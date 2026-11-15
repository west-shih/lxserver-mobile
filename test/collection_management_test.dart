import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/library/library_controller.dart';
import 'package:lxserver_mobile/features/library/collection_screen.dart';
import 'package:lxserver_mobile/features/discovery/discovery_controller.dart';
import 'package:lxserver_mobile/shared/song_tile.dart';
import 'package:lxserver_mobile/shared/song_art.dart';
import 'package:lxserver_mobile/features/library/collection_header.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lxserver_mobile/features/settings/personal_center_screen.dart';

void main() {
  test('Deletion preserves latest unrelated lists and metadata, protects system lists', () async {
    final session = Session(
      Uri.parse('https://example.test'),
      'fixture',
      'fixture-token',
    );
    var writes = 0;
    final data = {
      'loveList': [],
      'defaultList': [],
      'userList': [
        {'id': 'custom', 'name': 'A', 'list': []},
        {'id': 'other', 'name': 'B', 'list': [], 'extra': 7},
      ],
      'extra': true,
    };
    final api = LxApi(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          writes++;
          final body = jsonDecode(request.body) as Map;
          expect(body['extra'], true);
          expect((body['userList'] as List).single['extra'], 7);
          return http.Response('{"success":true}', 200);
        }
        return http.Response(
          jsonEncode(request.url.path == '/api/user/list' ? data : []),
          200,
        );
      }),
    );
    final library = LibraryController(api, () {});
    await library.changeCollection(
      session,
      const MusicCollection('custom', 'A', []),
    );
    expect(writes, 1);
    expect(library.mutating, false);
    await expectLater(
      library.changeCollection(
        session,
        const MusicCollection('love', 'Love', []),
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(writes, 1);
    library.dispose();
  });

  test('Remote refresh collects every page, deduplicates and rejects repeated incomplete pages', () async {
    final library = LibraryController(LxApi(), () {});
    final session = Session(
      Uri.parse('https://example.test'),
      'fixture',
      'fixture-token',
    );
    final summary = PlaylistSummary({'id': 'remote'}, MusicSource.tx);
    Song song(int i) => Song({'songmid': '$i'}, MusicSource.tx);
    final pages = <int>[];
    final result = await library.remoteSongs(session, summary, (
      _,
      _,
      page,
    ) async {
      pages.add(page);
      return page == 1
          ? SongBatch(
              [song(1), song(2)],
              true,
              image: 'https://example.test/list.jpg',
            )
          : SongBatch([song(2), song(3)], false);
    });
    expect(pages, [1, 2]);
    expect(result.image, 'https://example.test/list.jpg');
    expect(result.songs.map((s) => s.id), ['tx:1', 'tx:2', 'tx:3']);
    await expectLater(
      library.remoteSongs(
        session,
        summary,
        (_, _, _) async => SongBatch([song(1)], true),
      ),
      throwsA(isA<ApiFailure>()),
    );
    library.dispose();
  });

  test('Linked replacement preserves source metadata and a rejected write leaves local state unchanged', () async {
    final session = Session(
      Uri.parse('https://example.test'),
      'fixture',
      'fixture-token',
    );
    var reject = false;
    final api = LxApi(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          final list =
              (jsonDecode(request.body)['userList'] as List).single as Map;
          expect(list['sourceListId'], 'remote');
          expect(list['customField'], 'keep');
          expect((list['list'] as List).single['songmid'], 'new');
          return reject
              ? http.Response('{}', 403)
              : http.Response('{"success":true}', 200);
        }
        return http.Response(
          jsonEncode(
            request.url.path == '/api/user/list'
                ? {
                    'loveList': [],
                    'defaultList': [],
                    'userList': [
                      {
                        'id': 'linked',
                        'name': 'Linked',
                        'source': 'tx',
                        'sourceListId': 'remote',
                        'customField': 'keep',
                        'list': [],
                      },
                    ],
                  }
                : [],
          ),
          200,
        );
      }),
    );
    final library = LibraryController(api, () {});
    const collection = MusicCollection(
      'linked',
      'Linked',
      [],
      source: MusicSource.tx,
      sourceListId: 'remote',
    );
    final replacement = [
      Song({'songmid': 'new'}, MusicSource.tx),
    ];
    await library.changeCollection(
      session,
      collection,
      replacement: replacement,
    );
    expect(library.collections.last.isLinked, true);
    reject = true;
    final previous = library.collections;
    await expectLater(
      library.changeCollection(session, collection, replacement: replacement),
      throwsA(isA<ApiFailure>()),
    );
    expect(identical(previous, library.collections), true);
    expect(library.mutating, false);
    library.dispose();
  });

  testWidgets(
    'Read-only reload rebuilds detail artwork and refresh persists remote cover without clearing missing metadata',
    (tester) async {
      var saved = <String, dynamic>{
        'loveList': [],
        'defaultList': [],
        'userList': [
          {
            'id': 'linked',
            'name': 'Fixture',
            'source': 'tx',
            'sourceListId': 'remote',
            'Album': '',
            'customField': 7,
            'list': [
              {'songmid': 'old', 'name': 'Old'},
            ],
          },
        ],
      };
      var writes = 0;
      final c =
          AppController(
              api: LxApi(
                client: MockClient((request) async {
                  if (request.method == 'POST') {
                    expect(request.url.path, '/api/user/list');
                    writes++;
                    saved = jsonDecode(request.body) as Map<String, dynamic>;
                    return http.Response('{"success":true}', 200);
                  }
                  if (request.url.path == '/api/user/list') {
                    return http.Response(jsonEncode(saved), 200);
                  }
                  if (request.url.path == '/api/music/songList/detail') {
                    expect(request.url.queryParameters['source'], 'tx');
                    expect(request.url.queryParameters['id'], 'remote');
                    return http.Response(
                      jsonEncode({
                        'list': [
                          {'songmid': 'new', 'name': 'New'},
                        ],
                        'total': 1,
                        'limit': 1,
                        'info': {
                          'img': ' ',
                          'pic': 'https://example.test/new-cover.jpg',
                        },
                      }),
                      200,
                    );
                  }
                  return http.Response('[]', 200);
                }),
              ),
            )
            ..session = Session(
              Uri.parse('https://example.test'),
              'fixture',
              'fixture-token',
            );
      await c.library.load(c.session!);
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: c,
            collection: c.library.collections.last,
            editable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final headerArt = find.descendant(
        of: find.byType(CollectionHeader),
        matching: find.byType(SongArt),
      );
      expect(tester.widget<SongArt>(headerArt).url, isEmpty);
      (saved['userList'] as List).single['Album'] =
          'https://example.test/saved-cover.jpg';
      await c.library.load(c.session!);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SongArt>(headerArt).url,
        'https://example.test/saved-cover.jpg',
      );
      expect(writes, 0);
      final collection = c.library.collections.last;
      final result = await c.library.remoteSongs(
        c.session!,
        PlaylistSummary({'id': 'remote'}, MusicSource.tx),
        c.discovery.detail,
      );
      expect(result.image, 'https://example.test/new-cover.jpg');
      await c.library.changeCollection(
        c.session!,
        collection,
        replacement: result.songs,
        image: result.image,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SongArt>(headerArt).url,
        'https://example.test/new-cover.jpg',
      );
      final updated = (saved['userList'] as List).single as Map;
      expect(updated['Album'], result.image);
      expect(updated['customField'], 7);
      expect(updated['sourceListId'], 'remote');
      expect((updated['list'] as List).single['songmid'], 'new');
      await c.library.changeCollection(
        c.session!,
        c.library.collections.last,
        replacement: result.songs,
        image: ' ',
      );
      expect(
        (saved['userList'] as List).single['Album'],
        'https://example.test/new-cover.jpg',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Prototype header separates metadata, play toolbar and on-demand search on narrow screens',
    (tester) async {
      final c = AppController()..pagedCollections = true;
      final songs = List.generate(
        25,
        (i) => Song({'songmid': '$i', 'name': 'Song $i'}, MusicSource.kw),
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [320.0, 360.0]) {
        for (final scale in [1.0, 1.6]) {
          tester.view.physicalSize = Size(width, 720);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: CollectionScreen(
                  controller: c,
                  collection: MusicCollection('custom', 'Fixture', songs),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Fixture'), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.text('25 首'), findsOneWidget);
          expect(
            tester.getRect(find.byType(CollectionHeader)).bottom,
            lessThanOrEqualTo(
              tester
                  .getRect(find.byKey(const ValueKey('collection-toolbar')))
                  .top,
            ),
          );
          expect(
            tester
                .getSize(find.byKey(const ValueKey('collection-pagination')))
                .height,
            32,
          );
          await tester.tap(find.byTooltip('搜索歌单内歌曲'));
          await tester.pumpAndSettle();
          expect(find.byType(CollectionHeader), findsNothing);
          expect(
            tester
                .widget<TextField>(find.byType(TextField))
                .decoration!
                .hintText,
            '搜索歌单内歌曲',
          );
          await tester.enterText(find.byType(TextField), 'Song 24');
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byType(SongTile),
              matching: find.text('Song 24'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('collection-pagination')),
            findsNothing,
          );
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(find.byType(CollectionHeader), findsOneWidget);
          expect(find.text('第 1 / 2 页'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
      c.dispose();
    },
  );

  testWidgets(
    'Search covers other pages and preserves song artwork and queue',
    (tester) async {
      final c = AppController()..pagedCollections = true;
      final songs = List.generate(
        65,
        (i) => Song({
          'songmid': '$i',
          'name': 'Song $i',
          'singer': i == 63 ? 'Target artist' : 'Artist',
        }, MusicSource.kw),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: c,
            collection: MusicCollection('custom', 'Only title', songs),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Only title'), findsOneWidget);
      expect(find.text('第 1 / 4 页'), findsOneWidget);
      await tester.tap(find.byTooltip('搜索歌单内歌曲'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'TARGET');
      await tester.pumpAndSettle();
      expect(find.text('Song 63'), findsOneWidget);
      expect(find.byKey(const ValueKey('collection-pagination')), findsNothing);
      final row = tester.widget<SongTile>(find.byType(SongTile));
      expect(
        find.descendant(
          of: find.byType(SongTile),
          matching: find.byType(SongArt),
        ),
        findsOneWidget,
      );
      expect(find.byType(SongArt), findsOneWidget);
      expect(row.queue.length, 65);
      await tester.tap(find.byTooltip('清除歌单搜索'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 / 4 页'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Detail renaming validates and updates title while preserving songs and source fields',
    (tester) async {
      var writes = 0;
      var data = <String, dynamic>{
        'loveList': [],
        'defaultList': [],
        'userList': [
          {
            'id': 'custom',
            'name': 'Before',
            'source': 'tx',
            'sourceListId': 'remote',
            'other': 7,
            'list': [
              {'songmid': '1', 'name': 'Track'},
            ],
          },
        ],
      };
      final c =
          AppController(
              api: LxApi(
                client: MockClient((request) async {
                  if (request.method == 'POST') {
                    writes++;
                    data = jsonDecode(request.body) as Map<String, dynamic>;
                    return http.Response('{"success":true}', 200);
                  }
                  return http.Response.bytes(
                    utf8.encode(
                      jsonEncode(
                        request.url.path == '/api/user/list' ? data : [],
                      ),
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
      await c.library.load(c.session!);
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: c,
            collection: c.library.collections.last,
            editable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('歌单操作'));
      await tester.pumpAndSettle();
      expect(find.text('刷新同步'), findsOneWidget);
      expect(find.text('删除歌单'), findsOneWidget);
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入歌单名称'), findsOneWidget);
      expect(writes, 0);
      await tester.enterText(find.byType(TextFormField), '  After  ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('After'), findsOneWidget);
      expect(find.text('Track'), findsOneWidget);
      final list = (data['userList'] as List).single as Map;
      expect(list['name'], 'After');
      expect(list['other'], 7);
      expect(list['sourceListId'], 'remote');
      expect((list['list'] as List).single['songmid'], '1');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Page size defaults to twenty and persists selected size in personal center',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final c = AppController()
        ..session = Session(
          Uri.parse('https://example.test'),
          'fixture',
          'fixture-token',
        );
      expect(c.collectionPageSize, 20);
      await tester.pumpWidget(
        MaterialApp(home: PersonalCenterScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButton<int>));
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('每页 30 项').last);
      await tester.pumpAndSettle();
      expect(c.collectionPageSize, 30);
      expect(await c.store.readCollectionPageSize(), '30');
      expect(c.pagedCollections, true);
      expect(await c.store.readListMode(), 'true');
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('每页歌曲数'), findsNothing);
      expect(find.textContaining('关闭后'), findsNothing);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('连续列表').last);
      await tester.pumpAndSettle();
      expect(c.pagedCollections, false);
      expect(c.collectionPageSize, 30);
      expect(await c.store.readListMode(), 'false');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Paging resets scroll, keeps full queue, and playback toolbar stays pinned',
    (tester) async {
      final c = AppController()..pagedCollections = true;
      final songs = List.generate(
        120,
        (i) => Song({'songmid': '$i', 'name': 'Track $i'}, MusicSource.kw),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionScreen(
            controller: c,
            collection: MusicCollection('custom', 'Fixture', songs),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第 1 / 6 页'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('collection-play')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 / 6 页'), findsOneWidget);
      expect(find.text('Track 20'), findsOneWidget);
      expect(find.text('Track 0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
