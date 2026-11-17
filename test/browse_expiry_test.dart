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

void main() {
  late Directory root;
  late DateTime now;
  late BrowseCache cache;
  final session = Session(
    Uri.parse('https://example.test'),
    'fixture',
    'fixture-token',
  );
  const path = '/api/music/songList/list';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lx-expiry-test');
    now = DateTime.utc(2026, 11, 17);
    cache = BrowseCache(directory: () async => root, now: () => now);
  });
  tearDown(() => root.delete(recursive: true));

  test('freshness uses fetch time, survives restart, and handles legacy and clock rollback', () async {
    await cache.write('key', {'value': 1}, generation: cache.generation);
    now = now.add(const Duration(minutes: 59));
    await cache.read('key'); // LRU access must not extend freshness.
    expect(await cache.isFresh('key', const Duration(hours: 1)), isTrue);
    now = now.add(const Duration(minutes: 1));
    final restarted = BrowseCache(directory: () async => root, now: () => now);
    expect(await restarted.isFresh('key', const Duration(hours: 1)), isFalse);
    expect(await restarted.read('key'), {'value': 1});
    now = now.subtract(const Duration(hours: 2));
    expect(await restarted.isFresh('key', const Duration(hours: 1)), isFalse);
    await File('${root.path}/${BrowseCache.digest('legacy')}.json')
        .writeAsString(
          jsonEncode({
            'version': 1,
            'data': {'value': 2},
          }),
        );
    expect(await cache.read('legacy'), {'value': 2});
    expect(await cache.isFresh('legacy', const Duration(days: 7)), isFalse);
    expect(BrowseCache.lifetime(path), const Duration(hours: 1));
    expect(
      BrowseCache.lifetime('/api/music/search'),
      const Duration(hours: 24),
    );
    expect(
      BrowseCache.lifetime('/api/music/songList/detail'),
      const Duration(hours: 24),
    );
    expect(
      BrowseCache.lifetime('/api/music/artistDetail'),
      const Duration(days: 7),
    );
  });

  test('only entry revalidation checks expiry; successful refresh invalidates sibling pages', () async {
    var sent = 0;
    final api = LxApi(
      browseCache: cache,
      client: MockClient(
        (_) async => http.Response(jsonEncode({'value': ++sent}), 200),
      ),
    );
    Future<Object> page(int n) =>
        api.read(session, path, query: {'page': '$n', 'source': 'wy'});
    await page(1);
    await page(2);
    expect(
      await api.revalidateBrowse(() async {
        await page(1);
      }),
      isFalse,
    );
    expect(sent, 2);
    now = now.add(const Duration(hours: 1));
    expect(await page(2), {'value': 2});
    await api.cachedBrowseOnly(() => page(1));
    expect(sent, 2);
    expect(
      await api.revalidateBrowse(() async {
        await page(1);
      }),
      isTrue,
    );
    expect(sent, 3);
    await page(2);
    expect(sent, 4);
  });

  test('partial failure, cancellation and cache clear never commit staged responses', () async {
    var sent = 0;
    var fail = false;
    final api = LxApi(
      browseCache: cache,
      client: MockClient((r) async {
        sent++;
        if (fail && r.url.queryParameters['page'] == '2') {
          return http.Response('{}', 500);
        }
        return http.Response(jsonEncode({'value': sent}), 200);
      }),
    );
    Future<Object> page(int n) =>
        api.read(session, path, query: {'page': '$n'});
    await page(1);
    await page(2);
    now = now.add(const Duration(days: 1));
    fail = true;
    expect(
      await api.revalidateBrowse(() async {
        await page(1);
        await page(2);
      }),
      isFalse,
    );
    expect(await page(1), {'value': 1});
    expect(await page(2), {'value': 2});
    var current = true;
    expect(
      await api.revalidateBrowse(() async {
        await page(1);
        current = false;
      }, current: () => current),
      isFalse,
    );
    expect(await page(1), {'value': 1});
    expect(
      await api.revalidateBrowse(() async {
        await page(1);
        await cache.clear();
      }),
      isFalse,
    );
    expect(await cache.bytes(), 0);
  });

  test(
    'unauthorized revalidation propagates instead of hiding behind old cache',
    () async {
      var unauthorized = false;
      final api = LxApi(
        browseCache: cache,
        client: MockClient(
          (_) async => http.Response('{}', unauthorized ? 401 : 200),
        ),
      );
      await api.read(session, path);
      now = now.add(const Duration(days: 1));
      unauthorized = true;
      await expectLater(
        api.revalidateBrowse(() async {
          await api.read(session, path);
        }),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.unauthorized,
            'unauthorized',
            isTrue,
          ),
        ),
      );
    },
  );

  test('entity entry keeps old model visible, commits new first page, failure retains pagination', () async {
    var revision = 1, fail = false;
    Completer<void>? gate;
    final api = LxApi(
      browseCache: cache,
      client: MockClient((r) async {
        if (gate != null) await gate.future;
        if (fail) return http.Response('{}', 500);
        return http.Response(
          jsonEncode({
            'list': [
              for (var i = 0; i < 20; i++)
                {
                  'id': '$revision-${r.url.queryParameters['page']}-$i',
                  'name': 'fixture',
                },
            ],
            'total': 100,
          }),
          200,
        );
      }),
    );
    final controller = EntitySearchController(api, () {})
      ..kind = SearchKind.artist;
    addTearDown(controller.dispose);
    await controller.search(session, 'fixture');
    await controller.search(session, 'fixture', more: true);
    expect(controller.page, 2);
    now = now.add(const Duration(days: 1));
    revision = 2;
    gate = Completer<void>();
    final update = controller.revalidate(session);
    expect(controller.items.first.id, '1-1-0');
    expect(controller.items.length, 40);
    gate.complete();
    await update;
    gate = null;
    expect(controller.items.first.id, '2-1-0');
    expect(controller.page, 1);
    await controller.search(session, 'fixture', more: true);
    now = now.add(const Duration(days: 1));
    fail = true;
    await controller.revalidate(session);
    expect(controller.items.first.id, '2-1-0');
    expect(controller.page, 2);
    expect(controller.items.length, 40);
  });
}
