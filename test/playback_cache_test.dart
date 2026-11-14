import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/player/playback_cache.dart';
import 'package:lxserver_mobile/features/player/quality.dart';

void main() {
  test(
    'Recent failures suppress repeated probing, manual retry bypasses it',
    () async {
      final cache = PlaybackCache();
      final track = Song({'songmid': 'failure'}, MusicSource.kw);
      var calls = 0;
      Future<PlaybackResource?> play() => loadWithQualityFallback(
        song: track,
        preference: 'flac',
        cache: cache,
        scope: 'fixture',
        resolve: (_) async {
          calls++;
          throw const ApiFailure('Unavailable');
        },
        load: (_) async {},
        isCurrent: () => true,
        onAttempt: (_) {},
      );
      await expectLater(play(), throwsA(isA<ApiFailure>()));
      expect(calls, 3);
      await expectLater(play(), throwsA(isA<ApiFailure>()));
      expect(calls, 3);
      cache.forget('fixture', track);
      await expectLater(play(), throwsA(isA<ApiFailure>()));
      expect(calls, 6);
      cache.restore('{"configuration":"","history":{"bad":{"failed":12}}}');
      expect(cache.failed('fixture', track, 'flac'), false);
    },
  );
  test('Successful quality is durable while URL expiry remains bounded', () {
    var now = DateTime.utc(2026, 11, 14);
    final cache = PlaybackCache(now: () => now);
    final session = Session(
      Uri.parse('https://fixture.test'),
      'fixture',
      'token',
    );
    final song = Song({'songmid': 'ttl'}, MusicSource.kw);
    final resource = PlaybackResource(
      Uri.parse('https://media.test/ttl'),
      '320k',
      '320k',
    );
    final scope = cache.scope(session);
    cache.success(scope, song, resource);
    now = now.add(const Duration(minutes: 4));
    cache.success(scope, song, resource, reusedUrl: true);
    now = now.add(const Duration(minutes: 2));
    expect(cache.resource(scope, song, '320k'), null);
    now = now.add(const Duration(hours: 5));
    cache.success(scope, song, resource);
    now = now.add(const Duration(hours: 1));
    expect(cache.successful(scope, song), '320k');
  });
  final session = Session(
    Uri.parse('https://fixture.test'),
    'fixture',
    'fixture-token',
  );
  Song song({bool fresh = false}) => Song(
    {
      'songmid': 'fixture-song',
      'types': [
        {'type': '128k'},
        {'type': '320k'},
      ],
    },
    MusicSource.tx,
    freshQualityMetadata: fresh,
  );
  PlaybackResource resource(String q) => PlaybackResource(
    Uri.parse('https://media.test/$q'),
    q,
    q,
    sourceId: 'fixture-source',
  );

  test(
    'Fresh metadata skips unavailable qualities; old lists still allow probing',
    () {
      expect(QualityPolicy.attempts(song(fresh: true), 'flac'), [
        '320k',
        '128k',
      ]);
      expect(QualityPolicy.initial(song(fresh: true), 'flac'), '320k');
      expect(QualityPolicy.attempts(song(), 'flac'), ['flac', '320k', '128k']);
      expect(
        QualityPolicy.attempts(
          song(fresh: true),
          'flac',
          respectMetadata: false,
        ).first,
        'flac',
      );
    },
  );
  test('Replay reuses successful quality and URL without resolution', () async {
    final cache = PlaybackCache();
    final scope = cache.scope(session);
    final calls = <String>[];
    Future<PlaybackResource?> play() => loadWithQualityFallback(
      song: song(),
      preference: 'flac',
      cache: cache,
      scope: scope,
      resolve: (q) async {
        calls.add(q);
        if (q == 'flac') throw const ApiFailure('Unavailable');
        return resource(q);
      },
      load: (_) async {},
      isCurrent: () => true,
      onAttempt: (_) {},
    );
    expect((await play())!.requestedQuality, '320k');
    expect((await play())!.requestedQuality, '320k');
    expect(calls, ['flac', '320k']);
    expect(cache.failed(scope, song(), 'flac'), true);
  });
  test(
    'Expired cached URL is re-resolved at the same quality before downgrade',
    () async {
      final cache = PlaybackCache();
      final scope = cache.scope(session);
      cache.success(scope, song(), resource('flac'));
      var loads = 0;
      final calls = <String>[];
      final result = await loadWithQualityFallback(
        song: song(),
        preference: 'flac',
        cache: cache,
        scope: scope,
        resolve: (q) async {
          calls.add(q);
          return resource(q);
        },
        load: (_) async {
          if (++loads == 1) throw StateError('Expired URL');
        },
        isCurrent: () => true,
        onAttempt: (_) {},
      );
      expect(result!.requestedQuality, 'flac');
      expect(calls, ['flac']);
      expect(loads, 2);
      expect(cache.failed(scope, song(), 'flac'), false);
    },
  );
  test(
    'TTL expiry and manual retry clear suppression without changing preference',
    () {
      var now = DateTime.utc(2026, 11, 14);
      final cache = PlaybackCache(now: () => now);
      final scope = cache.scope(session);
      cache.success(scope, song(), resource('320k'));
      cache.failure(scope, song(), 'flac');
      now = now.add(const Duration(minutes: 3));
      expect(cache.failed(scope, song(), 'flac'), false);
      expect(cache.resource(scope, song(), '320k'), isNotNull);
      now = now.add(const Duration(minutes: 3));
      expect(cache.resource(scope, song(), '320k'), null);
      expect(cache.successful(scope, song()), '320k');
      cache.forget(scope, song());
      expect(cache.successful(scope, song()), null);
      cache.success(scope, song(), resource('320k'));
      now = now.add(const Duration(hours: 7));
      expect(cache.successful(scope, song()), '320k');
    },
  );
  test('Restarts restore result history but never signed media URLs', () async {
    String? saved;
    final cache = PlaybackCache(saveHistory: (value) async => saved = value);
    cache.configure([
      {'id': 'source-a', 'enabled': true},
    ]);
    final scope = cache.scope(session);
    cache.success(scope, song(), resource('320k'));
    cache.failure(scope, song(), 'flac');
    await cache.flush();
    expect(saved, isNot(contains('https://media.test')));
    final restored = PlaybackCache()..restore(saved);
    restored.configure([
      {'id': 'source-a', 'enabled': true},
    ]);
    expect(restored.successful(restored.scope(session), song()), '320k');
    expect(restored.failed(restored.scope(session), song(), 'flac'), false);
    expect(restored.resource(restored.scope(session), song(), '320k'), null);
  });
  test('Account, server and source configuration changes isolate or invalidate history', () {
    final cache = PlaybackCache();
    final scope = cache.scope(session);
    cache.success(scope, song(), resource('flac'));
    expect(
      cache.successful(
        cache.scope(Session(session.server, 'other', 'token')),
        song(),
      ),
      null,
    );
    expect(
      cache.successful(
        cache.scope(
          Session(Uri.parse('https://other.test'), session.username, 'token'),
        ),
        song(),
      ),
      null,
    );
    cache.configure([
      {'id': 'new-source', 'enabled': true},
    ]);
    expect(cache.successful(scope, song()), null);
    expect(cache.successful(cache.scope(session), song()), null);
  });
  test(
    'Cancelled and unauthorized requests never poison failure cache',
    () async {
      final cache = PlaybackCache();
      final scope = cache.scope(session);
      var current = true;
      await loadWithQualityFallback(
        song: song(),
        preference: 'flac',
        cache: cache,
        scope: scope,
        resolve: (_) async {
          current = false;
          throw const ApiFailure('Cancelled');
        },
        load: (_) async {},
        isCurrent: () => current,
        onAttempt: (_) {},
      );
      expect(cache.failed(scope, song(), 'flac'), false);
      await expectLater(
        loadWithQualityFallback(
          song: song(),
          preference: 'flac',
          cache: cache,
          scope: scope,
          resolve: (_) async =>
              throw const ApiFailure('Expired', unauthorized: true),
          load: (_) async {},
          isCurrent: () => true,
          onAttempt: (_) {},
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(cache.failed(scope, song(), 'flac'), false);
    },
  );
}
