import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/player/playback_cache.dart';
import 'package:lxserver_mobile/features/player/quality.dart';

void main() {
  test(
    'Restored spatial choice beats a standard local file and a changed default',
    () async {
      final song = Song({'songmid': 'spatial-fixture'}, MusicSource.tx);
      String? saved;
      final first = PlaybackCache(saveHistory: (value) async => saved = value);
      first.success(
        'scope',
        song,
        PlaybackResource(
          Uri.parse('https://media.test/spatial'),
          'atmos',
          'atmos',
        ),
        preference: 'flac',
      );
      await first.flush();
      final restored = PlaybackCache()..restore(saved);
      final localCalls = <String>[];
      final resolved = <String>[];
      final result = await loadWithQualityFallback(
        song: song,
        preference: '128k',
        cache: restored,
        scope: 'scope',
        localFile: (q) async {
          localCalls.add(q);
          return q == '128k'
              ? PlaybackResource(
                  Uri.file('/fixture.mp3'),
                  q,
                  q,
                  localFile: true,
                )
              : null;
        },
        resolve: (q) async {
          resolved.add(q);
          return PlaybackResource(Uri.parse('https://media.test/$q'), q, q);
        },
        load: (_) async {},
        isCurrent: () => true,
        onAttempt: (_) {},
      );
      expect(result!.requestedQuality, 'atmos');
      expect(localCalls, ['atmos']);
      expect(resolved, ['atmos']);
    },
  );

  test('A saved working quality survives a lower global default', () async {
    final track = Song({'songmid': 'bounded'}, MusicSource.tx);
    final cache = PlaybackCache()
      ..success(
        'scope',
        track,
        PlaybackResource(Uri.parse('https://media.test/flac'), 'flac', 'flac'),
        preference: '128k',
      );
    final result = await loadWithQualityFallback(
      song: track,
      preference: '128k',
      cache: cache,
      scope: 'scope',
      resolve: (q) async =>
          PlaybackResource(Uri.parse('https://media.test/$q'), q, q),
      load: (_) async {},
      isCurrent: () => true,
      onAttempt: (_) {},
    );
    expect(result!.requestedQuality, 'flac');
  });
  final song = Song({'songmid': 'remembered'}, MusicSource.tx);
  PlaybackResource resource(String q) =>
      PlaybackResource(Uri.parse('https://media.test/$q'), q, q);

  test('A week and a restart only refresh the working quality URL, not higher qualities', () async {
    var now = DateTime.utc(2026, 11, 14);
    String? saved;
    final cache = PlaybackCache(
      now: () => now,
      saveHistory: (value) async => saved = value,
    );
    final firstCalls = <String>[];
    await loadWithQualityFallback(
      song: song,
      preference: 'flac',
      cache: cache,
      scope: 'scope',
      resolve: (q) async {
        firstCalls.add(q);
        if (q == 'flac') throw const ApiFailure('Unavailable');
        return resource(q);
      },
      load: (_) async {},
      isCurrent: () => true,
      onAttempt: (_) {},
    );
    expect(firstCalls, ['flac', '320k']);
    await cache.flush();
    now = now.add(const Duration(days: 7));
    final restored = PlaybackCache(now: () => now)..restore(saved);
    final replayCalls = <String>[];
    final replay = await loadWithQualityFallback(
      song: song,
      preference: 'flac',
      cache: restored,
      scope: 'scope',
      resolve: (q) async {
        replayCalls.add(q);
        return resource(q);
      },
      load: (_) async {},
      isCurrent: () => true,
      onAttempt: (_) {},
    );
    expect(replay!.requestedQuality, '320k');
    expect(replayCalls, ['320k']);
  });
  test('Only explicit retry replaces the remembered track quality', () async {
    final cache = PlaybackCache()
      ..success('scope', song, resource('128k'), preference: 'flac');
    final changed = await loadWithQualityFallback(
      song: song,
      preference: '320k',
      cache: cache,
      scope: 'scope',
      resolve: (q) async => resource(q),
      load: (_) async {},
      isCurrent: () => true,
      onAttempt: (_) {},
    );
    expect(changed!.requestedQuality, '128k');
    cache.forget('scope', song);
    final retried = await loadWithQualityFallback(
      song: song,
      preference: 'flac',
      cache: cache,
      scope: 'scope',
      respectMetadata: false,
      resolve: (q) async => resource(q),
      load: (_) async {},
      isCurrent: () => true,
      onAttempt: (_) {},
    );
    expect(retried!.requestedQuality, 'flac');
  });
  test('Failure of the working quality allows a new selection', () async {
    final cache = PlaybackCache()
      ..success('scope', song, resource('320k'), preference: 'flac');
    final calls = <String>[];
    final result = await loadWithQualityFallback(
      song: song,
      preference: 'flac',
      cache: cache,
      scope: 'scope',
      resolve: (q) async {
        calls.add(q);
        if (q == '320k') throw const ApiFailure('Unavailable');
        return resource(q);
      },
      load: (r) async {
        if (r.requestedQuality == '320k') throw StateError('Expired/broken');
      },
      isCurrent: () => true,
      onAttempt: (_) {},
    );
    expect(calls, ['320k', '128k']);
    expect(result!.requestedQuality, '128k');
  });
  test(
    'Incomplete or changed metadata does not erase a proven working quality',
    () async {
      final cache = PlaybackCache()
        ..success('scope', song, resource('320k'), preference: 'flac');
      final fresh = Song(
        {
          'songmid': 'remembered',
          'types': [
            {'type': 'flac'},
          ],
        },
        MusicSource.tx,
        freshQualityMetadata: true,
      );
      final result = await loadWithQualityFallback(
        song: fresh,
        preference: 'flac',
        cache: cache,
        scope: 'scope',
        resolve: (q) async => resource(q),
        load: (_) async {},
        isCurrent: () => true,
        onAttempt: (_) {},
      );
      expect(result!.requestedQuality, '320k');
    },
  );
}
