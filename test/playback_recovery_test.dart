import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/player/playback_cache.dart';
import 'package:lxserver_mobile/features/player/quality.dart';

void main() {
  test(
    'Unavailable online sources do not hide a lower-quality server file',
    () async {
      final track = Song({'songmid': 'cached-only'}, MusicSource.kw);
      var resolves = 0;
      final result = await loadWithQualityFallback(
        song: track,
        preference: 'flac',
        serverCache: (q) async => q == '320k'
            ? PlaybackResource(
                Uri.parse('https://fixture.test/cache'),
                '320k',
                '320k',
                serverCached: true,
              )
            : null,
        resolve: (_) async {
          resolves++;
          throw const ApiFailure(
            'No configured source',
            kind: FailureKind.sourceUnavailable,
          );
        },
        load: (_) async {},
        isCurrent: () => true,
        onAttempt: (_) {},
      );
      expect(result!.serverCached, true);
      expect(result.requestedQuality, '320k');
      expect(resolves, 1);
    },
  );
  test('Fresh results containing platform placeholders are not a complete quality list', () {
    final partial = Song(
      {
        'types': [
          {'type': '128k'},
          {'type': 'flac', 'isPlatformQuality': true},
        ],
      },
      MusicSource.tx,
      freshQualityMetadata: true,
    );
    expect(QualityPolicy.attempts(partial, 'flac').first, 'flac');
  });
  final session = Session(
    Uri.parse('https://fixture.test/prefix'),
    'fixture',
    'fixture-token',
  );
  final song = Song({
    'songmid': 'fixture',
    'name': 'Fixture',
    'singer': 'Artist',
  }, MusicSource.tx);
  PlaybackResource resource(
    String q, {
    String source = 'a',
    bool more = false,
  }) => PlaybackResource(
    Uri.parse('https://media.test/$source/$q'),
    q,
    q,
    sourceId: source,
    hasMoreSources: more,
  );

  test('Reusable URL skips the server cache check and resolver', () async {
    final events = <String>[];
    final cache = PlaybackCache()..success('scope', song, resource('flac'));
    final result = await loadWithQualityFallback(
      song: song,
      preference: 'flac',
      cache: cache,
      scope: 'scope',
      serverCache: (q) async {
        events.add('server:$q');
        return PlaybackResource(
          Uri.parse('https://fixture.test/cache'),
          q,
          q,
          serverCached: true,
        );
      },
      resolve: (_) async => throw StateError('Unnecessary resolution'),
      load: (r) async => events.add(r.serverCached ? 'file' : 'link'),
      isCurrent: () => true,
      onAttempt: (_) {},
    );
    expect(result!.serverCached, false);
    expect(events, ['link']);
  });
  test(
    'Connection failure uses a local fallback without changing preference',
    () async {
      final cache = PlaybackCache()
        ..success('scope', song, resource('flac'), preference: 'flac');
      cache.invalidateUrl('scope', song, 'flac');
      var resolves = 0;
      final result = await loadWithQualityFallback(
        song: song,
        preference: 'flac',
        cache: cache,
        scope: 'scope',
        recoverPlaybackConnection: true,
        localFile: (q) async => q == '320k'
            ? PlaybackResource(Uri.file('/fixture.mp3'), q, q, localFile: true)
            : null,
        resolve: (_) async {
          resolves++;
          throw const ApiFailure(
            'Disconnected',
            kind: FailureKind.network,
            connectionFailed: true,
          );
        },
        load: (_) async {},
        isCurrent: () => true,
        onAttempt: (_) {},
      );
      expect(result?.requestedQuality, '320k');
      expect(resolves, 1);
      expect(cache.successful('scope', song, preference: 'flac'), 'flac');
    },
  );

  test('Playback resolution retries a connection failure only once', () async {
    var resolves = 0;
    final disconnected = http.ClientException('Connection closed');
    final api = LxApi(
      client: MockClient((_) async {
        resolves++;
        throw disconnected;
      }),
    );
    addTearDown(api.close);
    await expectLater(
      loadWithQualityFallback(
        song: song,
        preference: 'flac',
        recoverPlaybackConnection: true,
        resolve: (q) => api.resolvePlayback(session, song, quality: q),
        load: (_) async {},
        isCurrent: () => true,
        onAttempt: (_) {},
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.connectionFailed,
          'connectionFailed',
          true,
        ),
      ),
    );
    expect(resolves, 2);
  });

  test('Only confirmed server cache misses suppress repeated checks', () async {
    var checks = 0;
    final api = LxApi(
      client: MockClient((_) async {
        if (++checks == 1) throw http.ClientException('Disconnected');
        return http.Response('{"exists":false}', 200);
      }),
    );
    addTearDown(api.close);
    expect(await api.cachedPlayback(session, song, 'flac'), null);
    expect(await api.cachedPlayback(session, song, 'flac'), null);
    expect(await api.cachedPlayback(session, song, 'flac'), null);
    expect(checks, 2);
  });
  test(
    'Broken server file falls through to streaming at the same quality',
    () async {
      final result = await loadWithQualityFallback(
        song: song,
        preference: 'flac',
        serverCache: (q) async => PlaybackResource(
          Uri.parse('https://fixture.test/cache'),
          q,
          q,
          serverCached: true,
        ),
        resolve: (q) async => resource(q),
        load: (r) async {
          if (r.serverCached) throw StateError('Stale file');
        },
        isCurrent: () => true,
        onAttempt: (_) {},
      );
      expect(result!.requestedQuality, 'flac');
      expect(result.serverCached, false);
    },
  );
  test(
    'Load failure excludes its source before trying a lower quality',
    () async {
      final attempts = <String>[];
      final result = await loadWithQualityFallback(
        song: song,
        preference: 'flac',
        resolve: (_) async => throw StateError('Wrong resolver'),
        resolveFromSources: (q, excluded) async {
          attempts.add('$q:${excluded.join(',')}');
          return resource(
            q,
            source: excluded.isEmpty ? 'a' : 'b',
            more: excluded.isEmpty,
          );
        },
        load: (r) async {
          if (r.sourceId == 'a') throw StateError('Bad URL');
        },
        isCurrent: () => true,
        onAttempt: (_) {},
      );
      expect(result!.sourceId, 'b');
      expect(result.requestedQuality, 'flac');
      expect(attempts, ['flac:', 'flac:a']);
    },
  );
  test(
    'Network failure stops recovery without recording a quality failure',
    () async {
      final cache = PlaybackCache();
      var calls = 0;
      await expectLater(
        loadWithQualityFallback(
          song: song,
          preference: 'flac',
          cache: cache,
          scope: 'scope',
          recoverPlaybackConnection: true,
          resolve: (q) async {
            calls++;
            throw const ApiFailure('Offline', kind: FailureKind.network);
          },
          load: (_) async {},
          isCurrent: () => true,
          onAttempt: (_) {},
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls, 1);
      expect(cache.failed('scope', song, 'flac'), false);
    },
  );
  test(
    'Legacy history without a preference binding is not reused blindly',
    () async {
      var now = DateTime.utc(2026, 11, 14);
      final cache = PlaybackCache(now: () => now);
      cache.success('scope', song, resource('128k'));
      cache.failure('scope', song, 'flac');
      now = now.add(const Duration(seconds: 31));
      final calls = <String>[];
      final result = await loadWithQualityFallback(
        song: song,
        preference: 'flac',
        cache: cache,
        scope: 'scope',
        resolve: (q) async {
          calls.add(q);
          return resource(q);
        },
        load: (_) async {},
        isCurrent: () => true,
        onAttempt: (_) {},
      );
      expect(result!.requestedQuality, 'flac');
      expect(calls, ['flac']);
    },
  );
  test('Recovery request count and elapsed budget are bounded', () async {
    var calls = 0;
    await expectLater(
      loadWithQualityFallback(
        song: song,
        preference: 'flac',
        maxResolutions: 2,
        resolve: (q) async {
          calls++;
          throw const ApiFailure('Unavailable');
        },
        load: (_) async {},
        isCurrent: () => true,
        onAttempt: (_) {},
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, 2);
    await expectLater(
      loadWithQualityFallback(
        song: song,
        preference: 'flac',
        recoveryBudget: Duration.zero,
        resolve: (q) async {
          calls++;
          return resource(q);
        },
        load: (_) async {},
        isCurrent: () => true,
        onAttempt: (_) {},
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, 2);
  });
  test(
    'Server cache contract handles prefix, identity and credentials safely',
    () async {
      var body = <String, dynamic>{
        'exists': true,
        'quality': 'flac',
        'url': '/api/music/cache/file/fixture/test.flac?token=fixture-token',
      };
      final api = LxApi(
        client: MockClient((r) async {
          expect(r.url.path, '/prefix/api/music/cache/check');
          expect(r.url.queryParameters['exactQuality'], '1');
          expect(r.headers['x-user-token'], session.token);
          return http.Response(jsonEncode(body), 200);
        }),
      );
      addTearDown(api.close);
      final hit = await api.cachedPlayback(session, song, 'flac');
      expect(hit!.serverCached, true);
      expect(hit.url.path, '/prefix/api/music/cache/file/fixture/test.flac');
      body = {...body, 'isCollision': true};
      expect(await api.cachedPlayback(session, song, 'flac'), null);
      body.remove('isCollision');
      body['quality'] = '128k';
      expect(await api.cachedPlayback(session, song, 'flac'), null);
      body['quality'] = 'flac';
      body['url'] =
          'https://other.test/api/music/cache/file/a?token=fixture-token';
      expect(await api.cachedPlayback(session, song, 'flac'), null);
    },
  );
  test(
    'Resolver sends excluded source IDs and preserves server retry metadata',
    () async {
      final api = LxApi(
        client: MockClient((r) async {
          expect(jsonDecode(r.body)['excludeApiSources'], ['a']);
          return http.Response(
            jsonEncode({
              'url': 'https://media.test/audio',
              'type': 'flac',
              'sourceId': 'b',
              'hasMoreSources': true,
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final result = await api.resolvePlayback(
        session,
        song,
        quality: 'flac',
        excludeApiSources: ['a'],
      );
      expect(result.sourceId, 'b');
      expect(result.hasMoreSources, true);
    },
  );
}
