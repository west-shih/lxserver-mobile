import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';

void main() {
  final server = Uri.parse('https://example.test/lx');
  final session = Session(server, 'test-user', 'test-token');
  test('Rejects unsafe addresses; preserves reverse proxy prefix', () {
    for (final value in [
      'example.test',
      'file:///local',
      'https://u:p@example.test',
      'https://example.test?token=x',
    ]) {
      expect(() => parseServer(value), throwsA(isA<ApiFailure>()));
    }
    expect(parseServer(' https://example.test/lx/ ').path, '/lx');
  });
  test('Login sends password in JSON only and requires a real token', () async {
    final api = LxApi(
      client: MockClient((request) async {
        expect(request.url.path, '/lx/api/user/login');
        expect(request.url.query, isEmpty);
        expect(request.method, 'POST');
        expect(request.headers.containsKey('x-user-token'), false);
        expect(jsonDecode(request.body), {
          'username': 'test-user',
          'password': 'test-password',
        });
        return http.Response(
          jsonEncode({
            'success': true,
            'token': 'test-token',
            'username': 'test-user',
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);
    expect(
      (await api.login(server, 'test-user', 'test-password')).token,
      'test-token',
    );
  });
  test(
    'All five sources use explicit pagination and preserve raw song fields',
    () async {
      final api = LxApi(
        client: MockClient((request) async {
          expect(request.headers['x-user-token'], session.token);
          expect(request.headers['x-user-name'], session.username);
          expect(request.url.queryParameters['limit'], '20');
          expect(request.url.queryParameters['page'], '2');
          return http.Response(
            jsonEncode({
              'list': [
                {
                  'name': 'Test',
                  'songmid': '42',
                  'types': [
                    {'type': '128k'},
                  ],
                  'custom': {'hash': 'raw'},
                },
              ],
              'hasMore': true,
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      for (final source in MusicSource.values) {
        final result = await api.search(session, 'keyword', source, 2);
        expect(result.songs.single.source, source);
        expect(result.songs.single.id, '${source.name}:42');
        expect(result.songs.single.raw['custom'], {'hash': 'raw'});
        expect(result.hasMore, true);
      }
    },
  );
  test('Playback sends original songInfo and resolves relative URLs', () async {
    final song = Song({
      'name': 'Test',
      'songmid': '42',
      'hash': 'original',
    }, MusicSource.kg);
    final api = LxApi(
      client: MockClient((request) async {
        expect(jsonDecode(request.body)['songInfo'], song.raw);
        expect(jsonDecode(request.body)['quality'], '320k');
        return http.Response('{"url":"/audio/test.mp3"}', 200);
      }),
    );
    addTearDown(api.close);
    expect(
      (await api.resolvePlayback(
        session,
        song,
        quality: '320k',
      )).url.toString(),
      'https://example.test/audio/test.mp3',
    );
  });
  test(
    'Auth failures are distinguished and arbitrary response content is hidden',
    () async {
      final unauthorized = LxApi(
        client: MockClient(
          (_) async => http.Response('secret server details', 401),
        ),
      );
      addTearDown(unauthorized.close);
      await expectLater(
        unauthorized.search(session, 'test', MusicSource.kw, 1),
        throwsA(
          isA<ApiFailure>().having((e) => e.unauthorized, 'expired', true),
        ),
      );
      final broken = LxApi(
        client: MockClient(
          (_) async => http.Response('<html>password=secret</html>', 502),
        ),
      );
      addTearDown(broken.close);
      await expectLater(
        broken.verify(session),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'safe error',
            isNot(contains('secret')),
          ),
        ),
      );
    },
  );
  test('Switching platforms ignores old in-flight results', () async {
    final first = Completer<http.Response>();
    final api = LxApi(
      client: MockClient((request) async {
        if (request.url.queryParameters['source'] == 'kw') return first.future;
        return http.Response(
          '{"list":[{"name":"new","songmid":"2"}],"hasMore":false}',
          200,
        );
      }),
    );
    final c = AppController(api: api)..session = session;
    addTearDown(c.dispose);
    final old = c.search('test');
    await c.changeSource(MusicSource.wy);
    first.complete(
      http.Response('{"list":[{"name":"old","songmid":"1"}]}', 200),
    );
    await old;
    expect(c.source, MusicSource.wy);
    expect(c.songs.single.name, 'new');
  });
  test('Queue can be started after adding a song before first playback', () {
    final c = AppController();
    addTearDown(c.dispose);
    final song = Song({'songmid': '1'}, MusicSource.kw);
    c.player.enqueue(session, song);
    c.player.enqueue(session, song);
    expect(c.player.queue.length, 1);
    expect(c.player.current, null);
  });
}
