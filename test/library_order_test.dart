import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/library/library_screen.dart';
import 'package:lxserver_mobile/features/library/collection_screen.dart';

class OrderFixture {
  Map<String, dynamic> data = {
    'unknown': 7,
    'loveList': [
      {'songmid': 'love', 'source': 'tx'},
    ],
    'defaultList': [],
    'userList': List.generate(
      4,
      (i) => {
        'id': 'list$i',
        'name': 'List $i',
        'extra': i,
        if (i == 0) ...{'source': 'tx', 'sourceListId': 'original'},
        'list': List.generate(
          40,
          (n) => {'songmid': '$i-$n', 'source': 'tx', 'name': 'Song $n'},
        ),
      },
    ),
  };
  Map<String, dynamic> settings = {'otherSetting': true};
  int writes = 0, settingsWrites = 0;
  bool denySettings = false;
  bool failReadback = false;

  bool deny = false;
  late final c =
      AppController(
          api: LxApi(
            client: MockClient((r) async {
              if (r.method == 'POST' && r.url.path == '/api/user/settings') {
                settingsWrites++;
                if (deny || denySettings) return http.Response('{}', 403);
                settings = jsonDecode(r.body) as Map<String, dynamic>;
                return http.Response('{"success":true}', 200);
              }
              if (r.method == 'POST') {
                writes++;
                if (deny) return http.Response('{}', 403);
                data = jsonDecode(r.body) as Map<String, dynamic>;
                return http.Response('{"success":true}', 200);
              }
              if (failReadback && settingsWrites > 0) {
                return http.Response('{}', 503);
              }
              return http.Response(
                jsonEncode(
                  r.url.path == '/api/user/list'
                      ? data
                      : r.url.path == '/api/user/settings'
                      ? settings
                      : [],
                ),
                200,
              );
            }),
          ),
        )
        ..session = Session(
          Uri.parse('https://example.test'),
          'fixture',
          'fixture-token',
        );
  Future<void> load() => c.library.load(c.session!);
  List<String> get ids =>
      (data['userList'] as List).map((v) => '${v['id']}').toList();
  Widget screen() => MaterialApp(
    home: Scaffold(body: LibraryScreen(controller: c)),
  );
}

