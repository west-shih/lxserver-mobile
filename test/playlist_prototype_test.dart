import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/discovery/discovery_controller.dart';
import 'package:lxserver_mobile/features/library/library_controller.dart';
import 'package:lxserver_mobile/features/library/library_song.dart';
import 'package:lxserver_mobile/features/library/collection_metadata.dart';
import 'package:lxserver_mobile/features/library/collection_header.dart';
import 'package:lxserver_mobile/features/library/collection_screen.dart';
import 'package:lxserver_mobile/shared/song_tile.dart';
import 'package:lxserver_mobile/shared/scrolling_title.dart';

final session = Session(
  Uri.parse('https://example.test'),
  'fixture',
  'fixture-token',
);
Song song(int id) => Song({
  'songmid': '$id',
  'name': 'Song $id',
  'source': 'tx',
}, MusicSource.tx);
http.Response response(Object data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200);

void main() {
  test('Metadata combines list date with detail creator and description; missing fields stay empty', () async {
    final api = LxApi(
      client: MockClient(
        (request) async => response({
          'list': [],
          'info': {
            'author': 'Detail creator',
            'desc': 'A short introduction',
            'img': 'https://example.test/cover.png',
            'play_count': '12.8万',
          },
        }),
      ),
    );
    final d = DiscoveryController(api, () {});
    final result = await d.detail(
      session,
      PlaylistSummary({
        'id': 'remote',
        'time': '2024-01-13',
        'author': 'List creator',
      }, MusicSource.tx),
      1,
    );
    expect(result.metadata.author, 'Detail creator');
    expect(result.metadata.date, '2024-01-13');
    expect(result.metadata.description, 'A short introduction');
    expect(result.metadata.playCount, '12.8万');
    expect(CollectionMetadata.fromJson({}).author, isEmpty);
    d.dispose();
  });

  test('Collection writes a complete deduplicated LX snapshot and duplicate collection makes no second POST', () async {
    var saved = <String, dynamic>{
      'loveList': [],
      'defaultList': [],
      'userList': [],
      'extra': 7,
    };
    var writes = 0;
    final api = LxApi(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          saved = jsonDecode(request.body) as Map<String, dynamic>;
          writes++;
          return response({'success': true});
        }
        return response(request.url.path == '/api/user/list' ? saved : []);
      }),
    );
    final library = LibraryController(api, () {});
    final pages = <int>[];
    Future<SongBatch> fetch(Session _, PlaylistSummary _, int page) async {
      pages.add(page);
      return page == 1
          ? SongBatch([song(1)], true, image: 'https://example.test/cover.png')
          : SongBatch([song(1), song(2)], false);
    }

    final summary = PlaylistSummary({
      'id': 'remote',
      'name': 'Fixture',
    }, MusicSource.tx);
    expect(await library.collectRemote(session, summary, fetch), true);
    expect(pages, [1, 2]);
    expect(writes, 1);
    expect(saved['extra'], 7);
    final added = (saved['userList'] as List).single as Map;
    expect(added['sourceListId'], 'remote');
    expect(added['source'], 'tx');
    expect(added['id'], matches(RegExp(r'^tx_[0-9a-f]{32}$')));
    expect(added['Album'], 'https://example.test/cover.png');
    final songs = added['list'] as List;
    expect(songs.length, 2);
    expect(songs.first['id'], 'tx_1');
    expect(songs.first['meta']['songId'], '1');
    expect(await library.collectRemote(session, summary, fetch), false);
    expect(writes, 1);
    expect(library.mutating, false);
    library.dispose();
  });

  test('Collection remains locked until the post-save read finishes', () async {
    var saved = <String, dynamic>{
      'loveList': [],
      'defaultList': [],
      'userList': [],
    };
    var posted = false;
    final waiting = Completer<void>();
    final reply = Completer<http.Response>();
    final library = LibraryController(
      LxApi(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            saved = jsonDecode(request.body) as Map<String, dynamic>;
            posted = true;
            return response({'success': true});
          }
          if (request.url.path == '/api/user/list') {
            if (posted) {
              waiting.complete();
              return reply.future;
            }
            return response(saved);
          }
          return response([]);
        }),
      ),
      () {},
    );
    final summary = PlaylistSummary({'id': 'remote'}, MusicSource.tx);
    Future<SongBatch> fetch(Session _, PlaylistSummary _, int _) async =>
        SongBatch([song(1)], false);
    final first = library.collectRemote(session, summary, fetch);
    await waiting.future;
    expect(library.mutating, true);
    await expectLater(
      library.collectRemote(session, summary, fetch),
      throwsA(isA<ApiFailure>()),
    );
    reply.complete(response(saved));
    expect(await first, true);
    expect(library.mutating, false);
    library.dispose();
  });

  test(
    'Failure on a later page or session reset never writes partial collections',
    () async {
      var writes = 0;
      final library = LibraryController(
        LxApi(
          client: MockClient((request) async {
            if (request.method == 'POST') writes++;
            return response({});
          }),
        ),
        () {},
      );
      final summary = PlaylistSummary({'id': 'remote'}, MusicSource.tx);
      await expectLater(
        library.collectRemote(session, summary, (_, _, page) async {
          if (page == 2) throw const ApiFailure('fixture failure');
          return SongBatch([song(1)], true);
        }),
        throwsA(isA<ApiFailure>()),
      );
      expect(writes, 0);
      expect(library.mutating, false);
      expect(
        await library.collectRemote(session, summary, (_, _, _) async {
          library.reset();
          return SongBatch([song(1)], false);
        }),
        false,
      );
      expect(writes, 0);
      library.dispose();
    },
  );

  test(
    'Saved song identities preserve QQ playback ids and Kugou hash semantics',
    () {
      final tx = librarySong(
        Song({
          'songmid': 'media-mid',
          'songId': 42,
          'strMediaMid': 'file-mid',
          'source': 'tx',
        }, MusicSource.tx),
      );
      expect(tx['id'], 'tx_media-mid');
      expect(tx['meta']['songId'], '42');
      expect(tx['meta']['strMediaMid'], 'file-mid');
      final kg = librarySong(
        Song({'songmid': '123_HASH', 'source': 'kg'}, MusicSource.kg),
      );
      expect(kg['id'], '123_HASH');
      expect(kg['meta']['songId'], '123');
      expect(kg['meta']['hash'], 'HASH');
    },
  );

  testWidgets(
    'External metadata is visible and description expands; scroll transfers title into navigation',
    (tester) async {
      final c = AppController();
      final songs = List.generate(80, song);
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: c,
            collection: MusicCollection(
              'remote',
              'Fixture title',
              songs,
              source: MusicSource.tx,
              metadata: const CollectionMetadata(
                author: 'Fixture creator',
                description: 'A long description of the playlist',
                playCount: '12.8万',
                date: '2024-01-13',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('创建者：Fixture creator'), findsOneWidget);
      expect(find.text('12.8万 次播放'), findsOneWidget);
      expect(find.text('2024-01-13'), findsOneWidget);
      expect(find.byType(ScrollingTitle), findsNothing);
      await tester.tap(find.text('A long description of the playlist'));
      await tester.pumpAndSettle();
      expect(find.text('A long description of the playlist'), findsNWidgets(2));
      Navigator.pop(
        tester.element(find.text('A long description of the playlist').last),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollingTitle), findsOneWidget);
      expect(find.byType(CollectionHeader).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Public hero and actions fit narrow screens with large text and absent metadata leaves no placeholders',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: CollectionScreen(
              controller: c,
              collection: const MusicCollection(
                'remote',
                'A long title with metadata for a narrow screen',
                [],
                source: MusicSource.wy,
                metadata: CollectionMetadata(
                  author: 'A long creator name',
                  description:
                      'An introduction that can be expanded and read in full',
                  playCount: '12.8万',
                  date: '2024-01-13',
                ),
              ),
              fetchPage: (_) async => SongBatch([song(1)], false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: c,
            collection: MusicCollection('custom', 'Fixture', [song(1)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('创建者：'), findsNothing);
      expect(find.text('暂无介绍'), findsNothing);
      expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Batch selection survives pagination, queues selected songs only and download cancellation adds no jobs',
    (tester) async {
      final c =
          AppController(
              api: LxApi(client: MockClient((_) async => response([]))),
            )
            ..session = session
            ..pagedCollections = true;
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: c,
            collection: MusicCollection(
              'custom',
              'Fixture',
              List.generate(45, song),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('批量操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SongTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SongTile).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SongTile).first);
      await tester.pumpAndSettle();
      expect(find.text('已选 3 首'), findsOneWidget);
      await tester.tap(find.text('下载'));
      await tester.pumpAndSettle();
      expect(find.text('下载 3 首歌曲'), findsOneWidget);
      expect(c.localMedia.jobs, isEmpty);
      await tester.tap(find.text('高品质'));
      await tester.pumpAndSettle();
      expect(c.localMedia.jobs, isEmpty);
      Navigator.pop(tester.element(find.text('下载 3 首歌曲')));
      await tester.pumpAndSettle();
      expect(c.localMedia.jobs, isEmpty);
      expect(find.text('已选 3 首'), findsOneWidget);
      await tester.tap(find.text('下一首播放'));
      await tester.pumpAndSettle();
      expect(c.player.queue.map((s) => s.id), ['tx:0', 'tx:1', 'tx:20']);
      expect(c.player.current?.id, c.player.queue.first.id);
      expect(c.player.playing, isFalse);
      expect(find.text('完成'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('完成'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Public favorite requires confirmation then changes to collected state',
    (tester) async {
      var saved = <String, dynamic>{
        'loveList': [],
        'defaultList': [],
        'userList': [],
      };
      var writes = 0;
      final c = AppController(
        api: LxApi(
          client: MockClient((request) async {
            if (request.method == 'POST') {
              writes++;
              saved = jsonDecode(request.body) as Map<String, dynamic>;
              return response({'success': true});
            }
            return response(request.url.path == '/api/user/list' ? saved : []);
          }),
        ),
      )..session = session;
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: c,
            collection: const MusicCollection(
              'remote',
              'Fixture',
              [],
              source: MusicSource.tx,
            ),
            fetchPage: (_) async => SongBatch([song(1)], false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('收藏歌单'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.tap(find.text('收藏').last);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.byTooltip('取消收藏歌单'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test('Original lookup retains the same-source list date and does not invent an uncached date', () {
    final d = DiscoveryController(LxApi(), () {});
    d.playlists = [
      PlaylistSummary({'id': 'remote', 'time': '2020-01-01'}, MusicSource.tx),
      PlaylistSummary({'id': 'remote', 'time': '2024-01-13'}, MusicSource.wy),
    ];
    const saved = MusicCollection(
      'local',
      'Renamed',
      [],
      source: MusicSource.wy,
      sourceListId: 'remote',
    );
    expect(d.originalSummary(saved).metadata.date, '2024-01-13');
    d.playlists = [];
    final fallback = d.originalSummary(saved);
    expect(fallback.id, 'remote');
    expect(fallback.name, 'Renamed');
    expect(fallback.metadata.date, isEmpty);
    expect(
      () => d.originalSummary(const MusicCollection('custom', 'Local', [])),
      throwsA(isA<ApiFailure>()),
    );
    d.dispose();
  });

  testWidgets(
    'Opening saved origin keeps cached creation date when the detail response omits it',
    (tester) async {
      final c = AppController(
        api: LxApi(
          client: MockClient((request) async {
            if (request.url.path == '/api/music/songList/detail') {
              return response({
                'list': [song(1).raw],
                'total': 1,
                'limit': 1,
                'info': {'author': 'Creator', 'desc': 'Introduction'},
              });
            }
            return response([]);
          }),
        ),
      )..session = session;
      c.discovery.playlists = [
        PlaylistSummary({
          'id': 'remote',
          'name': 'Original',
          'time': '2024-01-13',
        }, MusicSource.wy),
      ];
      const saved = MusicCollection(
        'local',
        'Renamed',
        [],
        source: MusicSource.wy,
        sourceListId: 'remote',
      );
      c.library.collections = [saved];
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: c,
            collection: saved,
            editable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2024-01-13'), findsNothing);
      await tester.tap(find.byTooltip('歌单操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开原始歌单'));
      await tester.pumpAndSettle();
      expect(find.text('2024-01-13'), findsOneWidget);
      expect(find.text('创建者：Creator'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
