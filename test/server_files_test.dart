import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/library/server_files_controller.dart';
import 'package:lxserver_mobile/features/player/quality.dart';
import 'package:lxserver_mobile/shared/music_badge.dart';
import 'package:lxserver_mobile/shared/song_tile.dart';

http.Response files(List<Object> rows) =>
    http.Response(jsonEncode({'success': true, 'data': rows}), 200);

void main() {
  test('Server file identities fall back past empty IDs and preserve platform separation', () {
    expect(
      ServerFilesController.songKey({
        'songmid': '',
        'songId': '42',
        'source': 'tx',
      }),
      'tx_42',
    );
    expect(
      ServerFilesController.songKey({'songmid': 'tx_42', 'source': 'tx'}),
      'tx_42',
    );
    expect(
      ServerFilesController.songKey({'id': '42', 'source': 'unknown'}),
      '42',
    );
  });
  final session = Session(
    Uri.parse('https://fixture.test'),
    'fixture',
    'token',
  );
  final song = Song({
    'songmid': '42',
    'name': 'Fixture',
    'singer': 'Artist',
  }, MusicSource.tx);
  test('One shared request maps server files by platform and prefers downloaded copies', () async {
    var calls = 0;
    final api = LxApi(
      client: MockClient((r) async {
        calls++;
        expect(r.url.path, '/api/music/cache/list');
        expect(r.headers['x-user-token'], 'token');
        return files([
          {'id': 'tx_42', 'quality': 'flac', 'folder': 'cache'},
          {'id': 'tx_42', 'quality': 'flac', 'folder': 'music'},
          {'id': 'tx_42', 'quality': 'flac', 'folder': 'cache'},
          {'id': 'wy_42', 'quality': 'flac', 'folder': 'cache'},
        ]);
      }),
    );
    final state = ServerFilesController(api, () {});
    addTearDown(state.dispose);
    addTearDown(api.close);
    await Future.wait([state.ensure(session), state.ensure(session)]);
    expect(calls, 1);
    expect(state.folders(song), {'flac': 'music'});
    expect(state.badge(song), '已下载');
    expect(state.badge(Song({'songmid': '42'}, MusicSource.wy)), '已缓存');
    expect(state.badge(Song({'songmid': '42'}, MusicSource.kw)), null);
  });
  test('Status refresh is bounded by TTL and isolates accounts', () async {
    var now = DateTime.utc(2026, 11, 14);
    var calls = 0;
    final api = LxApi(
      client: MockClient((r) async {
        calls++;
        return files(
          r.headers['x-user-name'] == 'fixture'
              ? [
                  {'id': 'tx_42', 'quality': 'flac', 'folder': 'cache'},
                ]
              : [],
        );
      }),
    );
    final state = ServerFilesController(api, () {}, now: () => now);
    addTearDown(state.dispose);
    addTearDown(api.close);
    await state.ensure(session);
    await state.ensure(session);
    expect(calls, 1);
    now = now.add(const Duration(seconds: 61));
    await state.ensure(session);
    expect(calls, 2);
    await state.ensure(Session(session.server, 'other', 'token-b'));
    expect(calls, 3);
    expect(state.badge(song), null);
  });
  test(
    'Unavailable status never displays stale or invented local cache badges',
    () async {
      var fail = false;
      final api = LxApi(
        client: MockClient(
          (_) async => fail
              ? http.Response('Forbidden', 403)
              : files([
                  {'id': 'tx_42', 'quality': 'flac', 'folder': 'cache'},
                ]),
        ),
      );
      final state = ServerFilesController(api, () {});
      addTearDown(state.dispose);
      addTearDown(api.close);
      await state.ensure(session);
      expect(state.badge(song), '已缓存');
      fail = true;
      await state.ensure(session, force: true);
      expect(state.available, false);
      expect(state.badge(song), null);
    },
  );
  test('Logout invalidates an in-flight file list', () async {
    final response = Completer<http.Response>();
    final api = LxApi(client: MockClient((_) => response.future));
    final state = ServerFilesController(api, () {});
    addTearDown(state.dispose);
    addTearDown(api.close);
    final pending = state.ensure(session);
    state.reset();
    response.complete(
      files([
        {'id': 'tx_42', 'quality': 'flac', 'folder': 'cache'},
      ]),
    );
    await pending;
    expect(state.available, false);
    expect(state.badge(song), null);
  });
  test('Quality groups distinguish concrete, unknown and explicitly absent options', () {
    final fresh = Song(
      {
        'types': [
          {'type': '128k'},
          {'type': '320k'},
        ],
      },
      MusicSource.tx,
      freshQualityMetadata: true,
    );
    expect(QualityPolicy.knownOptions(fresh).map((q) => q.id), [
      '128k',
      '320k',
    ]);
    expect(QualityPolicy.unverifiedOptions(fresh), isEmpty);
    final unknown = Song({}, MusicSource.tx);
    expect(QualityPolicy.knownOptions(unknown), isEmpty);
    expect(
      QualityPolicy.unverifiedOptions(unknown).map((q) => q.id),
      contains('master'),
    );
    final partial = Song(
      {
        'types': [
          {'type': '128k'},
          {'type': 'flac', 'isPlatformQuality': true},
        ],
      },
      MusicSource.tx,
      freshQualityMetadata: true,
    );
    expect(
      QualityPolicy.unverifiedOptions(partial).map((q) => q.id),
      contains('flac'),
    );
    expect(
      QualityPolicy.knownOptions(unknown, verified: ['flac']).map((q) => q.id),
      ['flac'],
    );
    expect(
      QualityPolicy.unverifiedOptions(Song({}, MusicSource.mg))
          .map((q) => q.id),
      isNot(contains('master')),
    );
  });
  testWidgets(
    'Server file quality uses LX colors without pretending the phone has cached audio',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(
        api: LxApi(
          client: MockClient(
            (_) async => files([
              {'id': 'tx_42', 'quality': 'master', 'folder': 'cache'},
            ]),
          ),
        ),
      )..session = session;
      addTearDown(c.dispose);
      await c.refreshServerFiles();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SongTile(song: song, controller: c, queue: [song]),
          ),
        ),
      );
      expect(find.text('QQ').hitTestable(), findsOneWidget);
      expect(find.text('Master').hitTestable(), findsOneWidget);
      expect(find.text('已缓存'), findsNothing);
      expect(
        tester
            .widget<MusicBadge>(
              find.ancestor(
                of: find.text('QQ'),
                matching: find.byType(MusicBadge),
              ),
            )
            .tone,
        BadgeTone.green,
      );
      expect(
        tester
            .widget<MusicBadge>(
              find.ancestor(
                of: find.text('Master'),
                matching: find.byType(MusicBadge),
              ),
            )
            .tone,
        BadgeTone.purple,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message?.contains('服务器已缓存') ?? false),
        ),
        findsNothing,
      );
      expect(tester.takeException(), null);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SongTile(song: song, controller: c, queue: [song]),
            ),
          ),
        ),
      );
      expect(tester.takeException(), null);
    },
  );
}
