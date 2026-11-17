import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/app.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/browse_cache.dart';
import 'package:lxserver_mobile/core/browse_snapshot.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/local_media/local_media_controller.dart';
import 'package:lxserver_mobile/shared/result_pagination.dart';
import 'package:lxserver_mobile/app/browse_navigation.dart';
import 'package:lxserver_mobile/features/search/entity_detail_screen.dart';
import 'package:lxserver_mobile/features/search/music_entity.dart';

class _MemoryBrowseStore extends BrowseSnapshotStore {
  @override
  Future<void> write(Map<String, dynamic> value) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final session = Session(
    Uri.parse('https://fixture.test'),
    'fixture',
    'fixture-token',
  );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('lx-session-test');
  });
  tearDown(() => root.delete(recursive: true));
  AppController controller(List<Uri> sent, {bool memory = false}) =>
      AppController(
        browseStore: memory ? _MemoryBrowseStore() : null,
        mediaDirectory: () async => root,
        api: LxApi(
          browseCache: BrowseCache(
            directory: () async => Directory('${root.path}/http'),
          ),
          client: MockClient((r) async {
            sent.add(r.url);
            Object data = {};
            if (r.url.path.endsWith('/verify')) data = {'valid': true};
            if (r.url.path == '/api/custom-source/list') {
              data = [
                {
                  'enabled': true,
                  'status': 'success',
                  'supportedSources': ['wy'],
                },
              ];
            }
            if (r.url.path == '/api/music/search') {
              final page = int.parse(r.url.queryParameters['page']!);
              data = {
                'list': List.generate(
                  20,
                  (i) => {
                    'songmid': '${(page - 1) * 20 + i}',
                    'source': 'wy',
                    'name': 'Fixture $i',
                  },
                ),
                'total': 200,
                'pageSize': 20,
                'hasMore': true,
              };
            }
            return http.Response(jsonEncode(data), 200);
          }),
        ),
      );
  Future<void> close(AppController c) async {
    await c.flushBrowseState();
    c.dispose();
    await c.playbackResume.flush();
    await c.localMedia.flush();
  }

  test('restart keeps noncontiguous native pages and positions without music queries', () async {
    final first = controller([]);
    await first.restore();
    first.session = session;
    await first.store.save(session);
    await first.setPagedCollections(true);
    await first.search('fixture');
    await first.ensureSearchPage(2, 20);
    first.homeTab = 0;
    first.rememberPage('home.search', {
      'page': 2,
      'offset': 120.0,
      'queryKey': 'fixture:false:wy:${first.searchRevision}:true:20',
    });
    first.savedRoutes = [
      {'type': 'settings'},
      {'type': 'downloads'},
    ];
    await close(first);
    final requests = <Uri>[];
    final second = controller(requests);
    await second.restore();
    expect(second.searchPageItems(2, 20).first.raw['songmid'], '40');
    expect(second.searchPageItems(1, 20), isEmpty);
    expect(second.pageState('home.search')['page'], 2);
    expect(second.pageState('home.search')['offset'], 120.0);
    expect(second.savedRoutes.map((e) => e['type']), ['settings', 'downloads']);
    expect(requests.where((r) => r.path.startsWith('/api/music/')), isEmpty);
    await second.logout();
    expect(await second.browseSnapshot.read(), isEmpty);
    await close(second);
  });

  testWidgets(
    'navigation stack restores settings then downloads and back returns through both',
    (tester) async {
      final c = controller([], memory: true)
        ..session = session
        ..restoring = false;
      c.library.hasSnapshot = true;
      c.savedRoutes = [
        {'type': 'settings'},
        {'type': 'downloads'},
      ];
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      expect(c.savedRoutes.map((e) => e['type']), ['settings', 'downloads']);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('个人中心'), findsOneWidget);
      expect(c.savedRoutes.single['type'], 'settings');
      navigator.pop();
      await tester.pumpAndSettle();
      expect(c.savedRoutes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  test('snapshot strips credentials and temporary resources, survives corruption and clear', () async {
    final store = BrowseSnapshotStore(directory: () async => root);
    await store.write({
      'server': 'https://fixture.test',
      'username': 'fixture',
      'pages': {
        'a': {
          'token': 'fixture-secret',
          'typeUrl': {'flac': 'temporary'},
          'img': 'https://fixture.test/image?signature=private',
          'page': 3,
        },
      },
    });
    final encoded = await File('${root.path}/browse-session-v2.json')
        .readAsString();
    expect(encoded, isNot(contains('fixture-secret')));
    expect(encoded, isNot(contains('temporary')));
    expect(encoded, isNot(contains('signature=private')));
    expect((await store.read())['pages']['a']['page'], 3);
    await File('${root.path}/browse-session-v2.json').writeAsString('{');
    expect(await store.read(), isEmpty);
    final pending = store.write({
      'pages': {'a': 1},
    });
    await store.clear();
    await pending;
    expect(await store.read(), isEmpty);
  });

  testWidgets(
    'restored detail keeps page three and reopens without fetching artist data',
    (tester) async {
      final sent = <Uri>[];
      final c = controller(sent, memory: true)
        ..session = session
        ..restoring = false
        ..pagedCollections = true;
      c.library.hasSnapshot = true;
      const entity = MusicEntity(
        {'id': 'fixture-artist', 'name': 'Fixture'},
        MusicSource.wy,
        true,
      );
      c.rememberPage('detail.entity:wy:true:fixture-artist', {
        'page': 2,
        'offset': 0,
        'model': {
          'entity': entity.raw,
          'songs': List.generate(
            45,
            (i) => {'songmid': '$i', 'source': 'wy', 'name': 'Fixture $i'},
          ),
          'albums': [],
          'order': 'hot',
        },
      });
      c.savedRoutes = [
        {'type': 'entity', 'source': 'wy', 'artist': true, 'data': entity.raw},
      ];
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ResultPagination>(find.byType(ResultPagination)).page,
        2,
      );
      expect(find.text('Fixture 40'), findsOneWidget);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pop();
      await tester.pumpAndSettle();
      navigator.push(
        browseRoute(EntityDetailScreen(controller: c, entity: entity)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<ResultPagination>(find.byType(ResultPagination)).page,
        2,
      );
      expect(
        sent.where(
          (r) =>
              r.path.endsWith('artistDetail') || r.path.endsWith('artistSongs'),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  test('cache defaults and persisted audio choice support five GB without replacing existing limit', () async {
    final cache = BrowseCache(
      directory: () async => Directory('${root.path}/browse'),
    );
    expect(cache.maxBytes, 128 * 1024 * 1024);
    await cache.setLimitMb(256);
    expect(cache.maxBytes, 256 * 1024 * 1024);
    final c = controller([]);
    await c.localMedia.activate(session);
    expect(c.localMedia.cacheLimitMb, 2048);
    await c.localMedia.setCacheLimit(5120);
    await c.localMedia.flush();
    expect(c.localMedia.cacheLimitMb, 5120);
    await c.localMedia.deactivate();
    await close(c);
    final other = controller([]);
    await other.localMedia.activate(session);
    expect(other.localMedia.cacheLimitMb, 5120);
    expect(LocalMediaController.cacheLimitsMb.last, 5120);
    await other.localMedia.deactivate();
    await close(other);
  });
}
