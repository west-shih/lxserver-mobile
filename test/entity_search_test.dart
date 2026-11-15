import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/library/library_controller.dart';
import 'package:lxserver_mobile/features/search/entity_detail_controller.dart';
import 'package:lxserver_mobile/features/search/entity_detail_screen.dart';
import 'package:lxserver_mobile/features/search/entity_search_controller.dart';
import 'package:lxserver_mobile/features/search/entity_search_screen.dart';
import 'package:lxserver_mobile/features/search/music_entity.dart';
import 'package:lxserver_mobile/features/search/source_availability.dart';
import 'package:lxserver_mobile/features/search/album_card.dart';
import 'package:lxserver_mobile/shared/song_art.dart';

final session = Session(
  Uri.parse('https://example.test'),
  'fixture',
  'fixture-token',
);
http.Response response(Object data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200);
MusicEntity entity({bool artist = true}) =>
    MusicEntity({'id': 'mid', 'name': '测试歌手'}, MusicSource.tx, artist);

void main() {
  testWidgets(
    'album card has a small corner favorite, no playback, and metadata anchored at the bottom',
    (tester) async {
      var saved = <Map<String, dynamic>>[];
      var albumRequests = 0;
      final c = AppController(
        api: LxApi(
          client: MockClient((r) async {
            if (r.url.path == '/api/music/albumSongs') {
              albumRequests++;
              return response({'list': []});
            }
            expect(r.url.path, '/api/user/library/albums');
            if (r.method == 'POST') {
              saved = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
              return response({'success': true});
            }
            return response(saved);
          }),
        ),
      )..session = session;
      const e = MusicEntity(
        {'id': 'one', 'name': '专辑名称', 'artistName': '歌手'},
        MusicSource.tx,
        false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                height: 290,
                child: AlbumCard(controller: c, entity: e),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SongArt>(find.byType(SongArt)).borderRadius, 0);
      expect(find.byIcon(Icons.download_rounded), findsNothing);
      await tester.tap(find.byTooltip('收藏专辑：专辑名称'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('取消收藏专辑：专辑名称'), findsOneWidget);
      expect(albumRequests, 0);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.byType(EntityDetailScreen), findsNothing);
      expect(
        tester.getTopLeft(find.text('歌手')).dx,
        lessThan(tester.getTopLeft(find.text('QQ')).dx),
      );
      final cardBottom = tester.getBottomLeft(find.byType(AlbumCard)).dy;
      expect(
        cardBottom - tester.getBottomLeft(find.text('歌手')).dy,
        lessThan(18),
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('late artist statistics do not move the name or favorite', (
    tester,
  ) async {
    final info = Completer<http.Response>();
    final c = AppController(
      api: LxApi(
        client: MockClient((r) async {
          if (r.url.path.endsWith('artistDetail')) return info.future;
          if (r.url.path == '/api/user/list') {
            return response({
              'loveList': [],
              'defaultList': [],
              'userList': [],
            });
          }
          return response([]);
        }),
      ),
    )..session = session;
    await tester.pumpWidget(
      MaterialApp(
        home: EntityDetailScreen(controller: c, entity: entity()),
      ),
    );
    await tester.pump();
    final before = tester.getTopLeft(find.text('测试歌手'));
    final favorite = tester.getCenter(
      find.byKey(const ValueKey('entity-favorite')),
    );
    info.complete(
      response({'name': '测试歌手', 'albumSize': 43, 'musicSize': 1013}),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('测试歌手')), before);
    expect(
      tester.getCenter(find.byKey(const ValueKey('entity-favorite'))),
      favorite,
    );
    expect(
      tester.getTopLeft(find.text('43 专辑')).dx,
      lessThan(tester.getTopLeft(find.text('1013 歌曲')).dx),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'artist favorite stays in app bar; shared play toolbar stays below tabs and disappears for albums',
    (tester) async {
      final c = AppController(
        api: LxApi(
          client: MockClient((r) async {
            if (r.url.path.endsWith('artistDetail')) {
              return response({
                'name': '测试歌手',
                'musicSize': 60,
                'albumSize': 3,
              });
            }
            if (r.url.path.endsWith('artistSongs')) {
              return response(
                List.generate(
                  60,
                  (i) => {'name': '歌曲 $i', 'songmid': '$i', 'source': 'tx'},
                ),
              );
            }
            if (r.url.path.endsWith('artistAlbums')) {
              return response({'list': [], 'total': 0});
            }
            if (r.url.path == '/api/user/list') {
              return response({
                'loveList': [],
                'defaultList': [],
                'userList': [],
              });
            }
            return response([]);
          }),
        ),
      )..session = session;
      await tester.pumpWidget(
        MaterialApp(
          home: EntityDetailScreen(controller: c, entity: entity()),
        ),
      );
      await tester.pumpAndSettle();
      final favorite = find.byKey(const ValueKey('entity-favorite'));
      expect(
        find.ancestor(of: favorite, matching: find.byType(AppBar)),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, '收藏歌手'), findsNothing);
      expect(find.byKey(const ValueKey('entity-play')), findsOneWidget);
      expect(find.text('60 首'), findsOneWidget);
      expect(find.textContaining('· 已加载'), findsNothing);
      await tester.tap(find.byTooltip('选择歌曲'));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsNothing);
      expect(find.text('已选 0 首'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('已选 60 首'), findsOneWidget);
      await tester.tap(find.text('下载'));
      await tester.pumpAndSettle();
      expect(find.text('下载 60 首歌曲'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(c.localMedia.jobs, isEmpty);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      final toolbar = find.byKey(const ValueKey('entity-playback-toolbar'));
      expect(
        tester.getTopLeft(toolbar).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('歌曲')).dy),
      );
      final before = tester.getTopLeft(toolbar).dy;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(toolbar).dy, closeTo(before, 1));
      await tester.tap(find.text('专辑'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('entity-play')), findsNothing);
      expect(find.text('热门'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test('known total jumps directly to native page and keeps earlier cached results', () async {
    final pages = <int>[];
    final d = EntitySearchController(
      LxApi(
        client: MockClient((r) async {
          final page = int.parse(r.url.queryParameters['page']!);
          pages.add(page);
          return response({
            'list': List.generate(20, (i) => {'id': '$page-$i'}),
            'total': page == 1 ? 2000 : 0,
            'pageSize': 20,
          });
        }),
      ),
      () {},
    );
    await d.select(session, SearchKind.album, MusicSource.wy, '专辑');
    await d.ensurePage(session, 49, 20);
    expect(pages, [1, 50]);
    expect(d.pageItems(49, 20).first.id, '50-0');
    expect(d.pageItems(0, 20).first.id, '1-0');
    expect(d.total, 2000);
    d.dispose();
  });

  testWidgets(
    'search cards at narrow width and large fonts fit; paging uses native windows',
    (tester) async {
      tester.view.physicalSize = const Size(360, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(
        api: LxApi(
          client: MockClient((r) async {
            final page = int.parse(r.url.queryParameters['page']!);
            return response({
              'list': List.generate(
                20,
                (i) => {
                  'id': '$page-$i',
                  'name': '测试专辑 $page-$i',
                  'artistName': '歌手',
                },
              ),
              'total': 60,
            });
          }),
        ),
      )..session = session;
      c.pagedCollections = true;
      await c.entitySearch.select(
        session,
        SearchKind.album,
        MusicSource.tx,
        '测试',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(body: EntitySearchScreen(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试专辑 1-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('测试专辑 2-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'album download requires confirmation and singer link has no chevron',
    (tester) async {
      final c = AppController(
        api: LxApi(
          client: MockClient((r) async {
            if (r.url.path.endsWith('albumSongs')) {
              return response({
                'name': '测试专辑',
                'artistName': '测试歌手',
                'artistId': 'singer-mid',
                'list': [
                  {'name': '测试歌曲', 'songmid': 'one', 'source': 'tx'},
                ],
              });
            }
            if (r.url.path == '/api/user/list') {
              return response({
                'loveList': [],
                'defaultList': [],
                'userList': [],
              });
            }
            return response([]);
          }),
        ),
      )..session = session;
      await tester.pumpWidget(
        MaterialApp(
          home: EntityDetailScreen(
            controller: c,
            entity: entity(artist: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试歌手'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('entity-favorite')),
          matching: find.byType(AppBar),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('选择歌曲'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载'));
      await tester.pumpAndSettle();
      expect(find.text('下载 1 首歌曲'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(c.localMedia.jobs, isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test(
    'entity capability intersection and empty account cannot issue search',
    () async {
      var calls = 0;
      final c = AppController(
        api: LxApi(
          client: MockClient((r) async {
            calls++;
            return response({});
          }),
        ),
      )..session = session;
      c.availability = SourceAvailability.parse([
        {
          'enabled': true,
          'status': 'success',
          'supportedSources': ['kg', 'tx'],
          'disabledSources': [],
        },
      ]);
      expect(c.entitySources, [MusicSource.tx]);
      c.availability = SourceAvailability.parse([]);
      await c.selectSearchKind(SearchKind.artist, '测试');
      expect(c.entitySources, isEmpty);
      expect(c.entitySearch.kind, SearchKind.artist);
      expect(calls, 0);
      c.dispose();
    },
  );

  test('type switch drops old request; later missing total retained; repeated page stops', () async {
    final delayed = Completer<http.Response>();
    final d = EntitySearchController(
      LxApi(
        client: MockClient((r) async {
          final q = r.url.queryParameters;
          if (q['type'] == 'singer') return delayed.future;
          expect(q['source'], 'tx');
          expect(q['limit'], '20');
          return response({
            'list': [
              {'id': q['page'] == '1' ? 'a' : 'b', 'name': '专辑'},
            ],
            'total': q['page'] == '1' ? 3 : 0,
          });
        }),
      ),
      () {},
    );
    final old = d.select(session, SearchKind.artist, MusicSource.wy, '旧查询');
    await d.select(session, SearchKind.album, MusicSource.tx, '新查询');
    delayed.complete(
      response({
        'list': [
          {'id': 'old'},
        ],
        'total': 1,
      }),
    );
    await old;
    expect(d.items.single.id, 'a');
    await d.search(session, '新查询', more: true);
    expect(d.total, 3);
    expect(d.items.map((e) => e.id), ['a', 'b']);
    await d.search(session, '新查询', more: true);
    expect(d.hasMore, false);
    d.dispose();
  });

  test('favorites send raw array, re-read latest, preserve unknown fields and confirm result', () async {
    var stored = <Map<String, dynamic>>[
      {
        'id': 'other',
        'source': 'wy',
        'extra': {'keep': true},
      },
    ];
    var writes = 0;
    final l = LibraryController(
      LxApi(
        client: MockClient((r) async {
          expect(r.url.path, '/api/user/library/albums');
          if (r.method == 'POST') {
            expect(jsonDecode(r.body), isA<List>());
            stored = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
            writes++;
            return response({'success': true});
          }
          return response(stored);
        }),
      ),
      () {},
    );
    const e = MusicEntity(
      {'id': 'mid', 'name': '专辑', 'publishTime': '2020-01-02'},
      MusicSource.tx,
      false,
    );
    await l.setEntityFavorite(session, e.favorite, false, true);
    expect(stored.first['extra'], {'keep': true});
    expect(stored.last['meta'], containsPair('albumId', 'mid'));
    expect(stored.last['publishTime'], '2020-01-02');
    expect(l.albums.last['publishTime'], '2020-01-02');
    expect(l.isEntityFavorite(e.favorite, false), true);
    await l.setEntityFavorite(session, e.favorite, false, true);
    expect(writes, 1);
    await l.setEntityFavorite(session, e.favorite, false, false);
    expect(stored.single['id'], 'other');
    expect(l.albums.single['id'], 'other');
    l.dispose();
  });

  test(
    'readback failure does not report saved favorite or retry POST',
    () async {
      var reads = 0, writes = 0;
      final l = LibraryController(
        LxApi(
          client: MockClient((r) async {
            if (r.method == 'POST') {
              writes++;
              return response({'success': true});
            }
            if (++reads == 1) return response([]);
            return http.Response('failed', 500);
          }),
        ),
        () {},
      );
      await expectLater(
        l.setEntityFavorite(session, entity().favorite, true, true),
        throwsA(isA<ApiFailure>()),
      );
      expect(writes, 1);
      expect(l.mutating, false);
      expect(l.artists, isEmpty);
      l.dispose();
    },
  );

  test('favorite mutation invalidated before POST on logout; lock prevents double writes', () async {
    final pending = Completer<http.Response>();
    var writes = 0;
    final l = LibraryController(
      LxApi(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            writes++;
            return response({'success': true});
          }
          return pending.future;
        }),
      ),
      () {},
    );
    final operation = l.setEntityFavorite(
      session,
      entity().favorite,
      true,
      true,
    );
    await expectLater(
      l.setEntityFavorite(session, entity().favorite, true, true),
      throwsA(isA<ApiFailure>()),
    );
    l.reset();
    pending.complete(response([]));
    await operation;
    expect(writes, 0);
    expect(l.artists, isEmpty);
    l.dispose();
  });

  test('detail isolates information failure, native sort requests, album page dedup and stale sort', () async {
    final old = Completer<http.Response>();
    final d = EntityDetailController(
      LxApi(
        client: MockClient((r) async {
          if (r.url.path.endsWith('artistDetail')) {
            return http.Response('failed', 500);
          }
          if (r.url.path.endsWith('artistAlbums')) {
            return response({
              'list': [
                {'id': 'a', 'img': 'https://example.test/a', 'singer': '歌手'},
              ],
              'total': 3,
            });
          }
          if (r.url.queryParameters['order'] == 'hot') return old.future;
          return response([
            {'songmid': 'latest', 'name': '最新歌曲', 'source': 'tx'},
          ]);
        }),
      ),
      session,
      entity(),
      () {},
    );
    final first = d.load();
    await d.load(sort: 'time');
    old.complete(
      response([
        {'songmid': 'old'},
      ]),
    );
    await first;
    expect(d.songs.single.raw['songmid'], 'latest');
    expect(d.infoError, isNotNull);
    expect(d.error, isNull);
    await d.loadAlbums();
    expect(d.albums.single.image, 'https://example.test/a');
    await d.loadAlbums(more: true);
    expect(d.moreAlbums, false);
    expect(d.albums.length, 1);
    d.dispose();
  });

  test(
    'album metadata uses real fields, preserves identity and missing dates',
    () async {
      final d = EntityDetailController(
        LxApi(
          client: MockClient(
            (r) async => response({
              'list': [],
              'id': 'different',
              'name': '真实专辑',
              'artistName': '真实歌手',
              'artistId': 'singer-mid',
              'publishTime': '2020-01-02',
              'desc': '<p>专辑简介</p>',
              'img': 'https://example.test/album',
            }),
          ),
        ),
        session,
        entity(artist: false),
        () {},
      );
      await d.load();
      expect(d.entity.id, 'mid');
      expect(d.entity.artistId, 'singer-mid');
      expect(d.entity.description, '专辑简介');
      expect(d.entity.date, '2020-01-02');
      expect(entity().date, isEmpty);
      d.dispose();
    },
  );

  testWidgets(
    'detail narrow and large text: inline badge, no alias or redundant menu, gray description',
    (tester) async {
      tester.view.physicalSize = const Size(360, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(
        api: LxApi(
          client: MockClient((r) async {
            if (r.url.path.endsWith('artistDetail')) {
              return response({
                'name': '测试歌手',
                'alias': ['Hidden Alias'],
                'musicSize': 1019,
                'albumSize': 76,
                'desc': '示例简介',
              });
            }
            if (r.url.path.endsWith('artistSongs')) return response([]);
            if (r.url.path == '/api/user/list') {
              return response({
                'loveList': [],
                'defaultList': [],
                'userList': [],
              });
            }
            return response([]);
          }),
        ),
      )..session = session;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: EntityDetailScreen(controller: c, entity: entity()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('歌手详情'), findsOneWidget);
      expect(find.text('1019 歌曲'), findsOneWidget);
      expect(find.text('Hidden Alias'), findsNothing);
      expect(find.byTooltip('更多'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
