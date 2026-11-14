import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/player/comments_controller.dart';
import 'package:lxserver_mobile/features/player/playback_mode.dart';
import 'package:lxserver_mobile/features/player/player_screen.dart';
import 'package:lxserver_mobile/shared/song_actions.dart';

void main() {
  testWidgets('Unplayed song offers download quality but no playback quality', (
    tester,
  ) async {
    final c = AppController();
    final item = Song({
      'songmid': 'not-playing',
      'name': 'Fixture',
    }, MusicSource.kw);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSongActions(context, c, item),
              child: const Text('菜单'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('菜单'));
    await tester.pumpAndSettle();
    expect(find.text('播放音质'), findsNothing);
    await tester.tap(find.text('下载到手机'));
    await tester.pumpAndSettle();
    expect(find.text('下载音质'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(find.textContaining('按首选'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('download-quality-128k')),
    );
    await tester.tap(find.byKey(const ValueKey('download-quality-128k')));
    await tester.pumpAndSettle();
    expect(find.text('下载音质'), findsOneWidget);
    expect(c.localMedia.jobs, isEmpty);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('download-quality-128k')),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(c.player.preferredQuality, 'flac');
    expect(c.player.current, null);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('信息'));
    await tester.pumpAndSettle();
    expect(find.text('本机'), findsOneWidget);
    expect(find.text('LXServer'), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  final session = Session(
    Uri.parse('https://fixture.test'),
    'fixture',
    'fixture-token',
  );
  final song = Song({
    'songmid': 'fixture-song',
    'name': 'Fixture',
    'singer': 'Artist',
    'types': [
      {'type': 'flac'},
    ],
  }, MusicSource.kw);
  test('Queue modes stop, wrap, repeat only on completion, and random excludes current', () {
    expect(nextQueueIndex(PlaybackMode.order, 2, 3, completed: true), null);
    expect(nextQueueIndex(PlaybackMode.list, 2, 3, completed: true), 0);
    expect(nextQueueIndex(PlaybackMode.single, 1, 3, completed: true), 1);
    expect(nextQueueIndex(PlaybackMode.single, 1, 3), 2);
    expect(nextQueueIndex(PlaybackMode.random, 0, 1), 0);
    expect(nextQueueIndex(PlaybackMode.random, -1, 0), null);
    final random = Random(14);
    for (var i = 0; i < 100; i++) {
      expect(
        nextQueueIndex(PlaybackMode.random, 1, 4, random: random),
        isNot(1),
      );
    }
  });
  test(
    'Comments contract and late hot response cannot overwrite latest tab',
    () async {
      final hot = Completer<http.Response>();
      final api = LxApi(
        client: MockClient((request) async {
          expect(request.url.path, '/api/music/comment');
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map;
          expect(body['songInfo']['source'], 'kw');
          expect(body['limit'], 20);
          return body['type'] == 'hot'
              ? hot.future
              : http.Response(
                  jsonEncode({
                    'comments': [
                      {'text': 'Latest'},
                    ],
                    'total': 21,
                    'maxPage': 2,
                  }),
                  200,
                );
        }),
      );
      final c = CommentsController(api, session, song, () {});
      final old = c.load();
      await c.load(category: 'new');
      hot.complete(
        http.Response(
          jsonEncode({
            'comments': [
              {'text': 'Old hot'},
            ],
          }),
          200,
        ),
      );
      await old;
      expect(c.items.single['text'], 'Latest');
      expect(c.maxPage, 2);
      await c.load(targetPage: 2);
      expect(c.page, 2);
      c.dispose();
    },
  );
  test('Comments authentication failures expire session and malformed data is retryable', () async {
    var expired = false;
    final c = CommentsController(
      LxApi(client: MockClient((_) async => http.Response('{}', 401))),
      session,
      song,
      () => expired = true,
    );
    await c.load();
    expect(expired, true);
    expect(c.error, isNotNull);
    expect(c.loading, false);
    c.dispose();
    final bad = CommentsController(
      LxApi(client: MockClient((_) async => http.Response('{}', 200))),
      session,
      song,
      () {},
    );
    await bad.load();
    expect(bad.error, isNotNull);
    bad.dispose();
  });
  testWidgets(
    'Player keeps metadata and tools together and opens read-only comments',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(
        api: LxApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'comments': [
                  {
                    'userName': 'Fixture listener',
                    'text': 'Fixture comment',
                    'likedCount': 12,
                    'reply': [
                      {'userName': 'Reply', 'text': 'Fixture reply'},
                    ],
                  },
                ],
                'total': 1,
                'maxPage': 1,
              }),
              200,
            ),
          ),
        ),
      )..session = session;
      c.player.enqueue(session, song);
      c.player.index = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(player: c.player, controller: c),
        ),
      );
      expect(find.text('酷我'), findsOneWidget);
      expect(find.byKey(const ValueKey('quality-selector')), findsNothing);
      expect(find.byTooltip('歌曲更多操作'), findsOneWidget);
      await tester.tap(find.byTooltip('歌曲评论'));
      await tester.pumpAndSettle();
      expect(find.text('Fixture comment'), findsOneWidget);
      expect(find.textContaining('Fixture reply'), findsOneWidget);
      await tester.tap(find.text('最新评论'));
      await tester.pumpAndSettle();
      expect(find.text('Fixture comment'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭评论'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('顺序播放'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('列表循环'));
      await tester.pumpAndSettle();
      expect(c.player.mode, PlaybackMode.list);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
