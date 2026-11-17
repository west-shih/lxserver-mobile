import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/discovery/discovery_controller.dart';

void main() {
  final session = Session(
    Uri.parse('https://example.test'),
    'fixture',
    'fixture-token',
  );
  test(
    'Shared Kugou link retains query parameters and returned metadata',
    () async {
      const link = 'https://www.kugou.com/songlist/fixture/?uid=123&chain=abc';
      final api = LxApi(
        client: MockClient((request) async {
          expect(request.url.path, '/api/music/songList/detail');
          expect(request.url.queryParameters, {
            'source': 'kg',
            'id': link,
            'page': '1',
          });
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'list': [],
                'info': {'name': '测试歌单', 'author': '测试作者'},
              }),
            ),
            200,
          );
        }),
      );
      final controller = DiscoveryController(api, () {});
      final summary = await controller.openShared(
        session,
        MusicSource.kg,
        link,
      );
      expect(summary.id, link);
      expect(summary.name, '测试歌单');
      expect(summary.author, '测试作者');
      controller.dispose();
    },
  );
  test('Malformed success response does not open a playlist', () async {
    final api = LxApi(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    final controller = DiscoveryController(api, () {});
    await expectLater(
      controller.openShared(session, MusicSource.kg, '123456'),
      throwsA(isA<ApiFailure>()),
    );
    controller.dispose();
  });
}
