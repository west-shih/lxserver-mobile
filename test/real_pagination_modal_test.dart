import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/app.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/core/page_window.dart';
import 'package:lxserver_mobile/features/player/player_views.dart';
import 'package:lxserver_mobile/features/library/collection_screen.dart';
import 'package:lxserver_mobile/features/library/library_controller.dart';
import 'package:lxserver_mobile/features/search/source_availability.dart';
import 'package:lxserver_mobile/shared/app_modal.dart';
import 'package:lxserver_mobile/shared/page_jump_sheet.dart';
import 'package:lxserver_mobile/shared/result_pagination.dart';

final session = Session(
  Uri.parse('https://example.test'),
  'fixture',
  'fixture-token',
);
http.Response response(Object data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200);
Map<String, dynamic> song(int i) => {
  'songmid': '$i',
  'name': 'Track $i',
  'source': 'wy',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Footer input jumps directly to a reported search page without reading preceding pages',
    (tester) async {
      final calls = <int>[];
      final c =
          AppController(
              api: LxApi(
                client: MockClient((r) async {
                  if (r.url.path != '/api/music/search') return response([]);
                  final page = int.parse(r.url.queryParameters['page']!);
                  calls.add(page);
                  return response({
                    'list': List.generate(20, (i) => song((page - 1) * 20 + i)),
                    'total': 2000,
                    'pageSize': 20,
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
      expect(find.text('第 1 / 100 页'), findsOneWidget);
      await tester.tap(find.text('跳页'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('输入页码'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('page-jump-input')),
        '50',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳转至第 50 页'));
      await tester.pumpAndSettle();
      expect(calls, [1, 50]);
      expect(find.text('第 50 / 100 页'), findsOneWidget);
      expect(find.text('Track 980'), findsOneWidget);
      expect(c.songs.length, 40);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Playlist-song pagination uses the same jump panel and keeps the full loaded list',
    (tester) async {
      final c =
          AppController(
              api: LxApi(client: MockClient((_) async => response([]))),
            )
            ..session = session
            ..pagedCollections = true;
      final songs = List.generate(243, (i) => Song(song(i), MusicSource.wy));
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: c,
            collection: MusicCollection('fixture', 'Fixture', songs),
            editable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第 1 / 13 页'), findsOneWidget);
      await tester.tap(find.text('跳页'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('输入页码'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('page-jump-input')),
        '13',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳转至第 13 页'));
      await tester.pumpAndSettle();
      expect(find.text('Track 240'), findsOneWidget);
      expect(find.text('第 13 / 13 页'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  test('Empty or wrapped target pages do not replace cached results or cause automatic retries', () async {
    for (final wrapped in [false, true]) {
      final calls = <int>[];
      final c = AppController(
        api: LxApi(
          client: MockClient((r) async {
            if (r.url.path != '/api/music/search') return response([]);
            final page = int.parse(r.url.queryParameters['page']!);
            calls.add(page);
            return response({
              'list': page == 1 || wrapped ? List.generate(20, song) : [],
              'total': 2000,
              'pageSize': 20,
              'hasMore': true,
            });
          }),
        ),
      )..session = session;
      await c.search('fixture');
      await expectLater(c.ensureSearchPage(89, 20), throwsA(isA<ApiFailure>()));
      expect(calls, [1, 90]);
      expect(c.songs.length, 20);
      expect(c.searching, false);
      expect(c.searchError, isNotNull);
      expect(c.searchPageItems(0, 20).first.id, 'wy:0');
      c.dispose();
    }
  });

  test('Search retains reported totals and native page size instead of using cached count', () async {
    final api = LxApi(
      client: MockClient(
        (r) async => response({
          'list': List.generate(20, song),
          'total': 625,
          'allPage': 32,
          'pageSize': 20,
          'hasMore': true,
        }),
      ),
    );
    final page = await api.search(session, 'fixture', MusicSource.wy, 1);
    expect(page.total, 625);
    expect(page.pageSize, 20);
    expect(displayPageCount(page.total!, 30), 21);
    api.close();
  });

  test('A distant search jump fetches only target native pages and retains prior cached songs', () async {
    final calls = <int>[];
    final c = AppController(
      api: LxApi(
        client: MockClient((r) async {
          if (r.url.path != '/api/music/search') return response([]);
          final page = int.parse(r.url.queryParameters['page']!);
          calls.add(page);
          return response({
            'list': List.generate(20, (i) => song((page - 1) * 20 + i)),
            'total': 4000,
            'pageSize': 20,
            'hasMore': true,
          });
        }),
      ),
    )..session = session;
    await c.search('fixture');
    await c.ensureSearchPage(99, 20);
    expect(calls, [1, 100]);
    expect(c.searchPageItems(99, 20).first.id, 'wy:1980');
    expect(c.searchTotal, 4000);
    expect(c.songs.length, 40);
    await c.ensureSearchPage(0, 20);
    expect(calls, [1, 100]);
    expect(c.searchPageItems(0, 20).first.id, 'wy:0');
    c.dispose();
  });

  test(
    'Display sizes different from native size request only overlapping pages',
    () async {
      final calls = <int>[];
      final c = AppController(
        api: LxApi(
          client: MockClient((r) async {
            if (r.url.path != '/api/music/search') return response([]);
            final page = int.parse(r.url.queryParameters['page']!);
            calls.add(page);
            return response({
              'list': List.generate(20, (i) => song((page - 1) * 20 + i)),
              'total': 625,
              'pageSize': 20,
              'hasMore': true,
            });
          }),
        ),
      )..session = session;
      await c.search('fixture');
      await c.ensureSearchPage(6, 30);
      expect(calls, [1, 10, 11]);
      expect(
        c.searchPageItems(6, 30).map((v) => v.id),
        List.generate(30, (i) => 'wy:${180 + i}'),
      );
      c.dispose();
    },
  );

  test('Public playlist jumps use native limit and preserve reported totals and source identity', () async {
    final calls = <int>[];
    final c = AppController(
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
          calls.add(page);
          return response({
            'list': List.generate(
              36,
              (i) => {'id': '${(page - 1) * 36 + i}', 'name': 'List'},
            ),
            'total': 845,
            'limit': 36,
          });
        }),
      ),
    )..session = session;
    await c.discovery.changeSource(session, MusicSource.wy);
    await c.discovery.ensurePage(session, 40, 20);
    expect(calls, [1, 23]);
    expect(c.discovery.total, 845);
    expect(c.discovery.pageItems(40, 20).first.id, '800');
    expect(
      c.discovery.pageItems(40, 20).every((v) => v.source == MusicSource.wy),
      true,
    );
    c.dispose();
  });

  testWidgets(
    'Reported totals drive display pages; unknown totals show no invented denominator or extra player gap',
    (tester) async {
      final c = AppController()
        ..restoring = false
        ..session = session
        ..offlineMode = true
        ..pagedCollections = true
        ..keyword = 'fixture'
        ..hasMore = true
        ..songs = List.generate(40, (i) => Song(song(i), MusicSource.wy));
      c.player.enqueueAll(session, c.songs);
      c.player.index = 0;
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('第 1 页'), findsOneWidget);
      expect(find.textContaining('还有更多'), findsNothing);
      final mini = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(MiniPlayer),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((mini.margin! as EdgeInsets).top, 0);
      expect((mini.margin! as EdgeInsets).bottom, 0);
      await tester.tap(find.text('跳页'));
      await tester.pumpAndSettle();
      expect(find.text('当前第 1 页，已加载 2 页'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Aggregate search and public playlists remain continuous even when pagination is enabled',
    (tester) async {
      final c =
          AppController(
              api: LxApi(
                client: MockClient((r) async {
                  if (r.url.path.endsWith('/tags')) {
                    return response({
                      'sortList': [
                        {'id': 'native'},
                      ],
                    });
                  }
                  return response({
                    'list': List.generate(
                      40,
                      (i) => {'id': '$i', 'name': 'List $i'},
                    ),
                    'total': 40,
                    'limit': 40,
                  });
                }),
              ),
            )
            ..restoring = false
            ..session = session
            ..offlineMode = true
            ..aggregate = true
            ..pagedCollections = true
            ..keyword = 'fixture'
            ..availability = const SourceAvailability([
              MusicSource.wy,
              MusicSource.tx,
            ], 1)
            ..songs = List.generate(40, (i) => Song(song(i), MusicSource.wy));
      c.discovery.aggregate = true;
      await tester.pumpWidget(LxApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.byType(ResultPagination), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('歌单'),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.discovery.playlists.length, 80);
      expect(find.byType(ResultPagination), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Jump sheet validates input, confirms target, and supports wheel and cancellation',
    (tester) async {
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showPageJump(
                    context,
                    currentPage: 7,
                    maxPage: 31,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsOneWidget);
      await tester.tap(find.text('输入页码'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('page-jump-input'));
      await tester.enterText(field, '32');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(field, '12');
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳转至第 12 页'));
      await tester.pumpAndSettle();
      expect(result, 11);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('page-jump-wheel')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result, isNot(7));
      expect(result, inInclusiveRange(0, 30));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Jump input remains scrollable on narrow large-text screens with keyboard insets',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.6),
              viewInsets: const EdgeInsets.only(bottom: 260),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showPageJump(context, currentPage: 0, maxPage: 1000),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('输入页码'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('page-jump-input'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '900');
      await tester.pumpAndSettle();
      expect(find.text('900'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Destructive confirmations share warning styling and cancel never invokes the action',
    (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final yes = await showAppDialog<bool>(
                    context: context,
                    dangerous: true,
                    builder: (dialog) => AlertDialog(
                      title: const Text('删除？'),
                      content: const Text('请确认操作。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true) actions++;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(find.byType(FilledButton)));
      expect(
        theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
        modalDanger,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(actions, 0);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(actions, 1);
    },
  );
}
