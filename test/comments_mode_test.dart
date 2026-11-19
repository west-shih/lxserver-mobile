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
import 'package:lxserver_mobile/features/player/comments_sheet.dart';
import 'package:lxserver_mobile/features/player/player_controls.dart';
import 'package:lxserver_mobile/shared/result_pagination.dart';
import 'package:lxserver_mobile/features/player/playback_mode.dart';
import 'package:lxserver_mobile/features/player/player_screen.dart';
import 'package:lxserver_mobile/shared/song_actions.dart';

void main() {
  testWidgets('Queue adapts to content within shared sheet limits', (
    tester,
  ) async {
    final app = AppController();
    final queueSession = Session(
      Uri.parse('https://fixture.test'),
      'fixture',
      'fixture',
    );
    final tracks = List.generate(
      30,
      (i) => Song({'songmid': 'queue-$i', 'name': 'Track $i'}, MusicSource.kw),
    );
    app.player.enqueue(queueSession, tracks.first);
    app.player.index = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showQueue(context, app.player),
            child: const Text('Open queue'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open queue'));
    await tester.pumpAndSettle();
    double height() => tester.getSize(find.byType(BottomSheet)).height;
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final shortHeight = height();
    expect(shortHeight, closeTo(200 + 18, 1));
    app.player.enqueueAll(queueSession, tracks.skip(1).take(3));
    await tester.pumpAndSettle();
    final middleHeight = height();
    expect(middleHeight, greaterThan(shortHeight));
    app.player.enqueueAll(queueSession, tracks.skip(4));
    await tester.pumpAndSettle();
    expect(height(), greaterThan(middleHeight));
    expect(height(), closeTo(screenHeight * .78 + 18, 1));
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .maxScrollExtent,
      greaterThan(0),
    );
    final selectedTile = find.byWidgetPredicate(
      (widget) => widget is ListTile && widget.selected,
    );
    final inkSurface = tester
        .element(selectedTile)
        .findAncestorWidgetOfExactType<Material>()!;
    expect(inkSurface.clipBehavior, Clip.hardEdge);
    expect(
      tester.getRect(find.byWidget(inkSurface)),
      tester.getRect(find.byType(ListView)),
    );
    final header = tester.getRect(find.text('接下来播放'));
    await tester.drag(find.byType(ListView), const Offset(0, -110));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('接下来播放')), header);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

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
  test(
    'QQ comments distinguish numeric IDs from MIDs without changing songs',
    () async {
      final payloads = <Map>[];
      final api = LxApi(
        client: MockClient((request) async {
          payloads.add((jsonDecode(request.body) as Map)['songInfo'] as Map);
          return http.Response('{"comments":[]}', 200);
        }),
      );
      final mid = Song({
        'songmid': 'fixture-mid',
        'songId': 'fixture-mid',
      }, MusicSource.tx);
      await api.comments(session, mid);
      expect(payloads.last.containsKey('songId'), false);
      expect(payloads.last['songmid'], 'fixture-mid');
      expect(mid.raw['songId'], 'fixture-mid');
      await api.comments(session, Song({'songmid': '12345'}, MusicSource.tx));
      expect(payloads.last['songId'], '12345');
      await api.comments(
        session,
        Song({
          'songmid': 'fixture-mid',
          'meta': {'songId': '67890'},
        }, MusicSource.tx),
      );
      expect(payloads.last['songId'], '67890');
      await api.comments(session, song);
      expect(payloads.last, song.raw);
    },
  );
  test(
    'Comments retain safe HTTP diagnostics instead of hiding the failure',
    () async {
      final c = CommentsController(
        LxApi(
          client: MockClient(
            (_) async =>
                http.Response('{"error":"private server detail"}', 500),
          ),
        ),
        session,
        song,
        () {},
      );
      await c.load();
      expect(c.error, contains('HTTP 500'));
      expect(c.error, isNot(contains('private server detail')));
      c.dispose();
    },
  );
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
      final newer = c.load(category: 'new');
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
      await newer;
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
      final close = tester.getCenter(find.byTooltip('关闭评论'));
      final order = tester.getCenter(find.text('最热评论'));
      final count = tester.getCenter(find.text('1 条'));
      final songLabel = tester.getCenter(
        find.text('${song.name} · ${song.sourceLabel}'),
      );
      expect(order.dy, greaterThan(close.dy));
      expect(order.dy, closeTo(songLabel.dy, 1));
      expect(songLabel.dx, lessThan(count.dx));
      expect(count.dx, lessThan(order.dx));
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final sheetHeight = tester.getSize(find.byType(BottomSheet)).height;
      expect(sheetHeight, greaterThanOrEqualTo(200 + 18));
      expect(sheetHeight, lessThan(screenHeight * .60));
      await tester.tap(find.text('最热评论'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最新评论').last);
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

  testWidgets('Comments share browsing mode and page size', (tester) async {
    final requests = <Map<String, dynamic>>[];
    final app =
        AppController(
            api: LxApi(
              client: MockClient((request) async {
                final body = jsonDecode(request.body) as Map<String, dynamic>;
                requests.add(body);
                return http.Response(
                  jsonEncode({
                    'comments': [
                      {'text': "Fixture page ${body['page']}"},
                    ],
                    'total': 25,
                    'maxPage': 3,
                  }),
                  200,
                );
              }),
            ),
          )
          ..session = session
          ..collectionPageSize = 10;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showComments(context, app, song),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultPagination), findsNothing);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture page 1'), findsOneWidget);
    expect(find.text('Fixture page 2'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭评论'));
    await tester.pumpAndSettle();

    app.pagedCollections = true;
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultPagination), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(ResultPagination)).dy,
      closeTo(tester.getBottomLeft(find.byType(BottomSheet)).dy, 1),
    );
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture page 1'), findsNothing);
    expect(find.text('Fixture page 2'), findsOneWidget);
    await tester.tap(find.text('跳页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('输入页码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('page-jump-input')), '3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳转至第 3 页'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture page 3'), findsOneWidget);
    expect(requests.map((body) => body['limit']), everyElement(10));
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