Future<void> dragList(WidgetTester tester, {int from = 2, int to = 4}) async {
  final handles = find.byType(ReorderableDragStartListener);
  final start = tester.getCenter(handles.at(from));
  final end = tester.getCenter(handles.at(to));
  final gesture = await tester.startGesture(start);
  await tester.pump();
  await gesture.moveTo(start + const Offset(0, 25));
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.moveTo(end + const Offset(0, 15));
  await tester.pump(const Duration(milliseconds: 400));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'System playlists can move between custom lists and restore from server settings',
    (tester) async {
      final f = OrderFixture();
      await f.load();
      await tester.pumpWidget(f.screen());
      await tester.pumpAndSettle();
      await dragList(tester, from: 0, to: 3);
      final order = f.c.library.collections.map((v) => v.id).toList();
      expect(order.first, isNot('love'));
      expect(order.indexOf('love'), greaterThan(order.indexOf('list0')));
      expect(f.writes, 0);
      expect(f.settingsWrites, 1);
      expect(f.settings['favoriteSidebarOrder'], order);
      expect(f.settings['otherSetting'], true);
      f.c.library.reset();
      await f.load();
      expect(f.c.library.collections.map((v) => v.id), order);
      expect((f.data['loveList'] as List).single['songmid'], 'love');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  test('Full order preserves hidden webpage entries and latest unrelated account settings', () async {
    final f = OrderFixture();
    f.settings['favoriteSidebarOrder'] = [
      'artists',
      'love',
      'albums',
      'default',
      ...f.ids,
    ];
    await f.load();
    final before = f.c.library.collections.map((v) => v.id).toList();
    f.settings['otherSetting'] = 'updated elsewhere';
    final desired = ['list2', 'default', 'list0', 'love', 'list1', 'list3'];
    await f.c.library.reorderCollections(f.c.session!, desired, before);
    expect(f.settings['favoriteSidebarOrder'], [
      'artists',
      'list2',
      'albums',
      'default',
      'list0',
      'love',
      'list1',
      'list3',
    ]);
    expect(f.settings['otherSetting'], 'updated elsewhere');
    expect(f.ids, ['list2', 'list0', 'list1', 'list3']);
    expect(f.writes, 1);
    expect(f.settingsWrites, 1);
    f.c.dispose();
  });

  test(
    'Changed server display order rejects a stale drag before either write',
    () async {
      final f = OrderFixture();
      await f.load();
      final before = f.c.library.collections.map((v) => v.id).toList();
      f.settings['favoriteSidebarOrder'] = ['default', 'love', ...f.ids];
      await expectLater(
        f.c.library.reorderCollections(
          f.c.session!,
          before.reversed.toList(),
          before,
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(f.writes, 0);
      expect(f.settingsWrites, 0);
      f.c.dispose();
    },
  );

  test('Settings failure after list write reports partial save and never resubmits either write', () async {
    final f = OrderFixture()..denySettings = true;
    await f.load();
    final before = f.c.library.collections.map((v) => v.id).toList();
    await expectLater(
      f.c.library.reorderCollections(
        f.c.session!,
        before.reversed.toList(),
        before,
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.message,
          'partial save',
          contains('私人歌单顺序已保存'),
        ),
      ),
    );
    expect(f.writes, 1);
    expect(f.settingsWrites, 1);
    expect(f.ids, ['list3', 'list2', 'list1', 'list0']);
    expect(f.c.library.collections.map((v) => v.id), [
      'love',
      'default',
      ...f.ids,
    ]);
    expect(f.c.library.mutating, false);
    f.c.dispose();
  });

  test(
    'Confirmed display order survives failed readback without replaying writes',
    () async {
      final f = OrderFixture()..failReadback = true;
      await f.load();
      final before = f.c.library.collections.map((v) => v.id).toList();
      final desired = ['default', 'list0', 'love', 'list1', 'list2', 'list3'];
      await f.c.library.reorderCollections(f.c.session!, desired, before);
      expect(f.c.library.collections.map((v) => v.id), desired);
      expect(f.c.library.error, contains('已保存'));
      expect(f.writes, 0);
      expect(f.settingsWrites, 1);
      f.c.dispose();
    },
  );

  testWidgets(
    'Compact category chips switch content without changing playlist order',
    (tester) async {
      final f = OrderFixture();
      await f.load();
      await tester.pumpWidget(f.screen());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '歌手'));
      await tester.pumpAndSettle();
      expect(find.text('暂无收藏'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '歌单'));
      await tester.pumpAndSettle();
      expect(find.text('我的喜欢'), findsOneWidget);
      expect(f.writes + f.settingsWrites, 0);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  test(
    'Playlist order saves latest complete rows and leaves system lists intact',
    () async {
      final f = OrderFixture();
      await f.load();
      (f.data['userList'] as List)[2]['newMetadata'] = 'keep';
      await f.c.library.reorderCollections(
        f.c.session!,
        ['love', 'default', 'list2', 'list0', 'list1', 'list3'],
        ['love', 'default', ...f.ids],
      );
      expect(f.writes, 1);
      expect(f.ids, ['list2', 'list0', 'list1', 'list3']);
      expect(f.data['unknown'], 7);
      expect((f.data['userList'] as List).first['newMetadata'], 'keep');
      expect(((f.data['userList'] as List).first['list'] as List).length, 40);
      expect((f.data['loveList'] as List).single['songmid'], 'love');
      expect(f.c.library.collections.map((v) => v.id), [
        'love',
        'default',
        ...f.ids,
      ]);
      f.c.dispose();
    },
  );

  test('Stale and invalid playlist order is rejected before writing; no-op does not POST', () async {
    final f = OrderFixture();
    await f.load();
    final before = f.c.library.collections.map((v) => v.id).toList();
    f.settings['favoriteSidebarOrder'] = before;
    await f.c.library.reorderCollections(f.c.session!, before, before);
    expect(f.writes, 0);
    for (final ids in [
      <String>['list0'],
      <String>['love', 'list0', 'list1', 'list2'],
    ]) {
      await expectLater(
        f.c.library.reorderCollections(f.c.session!, ids, before),
        throwsA(isA<ApiFailure>()),
      );
    }
    final old = before;
    (f.data['userList'] as List).add({'id': 'new', 'name': 'New', 'list': []});
    await expectLater(
      f.c.library.reorderCollections(f.c.session!, old.reversed.toList(), old),
      throwsA(isA<ApiFailure>()),
    );
    expect(f.writes, 0);
    f.c.dispose();
  });

  testWidgets(
    'Drag handles reorder personal playlists with system entries also available',
    (tester) async {
      final f = OrderFixture();
      await f.load();
      await tester.pumpWidget(f.screen());
      await tester.pumpAndSettle();
      expect(find.byType(ReorderableDragStartListener), findsNWidgets(6));
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(find.byType(SegmentedButton<int>), findsNothing);
      await dragList(tester);
      expect(f.writes, 1);
      expect(f.ids, isNot(['list0', 'list1', 'list2', 'list3']));
      expect(f.c.library.collections.take(2).map((v) => v.id), [
        'love',
        'default',
      ]);
      expect(
        tester.getTopLeft(find.text('我的喜欢')).dy,
        lessThan(tester.getTopLeft(find.text('List 1')).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'A denied drag restores the previous order with an error and no automatic retry',
    (tester) async {
      final f = OrderFixture()..deny = true;
      await f.load();
      await tester.pumpWidget(f.screen());
      await tester.pumpAndSettle();
      await dragList(tester);
      expect(f.writes, 1);
      expect(f.c.library.collections.skip(2).map((v) => v.id), [
        'list0',
        'list1',
        'list2',
        'list3',
      ]);
      expect(
        tester.getTopLeft(find.text('List 0')).dy,
        lessThan(tester.getTopLeft(find.text('List 1')).dy),
      );
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'Long press opens linked operations; system lists have no edit menu',
    (tester) async {
      final f = OrderFixture();
      await f.load();
      await tester.pumpWidget(f.screen());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, '我的喜欢'))
            .onLongPress,
        isNull,
      );
      await tester.longPress(find.text('List 0'));
      await tester.pumpAndSettle();
      for (final title in ['重命名', '刷新同步', '打开原始歌单', '删除歌单']) {
        expect(find.text(title), findsOneWidget);
      }
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Renamed');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('Renamed'), findsOneWidget);
      expect(f.writes, 1);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'Playback toolbar scrolls up then stays under navigation in normal and editing modes',
    (tester) async {
      final f = OrderFixture();
      await f.load();
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: f.c,
            collection: f.c.library.collections[2],
            editable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toolbar = find.byKey(const ValueKey('collection-toolbar'));
      final initial = tester.getTopLeft(toolbar).dy;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      final pinned = tester.getTopLeft(toolbar).dy;
      expect(pinned, lessThan(initial));
      expect(pinned, closeTo(tester.getBottomLeft(find.byType(AppBar)).dy, 1));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(toolbar).dy, closeTo(pinned, 1));
      expect(find.byTooltip('批量操作').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('批量操作'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('完成').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
