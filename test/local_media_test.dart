import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/core/browse_cache.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/features/local_media/audio_transfer.dart';
import 'package:lxserver_mobile/features/local_media/local_media_controller.dart';

Uint8List fixtureWav() {
  final bytes = Uint8List(44 + 32768);
  final data = ByteData.sublistView(bytes);
  void text(int offset, String s) =>
      bytes.setRange(offset, offset + s.length, s.codeUnits);
  text(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 22050, Endian.little);
  data.setUint32(28, 44100, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, 32768, Endian.little);
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpServer server;
  late Uri url;
  var gets = 0;
  var leakedCredentials = false;
  final wav = fixtureWav();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  setUp(() async {
    HttpOverrides.global = null;
    root = await Directory.systemTemp.createTemp('lx-local-media-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    gets = 0;
    leakedCredentials = false;
    url = Uri.parse(
      'http://127.0.0.1:${server.port}/audio.wav?signature=fixture-only',
    );
    server.listen((request) async {
      gets++;
      if (request.headers.value('x-user-token') != null) {
        leakedCredentials = true;
      }
      if (request.uri.path == '/cover.png') {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
        await request.response.close();
        return;
      }
      try {
        request.response.headers.contentType = ContentType('audio', 'wav');
        final body = request.uri.path == '/bad'
            ? Uint8List.fromList('<html>not audio</html>'.codeUnits)
            : wav;
        request.response.contentLength = body.length;
        for (var offset = 0; offset < body.length; offset += 1024) {
          request.response.add(
            body.sublist(offset, (offset + 1024).clamp(0, body.length)),
          );
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        await request.response.close();
      } catch (_) {
        /* Cancellation intentionally closes the client socket. */
      }
    });
  });
  tearDown(() async {
    await server.close(force: true);
    final path = root.absolute.path;
    expect(path.startsWith(Directory.systemTemp.absolute.path), true);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'One progressive transfer serves ranges and produces a complete local file',
    () async {
      final t = await AudioTransfer.open(
        url,
        '${root.path}/range',
        cacheBudget: wav.length * 2,
      );
      final proxy = CachedAudioProxy();
      final local = await proxy.add(t);
      final client = HttpClient();
      final request = await client.getUrl(local);
      request.headers.set('Range', 'bytes=64-127');
      final range = await request.close();
      expect(range.statusCode, 206);
      expect(
        range.headers.value('Content-Range'),
        'bytes 64-127/${wav.length}',
      );
      final bytes = await range.expand((b) => b).toList();
      expect(bytes, wav.sublist(64, 128));
      await t.done;
      expect(await t.target.readAsBytes(), wav);
      expect(gets, 1);
      expect(leakedCredentials, false);
      await t.cancel();
      client.close(force: true);
      await proxy.close();
    },
  );
  test(
    'Closing a decoder request during transfer does not leak proxy errors',
    () async {
      final t = await AudioTransfer.open(url, '${root.path}/interrupted');
      final proxy = CachedAudioProxy();
      final client = HttpClient();
      final response = await (await client.getUrl(await proxy.add(t))).close();
      await response.first;
      client.close(force: true);
      proxy.clear();
      await t.cancel();
      await proxy.close();
      expect(await t.part.exists(), false);
      expect(t.complete, false);
    },
  );
  test('Over-budget audio bypasses caching and partial cancellation is never complete', () async {
    await expectLater(
      AudioTransfer.open(url, '${root.path}/small', cacheBudget: 16),
      throwsA(isA<CacheBypass>()),
    );
    final t = await AudioTransfer.open(url, '${root.path}/cancel');
    while (t.received == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await t.cancel();
    expect(t.complete, false);
    expect(await t.target.exists(), false);
    expect(await t.part.exists(), false);
  });
  test(
    'HTML disguised as a media response is not promoted into the cache',
    () async {
      final t = await AudioTransfer.open(
        url.replace(path: '/bad'),
        '${root.path}/bad',
      );
      await expectLater(t.done, throwsA(isA<ApiFailure>()));
      expect(t.complete, false);
      expect(await t.target.exists(), false);
      await t.cancel();
    },
  );

  final s = Session(
    Uri.parse('https://fixture.test'),
    'fixture-user',
    'fixture-token',
  );
  final song = Song({
    'songmid': 'local-fixture',
    'name': 'Local fixture',
    'singer': 'Test',
  }, MusicSource.kw);
  LocalMediaController media({
    http.Response Function()? lyrics,
    BrowseCache? browseCache,
  }) {
    final api = LxApi(
      browseCache: browseCache,
      client: MockClient((r) async {
        if (r.url.path == '/api/music/lyric' && lyrics != null) {
          return lyrics();
        }
        if (r.url.path.endsWith('/cache/check')) {
          return http.Response(jsonEncode({'exists': false}), 200);
        }
        return http.Response(
          jsonEncode({'url': url.toString(), 'type': 'flac'}),
          200,
        );
      }),
    );
    addTearDown(api.close);
    return LocalMediaController(api, () {}, directory: () async => root);
  }

  Future<void> settle(LocalMediaController m) async {
    for (
      var i = 0;
      i < 500 &&
          m.jobs.any(
            (j) => [
              DownloadState.queued,
              DownloadState.resolving,
              DownloadState.downloading,
            ].contains(j.state),
          );
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      m.jobs.where((j) => j.state == DownloadState.failed).map((j) => j.error),
      isEmpty,
    );
    await m.flush();
  }

  Future<void> close(LocalMediaController m) async {
    await m.deactivate();
    await m.flush();
    m.dispose();
  }

  test('Cached and downloaded audio keep independent lyrics', () async {
    const downloaded = '[00:01.00]Downloaded lyric';
    const cached = '[00:01.00]Cached lyric';
    var responseLyric = downloaded;
    var requests = 0;
    var online = true;
    final browse = BrowseCache(
      directory: () async => Directory('${root.path}/browse'),
    );
    LocalMediaController open() => media(
      browseCache: browse,
      lyrics: () {
        requests++;
        return online
            ? http.Response(jsonEncode({'lyric': responseLyric}), 200)
            : http.Response('{}', 503);
      },
    );
    const download = LocalLyricsKind.download;
    const cache = LocalLyricsKind.cache;
    final m = open();
    await m.enqueue(s, song, 'flac');
    await settle(m);
    expect((await m.lyrics(s, song, kind: download))['lyric'], downloaded);
    expect(requests, 1);
    online = false;
    await expectLater(
      m.lyrics(s, song, kind: cache),
      throwsA(isA<ApiFailure>()),
    );
    online = true;
    responseLyric = cached;
    final resource = PlaybackResource(url, '320k', '320k');
    final transfer = (await m.prepareCache(s, song, resource))!;
    await m.acceptCache(s, song, resource, transfer);
    await transfer.done;
    await m.acceptCache(s, song, resource, transfer);
    expect((await m.lyrics(s, song, kind: cache))['lyric'], cached);
    expect((await m.lyrics(s, song, kind: download))['lyric'], downloaded);
    expect(await browse.bytes(), 0);
    await browse.clear();
    await m.releasePlayback();
    await m.deleteDownload(m.downloads.single);
    expect((await m.localResource(s, song, '320k'))?.localFile, true);
    await close(m);
    final index = File('${root.path}/lx_audio/index.json');
    expect(jsonDecode(await index.readAsString())['downloadLyrics'], isNull);

    online = false;
    final restored = open();
    await restored.activate(s);
    expect((await restored.lyrics(s, song, kind: cache))['lyric'], cached);
    await restored.clearCache();
    expect(await restored.localResource(s, song, '320k'), isNull);
    await restored.flush();
    expect(jsonDecode(await index.readAsString())['cacheLyrics'], isNull);
    await expectLater(
      restored.lyrics(s, song, kind: cache),
      throwsA(isA<ApiFailure>()),
    );
    await close(restored);
  });

  test('server failure pauses later downloads on the same platform', () async {
    final gate = Completer<http.Response>();
    final started = Completer<void>();
    var resolutions = 0;
    final api = LxApi(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/cache/check')) {
          return http.Response('{"exists":false}', 200);
        }
        resolutions++;
        if (!started.isCompleted) started.complete();
        return gate.future;
      }),
    );
    final m = LocalMediaController(api, () {}, directory: () async => root);
    await m.enqueue(s, song, 'flac');
    await started.future;
    await m.enqueue(
      s,
      Song({'songmid': 'second-fixture'}, song.source),
      'flac',
    );
    gate.complete(http.Response('{}', 500));
    for (
      var i = 0;
      i < 100 && m.jobs.first.state != DownloadState.failed;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(resolutions, 1);
    expect(m.jobs.first.state, DownloadState.failed);
    expect(m.jobs.last.state, DownloadState.paused);
    await close(m);
    api.close();
  });

  test('Automatic caching is only labelled after completion and is reused without network', () async {
    final m = media();
    await m.activate(s);
    final r = PlaybackResource(url, 'flac', 'flac');
    final t = await m.prepareCache(s, song, r);
    expect(m.badge(song), null);
    await m.acceptCache(s, song, r, t!);
    await t.done;
    await m.acceptCache(s, song, r, t);
    expect(m.badge(song), '已缓存');
    expect(m.cacheBytes, wav.length);
    final local = await m.localResource(s, song, 'flac');
    expect(local!.localFile, true);
    expect(local.url.scheme, 'file');
    expect(gets, 1);
    await m.clearCache();
    expect(m.badge(song), '已缓存');
    await m.releasePlayback();
    expect(m.badge(song), null);
    expect(m.cacheBytes, 0);
    await close(m);
  });
  test('Legacy disabled audio cache migrates to two GB and persists', () async {
    final directory = Directory('${root.path}/lx_audio');
    await directory.create(recursive: true);
    final index = File('${directory.path}/index.json');
    await index.writeAsString(
      jsonEncode({'cacheLimitMb': 0, 'files': [], 'jobs': []}),
    );
    final m = media();
    await m.initialize();
    await m.flush();
    expect(m.cacheLimitMb, 2048);
    expect(LocalMediaController.cacheLimitsMb, isNot(contains(0)));
    expect(jsonDecode(await index.readAsString())['cacheLimitMb'], 2048);
    await m.setCacheLimit(0);
    expect(m.cacheLimitMb, 2048);
    await close(m);
  });
  test('Promoting a cache to download avoids another transfer and clearing cache preserves it', () async {
    final m = media();
    await m.activate(s);
    final r = PlaybackResource(url, 'flac', 'flac');
    final t = (await m.prepareCache(s, song, r))!;
    await m.acceptCache(s, song, r, t);
    await m.enqueue(s, song, 'flac');
    await settle(m);
    expect(m.badge(song), '已下载');
    expect(gets, 1);
    expect(m.downloads.length, 1);
    await m.releasePlayback();
    await m.clearCache();
    await m.setCacheLimit(0);
    await m.flush();
    expect(m.downloads.length, 1);
    expect(await m.localResource(s, song, 'flac'), isNotNull);
    final json = await File('${root.path}/lx_audio/index.json').readAsString();
    expect(json, isNot(contains('signature=')));
    expect(json, isNot(contains('fixture-token')));
    await close(m);
    final restored = media();
    await restored.activate(s);
    expect(restored.cacheLimitMb, 2048);
    expect(restored.downloads.length, 1);
    expect((await restored.localResource(s, song, 'flac'))!.localFile, true);
    await restored.activate(Session(s.server, 'other-user', 'other-token'));
    expect(restored.downloads, isEmpty);
    await restored.activate(s);
    expect(restored.downloads.length, 1);
    await close(restored);
  });
  test('A queued download persists an actual audio file and can be deleted independently', () async {
    final m = media();
    await m.activate(s);
    await m.enqueue(s, song, 'flac');
    await settle(m);
    expect(m.downloads.length, 1);
    expect(m.badge(song), '已下载');
    expect(leakedCredentials, false);
    final file = m.downloads.single;
    final local = await m.localResource(s, song, 'flac');
    expect(await File.fromUri(local!.url).readAsBytes(), wav);
    await m.pin(s, song, 'flac');
    await expectLater(m.deleteDownload(file), throwsA(isA<ApiFailure>()));
    await m.releasePlayback();
    await m.deleteDownload(file);
    expect(m.downloads, isEmpty);
    await close(m);
  });
  test('Interrupted jobs restore paused and explicit retry replaces only after success', () async {
    final m = media();
    await m.activate(s);
    await m.enqueue(s, song, 'flac');
    for (
      var i = 0;
      i < 200 &&
          !m.jobs.any(
            (j) => j.state == DownloadState.downloading && j.received > 0,
          );
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (m.jobs.isNotEmpty) {
      await m.pause(m.jobs.first);
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await m.flush();
    await close(m);
    final next = media();
    await next.activate(s);
    if (next.jobs.isNotEmpty) {
      expect(next.jobs.first.state, DownloadState.paused);
      next.resume(next.jobs.first);
      await settle(next);
    }
    expect(next.downloads.length, 1);
    final previous = await next.localResource(s, song, 'flac');
    final before = gets;
    await next.enqueue(s, song, 'flac', replace: true);
    await settle(next);
    final replaced = await next.localResource(s, song, 'flac');
    expect(gets, before + 1);
    expect(replaced!.url, isNot(previous!.url));
    expect(await File.fromUri(previous.url).exists(), false);
    await close(next);
  });
  test('An authenticated session and downloads restore while the server is offline', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final m = media();
    await m.activate(s);
    await m.enqueue(s, song, 'flac');
    await settle(m);
    await close(m);
    final c = AppController(
      api: LxApi(
        client: MockClient((_) async => throw http.ClientException('offline')),
      ),
      mediaDirectory: () async => root,
    );
    await c.store.save(s);
    await c.store.saveQuality('320k');
    await c.restore();
    expect(c.offlineMode, true);
    expect(c.session?.username, s.username);
    expect(c.localMedia.downloads.length, 1);
    expect(c.player.preferredQuality, '320k');
    expect(await c.localMedia.localResource(s, song, 'flac'), isNotNull);
    await c.localMedia.deactivate();
    await c.localMedia.flush();
    c.dispose();
  });
  test(
    'Capacity eviction removes oldest automatic cache and preserves downloads',
    () async {
      final base = Directory('${root.path}/lx_audio');
      await Directory('${base.path}/cache').create(recursive: true);
      await Directory('${base.path}/downloads').create();
      final entries = <LocalAudio>[];
      for (var i = 0; i < 3; i++) {
        final track = Song({'songmid': 'capacity-$i'}, MusicSource.kw);
        final id = LocalMediaController.fileKey(s, track, 'flac');
        final folder = i == 2 ? 'downloads' : 'cache';
        final size = i == 2 ? wav.length : 140 * 1024 * 1024;
        final f = File('${base.path}/$folder/$id.wav');
        final handle = await f.open(mode: FileMode.write);
        await handle.writeFrom(wav);
        await handle.truncate(size);
        await handle.close();
        entries.add(
          LocalAudio(
            id: id,
            scope: LocalMediaController.scopeFor(s),
            song: track,
            quality: 'flac',
            folder: folder,
            ext: '.wav',
            bytes: size,
            used: i,
          ),
        );
      }
      await File('${base.path}/index.json').writeAsString(
        jsonEncode({
          'cacheLimitMb': 256,
          'files': entries.map((e) => e.toJson()).toList(),
          'jobs': [],
        }),
      );
      final m = media();
      await m.activate(s);
      expect(m.cacheBytes, 140 * 1024 * 1024);
      expect(m.downloads.length, 1);
      expect(
        await File('${base.path}/cache/${entries.first.id}.wav').exists(),
        false,
      );
      expect(
        await File('${base.path}/cache/${entries[1].id}.wav').exists(),
        true,
      );
      await close(m);
    },
  );
  test(
    'LRU keeps recently played audio without prioritizing selected versions',
    () async {
      final base = Directory('${root.path}/lx_audio');
      await Directory('${base.path}/cache').create(recursive: true);
      final otherPlatform = Song({'songmid': 'local-fixture'}, MusicSource.tx);
      final entries = <LocalAudio>[];
      for (var i = 0; i < 3; i++) {
        final track = i == 2 ? otherPlatform : song;
        final quality = i == 1 ? '320k' : 'flac';
        final id = LocalMediaController.fileKey(s, track, quality);
        final handle = await File('${base.path}/cache/$id.wav')
            .open(mode: FileMode.write);
        await handle.writeFrom(wav);
        await handle.truncate(100 * 1024 * 1024);
        await handle.close();
        entries.add(
          LocalAudio(
            id: id,
            scope: LocalMediaController.scopeFor(s),
            song: track,
            quality: quality,
            folder: 'cache',
            ext: '.wav',
            bytes: 100 * 1024 * 1024,
            used: i == 1 ? DateTime.now().millisecondsSinceEpoch + 100000 : 0,
          ),
        );
      }
      await File('${base.path}/index.json').writeAsString(
        jsonEncode({
          'cacheLimitMb': 512,
          'files': entries.map((e) => e.toJson()).toList(),
          'jobs': [],
        }),
      );
      final m = media();
      await m.activate(s);
      // Looking up a file is not actual playback and must not change its use timestamp.
      await m.localResource(s, song, '320k');
      expect(m.fileFor(song, '320k')!.used, entries[1].used);
      m.confirmPlayback(s, song, 'flac');
      await close(m);
      final restored = media();
      await restored.activate(s);
      await restored.setCacheLimit(256);
      expect(await restored.localResource(s, song, '320k'), isNotNull);
      expect(await restored.localResource(s, song, 'flac'), isNotNull);
      // The least recently played file is evicted regardless of platform or selected quality.
      expect(await restored.localResource(s, otherPlatform, 'flac'), null);
      await close(restored);
    },
  );
  test('Downloaded artwork, URL and platform survive restart and cover is removed with last download', () async {
    final imageUrl = url.replace(path: '/cover.png', query: '').toString();
    final illustrated = Song({...song.raw, 'img': imageUrl}, MusicSource.kw);
    final m = media();
    await m.enqueue(s, illustrated, 'flac');
    await settle(m);
    await m.flushArtwork();
    await m.flush();
    final path = m.artworkPath(illustrated)!;
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
    );
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1);
    frame.image.dispose();
    codec.dispose();
    final count = gets;
    await close(m);
    final restored = media();
    await restored.activate(s);
    await restored.flushArtwork();
    expect(restored.downloads.single.song.image, imageUrl);
    expect(restored.downloads.single.song.source, MusicSource.kw);
    expect(restored.artworkPath(illustrated), path);
    expect(gets, count);
    await restored.deleteDownload(restored.downloads.single);
    expect(await File(path).exists(), false);
    await close(restored);
  });
  test(
    'Legacy downloads receive artwork only from matching platform and song ID',
    () async {
      final imageUrl = url.replace(path: '/cover.png', query: '').toString();
      final m = media();
      await m.enqueue(s, song, 'flac');
      await settle(m);
      m.updateArtwork([
        Song({...song.raw, 'source': 'tx', 'img': imageUrl}, MusicSource.tx),
      ]);
      await m.flushArtwork();
      expect(m.downloads.single.song.image, isEmpty);
      m.updateArtwork([
        Song({...song.raw, 'img': imageUrl}, MusicSource.kw),
      ]);
      await m.flushArtwork();
      await m.flush();
      expect(m.downloads.single.song.image, imageUrl);
      expect(m.artworkPath(song), isNotNull);
      final encoded = await File('${root.path}/lx_audio/index.json')
          .readAsString();
      expect(encoded, contains('/cover.png'));
      expect(encoded, isNot(contains('retainedQuality')));
      await close(m);
    },
  );
  test('Clearing one song defers active cache and preserves downloads and other songs', () async {
    final base = Directory('${root.path}/lx_audio');
    await Directory('${base.path}/cache').create(recursive: true);
    await Directory('${base.path}/downloads').create();
    final other = Song({'songmid': 'other'}, MusicSource.kw);
    final entries = <LocalAudio>[];
    for (var i = 0; i < 3; i++) {
      final track = i == 2 ? other : song;
      final quality = i == 1 ? '320k' : 'flac';
      final folder = i == 1 ? 'downloads' : 'cache';
      final id = LocalMediaController.fileKey(s, track, quality);
      await File('${base.path}/$folder/$id.wav').writeAsBytes(wav);
      entries.add(
        LocalAudio(
          id: id,
          scope: LocalMediaController.scopeFor(s),
          song: track,
          quality: quality,
          folder: folder,
          ext: '.wav',
          bytes: wav.length,
          used: i,
        ),
      );
    }
    await File('${base.path}/index.json').writeAsString(
      jsonEncode({
        'cacheLimitMb': 512,
        'files': entries.map((e) => e.toJson()).toList(),
        'jobs': [],
      }),
    );
    final m = media();
    await m.activate(s);
    await m.pin(s, song, 'flac');
    expect(await m.clearSongCache(song), true);
    expect(m.pendingRemoval(song, 'flac'), true);
    expect(await m.localResource(s, song, 'flac'), isNotNull);
    await m.releasePlayback();
    expect(await m.localResource(s, song, 'flac'), null);
    expect(await m.localResource(s, song, '320k'), isNotNull);
    expect(await m.localResource(s, other, 'flac'), isNotNull);
    expect(m.downloads.length, 1);
    await close(m);
  });
}
