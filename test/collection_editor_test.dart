import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/library/library_controller.dart';
import 'package:lxserver_mobile/features/library/collection_screen.dart';
import 'package:lxserver_mobile/features/library/collection_edit_actions.dart';
import 'package:lxserver_mobile/features/player/player_views.dart';
import 'package:lxserver_mobile/shared/song_art.dart';
import 'package:lxserver_mobile/shared/song_tile.dart';
import 'package:lxserver_mobile/shared/playlist_edit_glyph.dart';

Map<String, dynamic> raw(int i) => {
  'songmid': '$i',
  'name': 'Song $i',
  'source': 'tx',
};

class Fixture {
  Fixture({int count = 6}) {
    data = {
      'loveList': [],
      'defaultList': [],
      'userList': [
        {
          'id': 'custom',
          'name': 'Fixture',
          'extra': 7,
          'list': List.generate(count, raw),
        },
        {
          'id': 'target',
          'name': 'Target',
          'list': [raw(99)],
        },
      ],
    };
  }
  late Map<String, dynamic> data;
  int writes = 0;
  int status = 200;
  late final c =
      AppController(
          api: LxApi(
            client: MockClient((request) async {
              if (request.method == 'POST') {
                writes++;
                if (status != 200) return http.Response('{}', status);
                data = jsonDecode(request.body) as Map<String, dynamic>;
                return http.Response('{"success":true}', 200);
              }
              return http.Response(
                jsonEncode(request.url.path == '/api/user/list' ? data : []),
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
  Future<void> load() async => c.library.load(c.session!);
  Widget screen({bool route = false}) => MaterialApp(
    home: route
        ? Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => CollectionScreen(
                      controller: c,
                      collection: c.library.collections[2],
                      editable: true,
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          )
        : CollectionScreen(
            controller: c,
            collection: c.library.collections[2],
            editable: true,
          ),
  );
  List<String> get ids => ((data['userList'] as List).first['list'] as List)
      .map((v) => 'tx:${v['songmid']}')
      .toList();
}

Future<void> begin(WidgetTester tester) async {
  await tester.tap(find.byTooltip('批量操作'));
  await tester.pumpAndSettle();
}

Future<void> dragFirstDown(WidgetTester tester) async {
  final first = find.byType(SongTile).at(0);
  final third = find.byType(SongTile).at(2);
  final handle = find.descendant(
    of: first,
    matching: find.byType(ReorderableDragStartListener),
  );
  final start = tester.getCenter(handle);
  final end = Offset(start.dx, tester.getRect(third).bottom - 4);
  final gesture = await tester.startGesture(start);
  await tester.pump();
  await gesture.moveTo(Offset(start.dx, start.dy + 30));
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.moveTo(end);
  await tester.pump(const Duration(milliseconds: 400));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Editor matches leading round selection and trailing drag handles; order saves only on Done',
    (tester) async {
      final f = Fixture();
      await f.load();
      f.c.player.enqueueAll(f.c.session!, f.c.library.collections[2].songs);
      f.c.player.index = 0;
      await tester.pumpWidget(f.screen());
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistEditGlyph), findsOneWidget);
      await begin(tester);
      expect(find.byType(MiniPlayer), findsNothing);
      final tile = find.byType(SongTile).first;
      final check = find.descendant(of: tile, matching: find.byType(Checkbox));
      final art = find.descendant(of: tile, matching: find.byType(SongArt));
      expect(tester.widget<Checkbox>(check).shape, isA<CircleBorder>());
      expect(tester.getRect(check).right, lessThan(tester.getRect(art).left));
      expect(find.byType(ReorderableDragStartListener), findsWidgets);
      await dragFirstDown(tester);
      expect(f.writes, 0);
      expect(f.ids, ['tx:0', 'tx:1', 'tx:2', 'tx:3', 'tx:4', 'tx:5']);
      expect(
        tester.widget<SongTile>(find.byType(SongTile).first).song.id,
        'tx:1',
      );
      final draft = tester
          .widgetList<SongTile>(find.byType(SongTile))
          .map((tile) => tile.song.id)
          .toList();
      expect(draft.length, 6);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(f.writes, 1);
      expect(f.ids, draft);
      expect(f.c.player.queue.first.id, 'tx:0');
      expect(f.c.player.current!.id, 'tx:0');
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'Deleting is confirmed, cancel writes nothing, and song removal leaves the playing queue intact',
    (tester) async {
      final f = Fixture();
      await f.load();
      f.c.player.enqueueAll(f.c.session!, f.c.library.collections[2].songs);
      f.c.player.index = 0;
      await tester.pumpWidget(f.screen());
      await tester.pumpAndSettle();
      await begin(tester);
      await tester.tap(find.byType(SongTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('从歌单删除 1 首歌曲？'), findsOneWidget);
      expect(f.writes, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(f.writes, 0);
      expect(find.text('已选 1 首'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(f.writes, 1);
      expect(f.ids.contains('tx:0'), false);
      expect(f.c.player.current!.id, 'tx:0');
      expect(f.c.player.queue.length, 6);
      expect(find.text('完成'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'Back during unsaved drag offers discard and restores the original view without writes',
    (tester) async {
      final f = Fixture();
      await f.load();
      await tester.pumpWidget(f.screen(route: true));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await begin(tester);
      await dragFirstDown(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('保存歌曲排序？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(find.text('完成'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();
      expect(f.writes, 0);
      expect(
        tester.widget<SongTile>(find.byType(SongTile).first).song.id,
        'tx:0',
      );
      expect(find.byType(CollectionEditActions), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets('Reordering page two preserves the ordering of all other pages', (
    tester,
  ) async {
    final f = Fixture(count: 45);
    await f.load();
    f.c.pagedCollections = true;
    await tester.pumpWidget(f.screen());
    await tester.pumpAndSettle();
    await begin(tester);
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    tester
        .widget<SliverReorderableList>(find.byType(SliverReorderableList))
        .onReorderItem!(0, 2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(f.ids.take(20), List.generate(20, (i) => 'tx:$i'));
    expect(f.ids.skip(20).take(3), ['tx:21', 'tx:22', 'tx:20']);
    expect(f.ids.skip(23), List.generate(22, (i) => 'tx:${i + 23}'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
  testWidgets(
    'External originals disable destructive editing but selected songs can be collected into a private target',
    (tester) async {
      final f = Fixture();
      await f.load();
      final songs = [
        Song(raw(1), MusicSource.tx),
        Song(raw(2), MusicSource.tx),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: f.c,
            collection: MusicCollection(
              'remote',
              'Remote',
              songs,
              source: MusicSource.tx,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await begin(tester);
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      await tester.tap(find.byType(SongTile).first);
      await tester.pumpAndSettle();
      final delete = find
          .ancestor(of: find.text('删除'), matching: find.byType(InkWell))
          .first;
      expect(tester.widget<InkWell>(delete).onTap, isNull);
      await tester.tap(find.text('收藏到歌单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Target'));
      await tester.pumpAndSettle();
      expect(f.writes, 1);
      final target = (f.data['userList'] as List)[1]['list'] as List;
      expect(target.map((v) => v['songmid']), ['99', '1']);
      expect(
        tester.widget<SongTile>(find.byType(SongTile).first).queue.length,
        2,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'All four editor actions fit a 320px screen at large text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = Fixture();
      await f.load();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: CollectionScreen(
              controller: f.c,
              collection: f.c.library.collections[2],
              editable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await begin(tester);
      for (final label in ['下一首播放', '收藏到歌单', '下载', '删除']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'Delete after dragging saves remaining draft order in the same confirmed write',
    (tester) async {
      final f = Fixture();
      await f.load();
      await tester.pumpWidget(f.screen());
      await tester.pumpAndSettle();
      await begin(tester);
      await dragFirstDown(tester);
      final rows = tester.widgetList<SongTile>(find.byType(SongTile)).toList();
      final removed = rows[3].song.id;
      final expected = rows
          .map((r) => r.song.id)
          .where((id) => id != removed)
          .toList();
      await tester.tap(find.byType(SongTile).at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.textContaining('同时保存当前拖动后的顺序'), findsOneWidget);
      expect(f.writes, 0);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(f.writes, 1);
      expect(f.ids, expected);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets('Failed sorting stays editable and can be explicitly retried', (
    tester,
  ) async {
    final f = Fixture();
    await f.load();
    await tester.pumpWidget(f.screen());
    await tester.pumpAndSettle();
    await begin(tester);
    await dragFirstDown(tester);
    final expected = tester
        .widgetList<SongTile>(find.byType(SongTile))
        .map((r) => r.song.id)
        .toList();
    f.status = 403;
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(f.writes, 1);
    expect(find.text('完成'), findsOneWidget);
    expect(f.ids.first, 'tx:0');
    expect(
      tester.widget<SongTile>(find.byType(SongTile).first).song.id,
      expected.first,
    );
    f.status = 200;
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(f.ids, expected);
    expect(f.writes, 2);
    expect(find.text('完成'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
}
