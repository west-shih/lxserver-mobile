import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/discovery/discovery_controller.dart';

final session = Session(
  Uri.parse('https://example.test'),
  'fixture',
  'fixture-token',
);
http.Response response(Object data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200);

void main() {
  test('Aggregate playlists use native defaults, interleave platforms, and page only unfinished platforms', () async {
    final calls = <String>[];
    final d =
        DiscoveryController(
            LxApi(
              client: MockClient((request) async {
                final source = request.url.queryParameters['source']!;
                if (request.url.path.endsWith('/tags')) {
                  calls.add('tags:$source');
                  return response({
                    'sortList': [
                      {'id': '$source-default'},
                    ],
                  });
                }
                final page = int.parse(request.url.queryParameters['page']!);
                calls.add('$source:$page');
                expect(
                  request.url.queryParameters['sortId'],
                  '$source-default',
                );
                return response({
                  'list': source == 'tx' && page == 2
                      ? [
                          {'id': '2'},
                        ]
                      : [
                          {'id': '1'},
                          {'id': '1'},
                          {'id': '2'},
                        ],
                  'total': source == 'tx' ? 4 : 2,
                  'limit': 2,
                });
              }),
            ),
            () {},
          )
          ..aggregate = true
          ..sources = [MusicSource.tx, MusicSource.wy];
    await d.load(session);
    expect(d.playlists.map((v) => '${v.source.name}:${v.id}'), [
      'tx:1',
      'wy:1',
      'tx:2',
      'wy:2',
    ]);
    expect(d.hasMore, true);
    await d.load(session, more: true);
    expect(calls.where((v) => v == 'wy:2'), isEmpty);
    expect(d.hasMore, false); // A repeated page cannot loop forever.
    await d.load(session);
    expect(calls.where((v) => v.startsWith('tags:')).length, 2);
    d.dispose();
  });

  test('Aggregate search skips category requests and partial failures retain successful results', () async {
    var failed = true;
    final pages = <String>[];
    final d =
        DiscoveryController(
            LxApi(
              client: MockClient((request) async {
                expect(request.url.path, '/api/music/songList/search');
                expect(request.url.queryParameters['text'], 'fixture');
                final source = request.url.queryParameters['source']!;
                pages.add('$source:${request.url.queryParameters['page']}');
                if (source == 'wy' && failed) return http.Response('{}', 500);
                return response({
                  'list': [
                    {'id': 'same'},
                  ],
                  'total': 1,
                  'limit': 20,
                });
              }),
            ),
            () {},
          )
          ..aggregate = true
          ..sources = [MusicSource.tx, MusicSource.wy]
          ..keyword = 'fixture';
    await d.load(session);
    expect(d.playlists.single.source, MusicSource.tx);
    expect(d.error, contains('网易'));
    failed = false;
    await d.load(session, more: true);
    expect(pages, ['tx:1', 'wy:1', 'wy:1']);
    expect(d.playlists.map((v) => v.source), [MusicSource.tx, MusicSource.wy]);
    expect(d.error, isNull);
    expect(d.hasMore, false);
    d.dispose();
  });

  test('Switching to one platform discards delayed aggregate responses and restores native categories', () async {
    final old = Completer<http.Response>();
    final d =
        DiscoveryController(
            LxApi(
              client: MockClient((request) async {
                if (request.url.path.endsWith('/tags')) {
                  return response({
                    'tags': [],
                    'sortList': [
                      {'id': 'native'},
                    ],
                  });
                }
                if (request.url.queryParameters['source'] == 'tx') {
                  return old.future;
                }
                return response({
                  'list': [
                    {'id': 'new'},
                  ],
                  'total': 1,
                  'limit': 20,
                });
              }),
            ),
            () {},
          )
          ..aggregate = true
          ..sources = [MusicSource.tx]
          ..keyword = 'fixture';
    final loading = d.load(session);
    await Future<void>.delayed(Duration.zero);
    await d.changeSource(session, MusicSource.wy);
    expect(d.aggregate, false);
    expect(d.sort, 'native');
    old.complete(
      response({
        'list': [
          {'id': 'old'},
        ],
      }),
    );
    await loading;
    expect(d.playlists.single.id, 'new');
    expect(d.playlists.single.source, MusicSource.wy);
    expect(d.loading, false);
    d.dispose();
  });
}
