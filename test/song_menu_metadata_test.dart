import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/discovery/discovery_controller.dart';
import 'package:lxserver_mobile/features/discovery/discovery_screen.dart';
import 'package:lxserver_mobile/features/player/playback_glyph.dart';
import 'package:lxserver_mobile/shared/song_actions.dart';

final session = Session(
  Uri.parse('https://example.test'),
  'fixture',
  'fixture-token',
);
http.Response response(Object data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200);
final track = Song({
  'songmid': 'one',
  'source': 'wy',
  'name': 'Fixture song',
}, MusicSource.wy);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Song menu comments read the selected song without starting playback',
    (tester) async {
      tester.view.padding = FakeViewPadding(
        bottom: 48 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPadding);
      Map? requested;
      final c = AppController(
        api: LxApi(
          client: MockClient((r) async {
            if (r.url.path == '/api/music/comment') {
              requested = jsonDecode(r.body) as Map;
              return response({'comments': [], 'total': 0});
            }
            return response([]);
          }),
        ),
      )..session = session;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSongActions(context, c, track),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('收藏到歌单'), findsOneWidget);
      final infoTile = find.ancestor(
        of: find.text('信息'),
        matching: find.byType(ListTile),
      );
      final commentTile = find.widgetWithText(ListTile, '评论');
      final glyph = tester.widget<PlaybackGlyph>(
        find.descendant(of: commentTile, matching: find.byType(PlaybackGlyph)),
      );
      expect(glyph.type, PlaybackGlyphType.comment);
      expect(
        tester.getBottomLeft(commentTile).dy,
        tester.getTopLeft(infoTile).dy,
      );
      expect(
        tester.getBottomLeft(find.byType(BottomSheet)).dy -
            tester.getBottomLeft(infoTile).dy,
        closeTo(48 + 4, 1),
      );
      await tester.tap(find.text('评论'));
      await tester.pumpAndSettle();
      expect(find.text('歌曲评论'), findsOneWidget);
      expect((requested!['songInfo'] as Map)['songmid'], 'one');
      expect(c.player.current, isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Collection picker excludes default, cancel writes nothing, repeat collection deduplicates',
    (tester) async {
      tester.view.padding = FakeViewPadding(
        bottom: 48 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPadding);
      var data = <String, dynamic>{
        'loveList': [],
        'defaultList': [
          {'songmid': 'preserved', 'source': 'wy'},
        ],
        'userList': [
          {'id': 'custom', 'name': 'Fixture list', 'list': [], 'extra': 42},
        ],
        'extra': true,
      };
      var writes = 0;
      final c = AppController(
        api: LxApi(
          client: MockClient((r) async {
            if (r.method == 'POST') {
              writes++;
              data = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
              return response({'success': true});
            }
            return response(r.url.path == '/api/user/list' ? data : []);
          }),
        ),
      )..session = session;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSongActions(context, c, track),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      Future<void> openPicker() async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('收藏到歌单'));
        await tester.pumpAndSettle();
      }

      await openPicker();
      expect(find.text('默认列表'), findsNothing);
      expect(find.text('我的喜欢'), findsOneWidget);
      final lastOption = find.ancestor(
        of: find.text('Fixture list'),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(lastOption).dense, isTrue);
      expect(
        tester.getBottomLeft(find.byType(BottomSheet)).dy -
            tester.getBottomLeft(lastOption).dy,
        closeTo(48, 1),
      );
      ScrollPosition pickerPosition() =>
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(pickerPosition().maxScrollExtent, 0);
      expect(
        pickerPosition().physics.shouldAcceptUserOffset(pickerPosition()),
        isFalse,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      for (var i = 0; i < 2; i++) {
        await openPicker();
        await tester.tap(find.text('Fixture list'));
        await tester.pumpAndSettle();
      }
      expect(((data['userList'] as List).single['list'] as List).length, 1);
      expect((data['defaultList'] as List).single['songmid'], 'preserved');
      expect((data['userList'] as List).single['extra'], 42);
      expect(data['extra'], true);
      expect(c.player.current, isNull);
      (data['userList'] as List).addAll([
        for (var i = 0; i < 20; i++)
          {'id': 'extra-$i', 'name': 'Extra $i', 'list': []},
      ]);
      await openPicker();
      expect(pickerPosition().maxScrollExtent, greaterThan(0));
      expect(
        pickerPosition().physics.shouldAcceptUserOffset(pickerPosition()),
        isTrue,
      );
      final create = find.text('新建歌单');
      final pinnedPosition = tester.getCenter(create);
      await tester.drag(find.byType(Scrollable), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getCenter(create), pinnedPosition);
      await tester.tap(create);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消').last);
      await tester.pumpAndSettle();
      expect(create, findsOneWidget);
      expect(writes, 1);
      await tester.tap(create);
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建并加入'));
      await tester.pumpAndSettle();
      expect(find.text('歌单名称不能为空'), findsOneWidget);
      expect(writes, 1);
      await tester.enterText(find.byType(TextField), 'New list');
      await tester.tap(find.text('创建并加入'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      final created = (data['userList'] as List).last as Map;
      expect(created['name'], 'New list');
      expect(created['source'], 'webplayer');
      expect(created['list'], hasLength(1));
      expect(writes, 2);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('Playlist date shares the metadata line at the right', (
    tester,
  ) async {
    final c = AppController(
      api: LxApi(client: MockClient((r) async => response([]))),
    )..session = session;
    c.discovery.playlists = [
      PlaylistSummary({
        'id': 'dated',
        'name': 'Dated',
        'author': 'Creator',
        'play_count': '10',
        'time': '2026-01-02',
      }, MusicSource.wy),
      PlaylistSummary({
        'id': 'undated',
        'name': 'Undated',
        'author': 'Another',
        'play_count': '20',
      }, MusicSource.wy),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiscoveryScreen(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Creator · 10 次播放'), findsOneWidget);
    expect(find.text('2026-01-02'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('2026-01-02')).dy,
      closeTo(tester.getTopLeft(find.text('Creator · 10 次播放')).dy, 1),
    );
    expect(find.text('Another · 20 次播放'), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
