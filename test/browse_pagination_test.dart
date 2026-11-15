import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/app.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/discovery/discovery_screen.dart';
import 'package:lxserver_mobile/shared/result_pagination.dart';
import 'package:lxserver_mobile/shared/song_tile.dart';

final session = Session(
  Uri.parse('https://example.test'),
  'fixture',
  'fixture-token',
);
http.Response response(Object data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200);
Map<String, dynamic> song(int i) => {
  'songmid': '$i',
  'source': 'wy',
  'name': 'Track $i',
};
int getRows(WidgetTester tester) =>
    (tester.widget<SliverList>(find.byType(SliverList).first).delegate
            as SliverChildBuilderDelegate)
        .childCount!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'One native sort is plain text, multiple sorts use a compact dropdown',
    (tester) async {
      final c = AppController(
        api: LxApi(
          client: MockClient(
            (r) async => response(
              r.url.path.endsWith('/tags')
                  ? {
                      'tags': [],
                      'sortList': [
                        {'id': 'native', 'name': '推荐'},
                      ],
                    }
                  : {'list': []},
            ),
          ),
        ),
      )..session = session;
      await c.discovery.changeSource(session, MusicSource.wy);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DiscoveryScreen(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.text('推荐'), findsOneWidget);
      final button = find.widgetWithText(TextButton, '全部分类');
      final gap =
          tester.getTopLeft(button).dy -
          tester.getBottomLeft(find.byType(ChoiceChip).first).dy;
      expect(gap, lessThanOrEqualTo(8));
      c.discovery.sorts = [
        {'id': 'native', 'name': '推荐'},
        {'id': 'new', 'name': '最新'},
      ];
      c.discovery.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Search paginates loaded results, keeps full playback queue and reacts to the common setting',
    (tester) async {
      final c = AppController()
        ..restoring = false
        ..session = session
        ..offlineMode = true
        ..pagedCollections = true
        ..keyword = 'fixture'
        ..songs = List.generate(65, (i) => Song(song(i), MusicSource.wy));
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      expect(getRows(tester), 20);
      expect(
        tester.widget<SongTile>(find.byType(SongTile).first).queue.length,
        65,
      );
      expect(tester.getSize(find.byType(ResultPagination)).height, 32);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('Track 20'), findsOneWidget);
      expect(find.text('Track 0'), findsNothing);
      await c.setCollectionPageSize(10);
      await tester.pumpAndSettle();
      expect(find.text('Track 0'), findsOneWidget);
      expect(getRows(tester), 10);
      await c.setPagedCollections(false);
      await tester.pumpAndSettle();
      expect(find.byType(ResultPagination), findsNothing);
      expect(getRows(tester), 65);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'A larger search display page fills from native pages and the last page keeps its remainder',
    (tester) async {
      final pages = <int>[];
      final c =
          AppController(
              api: LxApi(
                client: MockClient((r) async {
                  if (r.url.path != '/api/music/search') return response([]);
                  final page = int.parse(r.url.queryParameters['page']!);
                  pages.add(page);
                  return response({
                    'list': List.generate(3, (i) => song((page - 1) * 3 + i)),
                    'hasMore': page < 4,
                  });
                }),
              ),
            )
            ..restoring = false
            ..session = session
            ..pagedCollections = true
            ..collectionPageSize = 10;
      await c.search('fixture');
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      expect(pages, [1, 2, 3, 4]);
      expect(getRows(tester), 10);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(getRows(tester), 2);
      expect(find.text('Track 10'), findsOneWidget);
      expect(
        tester.widget<SongTile>(find.byType(SongTile).first).queue.length,
        12,
      );
      expect(pages, [1, 2, 3, 4]);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Public playlist display pages use the same page size and do not change native requests',
    (tester) async {
      final pages = <int>[];
      final c =
          AppController(
              api: LxApi(
                client: MockClient((r) async {
                  if (r.url.path.endsWith('/tags')) {
                    return response({
                      'tags': [],
                      'sortList': [
                        {'id': 'native', 'name': '推荐'},
                      ],
                    });
                  }
                  final page = int.parse(r.url.queryParameters['page']!);
                  pages.add(page);
                  expect(r.url.queryParameters.containsKey('limit'), false);
                  return response({
                    'list': List.generate(
                      3,
                      (i) => {
                        'id': '${(page - 1) * 3 + i}',
                        'name': 'List ${(page - 1) * 3 + i}',
                      },
                    ),
                    'total': 12,
                    'limit': 3,
                  });
                }),
              ),
            )
            ..session = session
            ..pagedCollections = true
            ..collectionPageSize = 10;
      await c.discovery.changeSource(session, MusicSource.wy);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DiscoveryScreen(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(pages, [1, 2, 3, 4]);
      expect(getRows(tester), 10);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(getRows(tester), 2);
      expect(find.text('List 10'), findsOneWidget);
      await c.setCollectionPageSize(20);
      await tester.pumpAndSettle();
      expect(getRows(tester), 12);
      expect(find.byType(ResultPagination), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Switching platform during a page request cannot advance the new query',
    (tester) async {
      final old = Completer<http.Response>();
      final c =
          AppController(
              api: LxApi(
                client: MockClient((r) async {
                  if (r.url.path != '/api/music/search') return response([]);
                  if (r.url.queryParameters['source'] == 'tx') {
                    return response({
                      'list': List.generate(
                        25,
                        (i) => {'songmid': 'new$i', 'name': 'New query $i'},
                      ),
                      'hasMore': false,
                    });
                  }
                  if (r.url.queryParameters['page'] == '2') return old.future;
                  return response({
                    'list': List.generate(20, song),
                    'hasMore': true,
                  });
                }),
              ),
            )
            ..restoring = false
            ..session = session
            ..pagedCollections = true;
      await c.search('fixture');
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'QQ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('New query 20'), findsOneWidget);
      old.complete(
        response({
          'list': [song(99)],
          'hasMore': false,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('New query 20'), findsOneWidget);
      expect(find.text('Track 99'), findsNothing);
      expect(find.byType(ResultPagination), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'Failed page filling keeps current results and does not loop or advance to a blank page',
    (tester) async {
      var calls = 0;
      final c =
          AppController(
              api: LxApi(
                client: MockClient((r) async {
                  if (r.url.path != '/api/music/search') return response([]);
                  calls++;
                  if (r.url.queryParameters['page'] == '2') {
                    return http.Response('{}', 503);
                  }
                  return response({
                    'list': List.generate(3, song),
                    'hasMore': true,
                  });
                }),
              ),
            )
            ..restoring = false
            ..session = session
            ..pagedCollections = true
            ..collectionPageSize = 10;
      await c.search('fixture');
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(getRows(tester), 3);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(calls, 3);
      expect(
        tester.widget<ResultPagination>(find.byType(ResultPagination)).page,
        0,
      );
      expect(find.text('Track 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
