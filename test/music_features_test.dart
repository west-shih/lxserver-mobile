import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/player/lyrics.dart';
import 'package:lxserver_mobile/features/search/source_availability.dart';
import 'package:lxserver_mobile/shared/song_art.dart';

http.Response jsonResponse(Object value) =>
    http.Response.bytes(utf8.encode(jsonEncode(value)), 200);

void main() {
  test('NetEase artwork uses accepted headers only for its own CDN', () {
    expect(artworkHeaders('https://p1.music.126.net/fixture.jpg'), {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://music.163.com/',
    });
    expect(artworkHeaders('https://music.126.net.attacker.test/a'), isEmpty);
    expect(artworkHeaders('https://example.test/a'), isEmpty);
  });
  test('Saved covers accept upstream aliases and skip blank fields', () {
    expect(
      Song({
        'img': '',
        'meta': {'picUrl': 'https://example.test/a.jpg'},
      }, MusicSource.wy).image,
      'https://example.test/a.jpg',
    );
    expect(
      Song({
        'album': {'picUrl': 'https://example.test/b.jpg'},
      }, MusicSource.tx).image,
      'https://example.test/b.jpg',
    );
    expect(
      firstImage([{}, '', ' https://example.test/list.jpg ']),
      'https://example.test/list.jpg',
    );
  });
  final session = Session(
    Uri.parse('https://example.test'),
    'test-user',
    'test-token',
  );
  test(
    'Lyrics use authenticated GET with saved song identity and source fields',
    () async {
      final api = LxApi(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/music/lyric');
          expect(request.headers['x-user-token'], 'test-token');
          expect(request.headers['x-user-name'], 'test-user');
          expect(
            request.url.queryParameters,
            containsPair('songmid', '123456'),
          );
          expect(request.url.queryParameters, containsPair('source', 'tx'));
          expect(request.url.queryParameters, containsPair('name', '测试 & 歌曲'));
          expect(
            request.url.queryParameters,
            containsPair('lrcUrl', 'https://example.test/lrc?a=1&b=2'),
          );
          expect(request.body, isEmpty);
          return jsonResponse({
            'lyric': '[00:01.00]fixture',
            '_fromLocalCache': true,
          });
        }),
      );
      final result = await api.lyrics(
        session,
        Song({
          'id': 'tx_123456',
          'name': '测试 & 歌曲',
          'singer': '测试歌手',
          'meta': {'lrcUrl': 'https://example.test/lrc?a=1&b=2'},
        }, MusicSource.tx),
      );
      expect(Lyrics.parse(result).lines.single.text, 'fixture');
    },
  );
  test(
    'QQ lyric GET resolves MID instead of forwarding a string songId',
    () async {
      for (final source in [MusicSource.tx, MusicSource.wy]) {
        final api = LxApi(
          client: MockClient((request) async {
            expect(request.url.queryParameters['songmid'], 'fixtureSongMid');
            if (source == MusicSource.tx) {
              expect(
                request.url.queryParameters.containsKey('songId'),
                isFalse,
              );
            } else {
              expect(request.url.queryParameters['songId'], '123456');
            }
            return jsonResponse({'lyric': '[00:01.00]fixture'});
          }),
        );
        await api.lyrics(
          session,
          Song({'songmid': 'fixtureSongMid', 'songId': 123456}, source),
        );
      }
    },
  );
  test('Availability unions ready sources and subtracts per-source disabled platforms', () {
    final result = SourceAvailability.parse([
      {
        'enabled': true,
        'status': 'success',
        'supportedSources': ['kw', 'mg'],
        'disabledSources': ['mg'],
      },
      {
        'enabled': true,
        'status': 'success',
        'supportedSources': ['kw', 'wy'],
      },
      {
        'enabled': false,
        'status': 'success',
        'supportedSources': ['mg'],
      },
      {
        'enabled': true,
        'status': 'error',
        'supportedSources': ['mg'],
      },
    ]);
    expect(result.readyCount, 2);
    expect(result.platforms, [MusicSource.kw, MusicSource.wy]);
    expect(SourceAvailability.parse([]).platforms, isEmpty);
    expect(
      () => SourceAvailability.parse([
        {'enabled': true},
      ]),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('Unavailable capability API keeps platforms visible', () async {
    final c = AppController(
      api: LxApi(
        client: MockClient((_) async => http.Response('Not found', 404)),
      ),
    )..session = session;
    addTearDown(c.dispose);
    await c.refreshSources();
    expect(c.availability, null);
    expect(c.availableSources.length, 5);
    expect(c.sourceError, isNotNull);
  });
  test('Known zero platforms never sends a search request', () async {
    var requests = 0;
    final c =
        AppController(
            api: LxApi(
              client: MockClient((_) async {
                requests++;
                return jsonResponse({});
              }),
            ),
          )
          ..session = session
          ..availability = const SourceAvailability([], 0);
    addTearDown(c.dispose);
    await c.search('test');
    expect(requests, 0);
    expect(c.searchError, contains('没有可用平台'));
    expect(c.searching, false);
  });
  test('Aggregate search isolates failures, retries failed page and paginates each source', () async {
    final calls = <String>[];
    var kgFailed = false;
    final api = LxApi(
      client: MockClient((request) async {
        final source = request.url.queryParameters['source'];
        final page = request.url.queryParameters['page'];
        calls.add('$source:$page');
        if (source == 'kg' && !kgFailed) {
          kgFailed = true;
          return http.Response('failure', 500);
        }
        return jsonResponse({
          'list': [
            {'name': 'Same title', 'songmid': page},
          ],
          'hasMore': source == 'kw' && page == '1',
        });
      }),
    );
    final c = AppController(api: api)
      ..aggregate = true
      ..session = session
      ..availability = const SourceAvailability([
        MusicSource.kw,
        MusicSource.kg,
        MusicSource.wy,
      ], 1);
    addTearDown(c.dispose);
    await c.search('test');
    expect(c.songs.map((s) => s.id), ['wy:1', 'kw:1']);
    expect(c.sourceFailures.keys, contains(MusicSource.kg));
    expect(c.availableSources, contains(MusicSource.kg));
    await c.search('test', more: true);
    expect(c.songs.map((s) => s.id), ['wy:1', 'kg:1', 'kw:1', 'kw:2']);
    expect(calls.where((v) => v == 'kg:1').length, 2);
    expect(calls.where((v) => v.startsWith('wy:')).length, 1);
    expect(c.hasMore, false);
    expect(c.searchError, null);
  });
  test(
    'Nested synchronized songs retain metadata and share the online identity',
    () {
      final nested = Song({
        'id': 'tx_42',
        'name': 'test',
        'source': 'tx',
        'meta': {
          'songId': '42',
          'picUrl': 'https://example.test/cover.jpg',
          'albumName': 'Album',
          'strMediaMid': 'original-mid',
          'qualitys': [
            {'type': '128k'},
          ],
        },
      }, MusicSource.kw);
      expect(
        nested.id,
        Song({'songmid': '42', 'source': 'tx'}, MusicSource.tx).id,
      );
      expect(nested.image, 'https://example.test/cover.jpg');
      expect(nested.album, 'Album');
      expect(nested.raw['strMediaMid'], 'original-mid');
      expect(nested.raw['meta'], isNotNull);
      expect(Song({'source': 'local'}, MusicSource.kw).sourceLabel, '本地');
    },
  );
  test('Library preserves personal collections when optional artist endpoint fails', () async {
    final c = AppController(
      api: LxApi(
        client: MockClient((request) async {
          expect(request.headers['x-user-token'], 'test-token');
          if (request.url.path.endsWith('/artists')) {
            return http.Response('failed', 500);
          }
          if (request.url.path.endsWith('/albums')) {
            return jsonResponse([
              {'id': 'album', 'name': 'Album', 'source': 'wy'},
            ]);
          }
          return jsonResponse({
            'loveList': [
              {
                'id': 'kw_1',
                'source': 'kw',
                'meta': {'songId': '1'},
              },
            ],
            'defaultList': [],
            'userList': [
              {'id': 'custom', 'name': 'Saved list', 'list': []},
            ],
          });
        }),
      ),
    )..session = session;
    addTearDown(c.dispose);
    await c.library.load(session);
    expect(c.library.collections.map((v) => v.id), [
      'love',
      'default',
      'custom',
    ]);
    expect(c.library.collections.first.songs.single.id, 'kw:1');
    expect(c.library.artistError, isNotNull);
    expect(c.library.albums.single['name'], 'Album');
    expect(c.library.error, null);
  });
  test(
    'Discovery uses server-provided sort IDs and explicit detail pagination',
    () async {
      final api = LxApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/tags')) {
            return jsonResponse({
              'tags': [],
              'sortList': [
                {'id': 5, 'name': '推荐'},
              ],
            });
          }
          if (request.url.path.endsWith('/detail')) {
            expect(request.url.queryParameters['page'], '1');
            return jsonResponse({
              'list': [
                {'songmid': 'one'},
              ],
              'total': 1,
              'limit': 20,
            });
          }
          expect(request.url.queryParameters['sortId'], '5');
          return jsonResponse({
            'list': [
              {'id': 'one', 'name': 'List'},
            ],
            'total': 1,
            'limit': 20,
          });
        }),
      );
      final c = AppController(api: api)..session = session;
      addTearDown(c.dispose);
      await c.discovery.changeSource(session, MusicSource.kg);
      expect(c.discovery.sort, '5');
      expect(c.discovery.hasMore, false);
      final result = await c.discovery.detail(
        session,
        c.discovery.playlists.single,
        1,
      );
      expect(result.songs.single.source, MusicSource.kg);
      expect(result.hasMore, false);
    },
  );
  test('LRC parses repeated timestamps, fractions, translations and backward seeking', () {
    final lyrics = Lyrics.parse({
      'lyric': '[ti:Test]\n[00:01.2][00:03.450]Repeated\n[00:02.00]Middle',
      'tlyric': '[00:01.20]翻译',
    });
    expect(lyrics.lines.map((line) => line.time.inMilliseconds), [
      1200,
      2000,
      3450,
    ]);
    expect(lyrics.lines.first.translation, '翻译');
    expect(lyrics.indexAt(const Duration(milliseconds: 999)), -1);
    expect(lyrics.indexAt(const Duration(seconds: 4)), 2);
    expect(lyrics.indexAt(const Duration(milliseconds: 1500)), 0);
    expect(
      Lyrics.parse({'lyric': '[ti:Test]\nPlain lyric'}).plain,
      'Plain lyric',
    );
    expect(Lyrics.parse({}).lines, isEmpty);
  });
}
