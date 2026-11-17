import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/core/browse_cache.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/search/entity_search_controller.dart';
import 'package:lxserver_mobile/features/search/music_entity.dart';
import 'package:lxserver_mobile/features/player/quality.dart';

void main() {
  late Directory root;
  late BrowseCache cache;
  final session = Session(
    Uri.parse('https://example.test'),
    'fixture',
    'fixture-token',
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lx-metadata-test');
    cache = BrowseCache(directory: () async => root);
  });
  tearDown(() => root.delete(recursive: true));
  http.Response result(int value) =>
      http.Response(jsonEncode({'value': value}), 200);
  const path = '/api/music/artistDetail';
  const query = {'source': 'wy', 'id': '42'};

  test('read-only comment POST caches while writes never do', () async {
    var sent = 0;
    final api = LxApi(
      browseCache: cache,
      client: MockClient((_) async => result(++sent)),
    );
    final song = Song({'songmid': '42'}, MusicSource.wy);
    await api.comments(session, song);
    await api.comments(session, song);
    expect(sent, 1);
    await api.refreshBrowse(() => api.comments(session, song));
    expect(sent, 2);
    await api.writeList(session, {});
    await api.writeList(session, {});
    expect(sent, 4);
  });

  test('cache-only restoration never sends a missing request', () async {
    var sent = 0;
    final api = LxApi(
      browseCache: cache,
      client: MockClient((_) async => result(++sent)),
    );
    await api.read(session, path, query: query);
    await api.cachedBrowseOnly(() => api.read(session, path, query: query));
    await expectLater(
      api.cachedBrowseOnly(
        () => api.read(session, path, query: {'source': 'wy', 'id': 'missing'}),
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(sent, 1);
  });

  test('server failure stops quality fallback after one resolution', () async {
    var sent = 0;
    final api = LxApi(
      client: MockClient((_) async {
        sent++;
        return http.Response('{}', 500);
      }),
    );
    await expectLater(
      loadWithQualityFallback(
        song: Song({'songmid': '42'}, MusicSource.wy),
        preference: 'flac',
        resolve: (_) async {
          await api.read(session, '/api/music/testFailure');
          throw StateError('unreachable');
        },
        load: (_) async {},
        isCurrent: () => true,
        onAttempt: (_) {},
      ),
      throwsA(
        isA<ApiFailure>().having((e) => e.kind, 'kind', FailureKind.server),
      ),
    );
    expect(sent, 1);
  });

  test(
    'restart reuses disk; explicit refresh replaces it; account is isolated',
    () async {
      var sent = 0;
      LxApi api() => LxApi(
        browseCache: BrowseCache(directory: () async => root),
        client: MockClient((_) async => result(++sent)),
      );
      expect(await api().read(session, path, query: query), {'value': 1});
      final restarted = api();
      expect(await restarted.read(session, path, query: query), {'value': 1});
      expect(sent, 1);
      expect(
        await restarted.refreshBrowse(
          () => restarted.read(session, path, query: query),
        ),
        {'value': 2},
      );
      expect(await api().read(session, path, query: query), {'value': 2});
      await restarted.read(
        Session(session.server, 'another', 'another-token'),
        path,
        query: query,
      );
      expect(sent, 3);
      final disk = (await root.list().toList()).whereType<File>();
      for (final file in disk) {
        expect(await file.readAsString(), isNot(contains('fixture-token')));
        expect(file.path, isNot(contains('fixture')));
      }
    },
  );

  test(
    'same in-flight request merges; failed refresh sends once and retains disk',
    () async {
      var sent = 0;
      var fail = false;
      final api = LxApi(
        browseCache: cache,
        client: MockClient((_) async {
          sent++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return fail ? http.Response('{}', 500) : result(sent);
        }),
      );
      await Future.wait(
        List.generate(5, (_) => api.read(session, path, query: query)),
      );
      expect(sent, 1);
      fail = true;
      await expectLater(
        api.refreshBrowse(() => api.read(session, path, query: query)),
        throwsA(isA<ApiFailure>()),
      );
      expect(sent, 2);
      expect(await api.read(session, path, query: query), {'value': 1});
      expect(sent, 2);
    },
  );

  test(
    'same platform serializes; stale queued query never reaches network',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final ids = <String>[];
      var current = true;
      final api = LxApi(
        client: MockClient((r) async {
          ids.add(r.url.queryParameters['id']!);
          if (ids.length == 1) {
            started.complete();
            await gate.future;
          }
          return result(1);
        }),
      );
      final first = api.read(session, path, query: query);
      await started.future;
      final queued = api.browseQuery(
        () => current,
        () => api.read(session, path, query: {'source': 'wy', 'id': '43'}),
      );
      final check = expectLater(queued, throwsA(isA<ApiFailure>()));
      current = false;
      gate.complete();
      await first;
      await check;
      expect(ids, ['42']);
    },
  );

  test('successful first-page refresh invalidates old later pages only in its family', () async {
    var sent = 0;
    final api = LxApi(
      browseCache: cache,
      client: MockClient((_) async => result(++sent)),
    );
    Future<Object> page(int page) => api.read(
      session,
      '/api/music/search',
      query: {
        'source': 'wy',
        'name': 'fixture',
        'page': '$page',
        'limit': '20',
      },
    );
    await page(1);
    await page(2);
    await api.read(session, path, query: query);
    await api.refreshBrowse(() => page(1));
    expect(sent, 4);
    await page(2);
    expect(sent, 5);
    await api.read(session, path, query: query);
    expect(sent, 5);
  });

  test(
    'clear rejects old in-flight writes and never caches private snapshots',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      var sent = 0;
      final api = LxApi(
        browseCache: cache,
        client: MockClient((_) async {
          sent++;
          if (sent == 1) {
            started.complete();
            await gate.future;
          }
          return result(sent);
        }),
      );
      final pending = api.read(session, path, query: query);
      await started.future;
      await cache.clear();
      gate.complete();
      await pending;
      expect(await cache.bytes(), 0);
      await api.read(session, path, query: query);
      expect(sent, 2);
      await api.read(session, '/api/user/list');
      await api.read(session, '/api/user/list');
      expect(sent, 4);
    },
  );

  test(
    'corrupt cache recovers; capacity eviction leaves usable JSON',
    () async {
      await File('${root.path}/broken.json').writeAsString('{');
      expect(await cache.read('missing'), isNull);
      final small = BrowseCache(directory: () async => root, maxBytes: 250);
      for (var i = 0; i < 8; i++) {
        await small.write('$i', {
          'data': List.filled(25, i),
        }, generation: small.generation);
      }
      expect(await small.bytes(), lessThanOrEqualTo(250));
    },
  );

  test('entity refresh failure keeps visible results and pagination', () async {
    var fail = false;
    final api = LxApi(
      browseCache: cache,
      client: MockClient(
        (_) async => fail
            ? http.Response('{}', 500)
            : http.Response(
                jsonEncode({
                  'list': [
                    {'id': '42', 'name': 'Fixture'},
                  ],
                  'total': 40,
                }),
                200,
              ),
      ),
    );
    final controller = EntitySearchController(api, () {})
      ..kind = SearchKind.artist;
    await controller.search(session, 'fixture');
    fail = true;
    await api.refreshBrowse(() => controller.search(session, 'fixture'));
    expect(controller.items.single.id, '42');
    expect(controller.page, 1);
    expect(controller.error, isNotNull);
    controller.dispose();
  });
}
