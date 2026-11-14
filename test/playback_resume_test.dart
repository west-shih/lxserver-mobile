import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/player/playback_resume.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = Session(
    Uri.parse('https://fixture.test'),
    'fixture',
    'fixture-token',
  );
  final songs = List.generate(
    3,
    (i) => Song({
      'songmid': '$i',
      'name': 'Song $i',
      'singer': 'Artist',
      'url': 'signed-audio',
      'img': 'https://cover.test/a?token=fixture-secret',
    }, MusicSource.kw),
  );
  PlaybackSnapshot snapshot({int seconds = 13}) => PlaybackSnapshot(
    scope: PlaybackSnapshot.scopeFor(session),
    songs: songs,
    index: 1,
    position: Duration(seconds: seconds),
    duration: const Duration(seconds: 120),
    quality: '320k',
    reportedQuality: '320k',
  );
  late Directory root;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('lx-playback-resume-');
  });
  tearDown(() async {
    expect(
      root.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      true,
    );
    if (await root.exists()) await root.delete(recursive: true);
  });
  test('Queue and progress survive restart without persisting credentials or audio URLs', () async {
    final store = PlaybackResumeStore(directory: () async => root);
    store.schedule(snapshot());
    store.schedule(snapshot(seconds: 22));
    await store.flush();
    final restored = await PlaybackResumeStore(directory: () async => root)
        .read(session);
    expect(restored!.songs.length, 3);
    expect(restored.songs[restored.index].id, songs[1].id);
    expect(restored.position.inSeconds, 22);
    expect(restored.quality, '320k');
    final value = await File('${root.path}/lx_playback.json').readAsString();
    for (final secret in ['signed-audio', 'fixture-token', 'fixture-secret']) {
      expect(value, isNot(contains(secret)));
    }
    expect(
      await store.read(Session(session.server, 'other', 'other-token')),
      null,
    );
    expect(
      await store.read(
        Session(
          Uri.parse('https://other.test'),
          session.username,
          session.token,
        ),
      ),
      null,
    );
    store.dispose();
  });
  test('Clear follows outstanding writes and allows the same state to be saved again', () async {
    final store = PlaybackResumeStore(directory: () async => root);
    store.schedule(snapshot(), immediately: true);
    await store.clear();
    expect(await store.read(session), null);
    store.schedule(snapshot(), immediately: true);
    await store.flush();
    expect(await store.read(session), isNotNull);
    store.schedule(snapshot(seconds: 22), immediately: true);
    store.schedule(snapshot(), immediately: true);
    await store.flush();
    expect((await store.read(session))!.position.inSeconds, 13);
    await File('${root.path}/lx_playback.json').writeAsString('{broken');
    expect(await store.read(session), null);
    store.dispose();
  });
  test(
    'Large queue includes the selected song and invalid snapshots are ignored',
    () {
      final queue = List.generate(
        2100,
        (i) => Song({'songmid': '$i'}, MusicSource.kw),
      );
      final value = PlaybackSnapshot(
        scope: PlaybackSnapshot.scopeFor(session),
        songs: queue,
        index: 2099,
        position: const Duration(seconds: 9),
        duration: const Duration(seconds: 3),
      ).toJson();
      final state = PlaybackSnapshot.parse(value, session)!;
      expect(state.songs.length, 2000);
      expect(state.songs[state.index].id, queue.last.id);
      expect(state.position.inSeconds, 3);
      expect(PlaybackSnapshot.parse({...value, 'index': -1}, session), null);
      expect(PlaybackSnapshot.parse({...value, 'version': 99}, session), null);
    },
  );
  for (final offline in [false, true]) {
    test(
      'Restore is paused without resolving audio; pending seek and empty queue persist ($offline)',
      () async {
        var audioRequests = 0;
        final c = AppController(
          mediaDirectory: () async => root,
          api: LxApi(
            client: MockClient((request) async {
              if (request.url.path.endsWith('/verify') && offline) {
                throw http.ClientException('Fixture offline');
              }
              if (request.url.path.endsWith('/url')) audioRequests++;
              return http.Response(jsonEncode({'valid': true}), 200);
            }),
          ),
        );
        await c.store.save(session);
        c.playbackResume.schedule(snapshot(), immediately: true);
        await c.playbackResume.flush();
        await c.restore();
        expect(c.player.current!.id, songs[1].id);
        expect(c.player.position.inSeconds, 13);
        expect(c.player.playing, false);
        expect(c.player.reportedQuality, '320k');
        expect(c.offlineMode, offline);
        expect(audioRequests, 0);
        await c.player.seek(const Duration(seconds: 25));
        await c.flushPlayback();
        expect((await c.playbackResume.read(session))!.position.inSeconds, 25);
        await c.player.reset();
        await c.flushPlayback();
        expect(await c.playbackResume.read(session), null);
        await c.localMedia.deactivate();
        await c.localMedia.flush();
        c.dispose();
        await c.playbackResume.flush();
      },
    );
  }
  test(
    'Rejected authentication clears both session and playback snapshot',
    () async {
      final c = AppController(
        mediaDirectory: () async => root,
        api: LxApi(client: MockClient((_) async => http.Response('{}', 401))),
      );
      await c.store.save(session);
      c.playbackResume.schedule(snapshot(), immediately: true);
      await c.playbackResume.flush();
      await c.restore();
      expect(c.session, null);
      expect(await c.store.read(), null);
      expect(await c.playbackResume.read(session), null);
      c.dispose();
      await c.playbackResume.flush();
    },
  );
}
