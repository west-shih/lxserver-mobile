import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/app/controller.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/search/music_entity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('lx-browse-test');
  });
  tearDown(() => root.delete(recursive: true));
  final session = Session(
    Uri.parse('https://example.test'),
    'fixture',
    'fixture-token',
  );
  AppController controller(List<Uri> requests) => AppController(
    mediaDirectory: () async => root,
    api: LxApi(
      client: MockClient((r) async {
        requests.add(r.url);
        if (r.url.path.endsWith('/verify')) {
          return http.Response('{"valid":true}', 200);
        }
        if (r.url.path == '/api/custom-source/list') {
          return http.Response(
            '[{"enabled":true,"status":"success","supportedSources": ["wy","tx"]}]',
            200,
          );
        }
        if (r.url.path.endsWith('/artistDetail')) {
          return http.Response(
            jsonEncode({'avatar': 'https://example.test/portrait.jpg'}),
            200,
          );
        }
        return http.Response('{"list":[],"tags":[],"sortList":[]}', 200);
      }),
    ),
  );

  test('Restart restores scoped drafts, search type and filters without querying first pages', () async {
    final first = controller([]);
    await first.restore();
    first.session = session;
    await first.store.save(session);
    first.updateBrowseDrafts('unfinished artist', 'unfinished playlist');
    first.homeTab = 1;
    first.keyword = 'submitted song';
    first.entitySearch.kind = SearchKind.artist;
    first.entitySearch.keyword = 'submitted artist';
    first.discovery.keyword = 'submitted playlist';
    first.discovery.tag = 'fixture-tag';
    first.discovery.tagName = 'Fixture';
    await first.flushBrowseState();
    first.dispose();
    await first.playbackResume.flush();
    await first.localMedia.flush();

    final requests = <Uri>[];
    final second = controller(requests);
    await second.restore();
    while (second.resumingBrowse) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(second.songDraft, 'unfinished artist');
    expect(second.playlistDraft, 'unfinished playlist');
    expect(second.homeTab, 1);
    expect(second.entitySearch.kind, SearchKind.artist);
    expect(second.discovery.tag, 'fixture-tag');
    expect(
      requests.where(
        (r) =>
            r.path == '/api/music/search' ||
            r.path.endsWith('/songList/search'),
      ),
      isEmpty,
    );
    await second.logout();
    expect(await second.store.readBrowseState(), isEmpty);
    second.dispose();
    await second.playbackResume.flush();
    await second.localMedia.flush();
  });

  test('Other accounts cannot restore search terms and corrupt snapshots are ignored', () async {
    final c = controller([]);
    await c.store.save(session);
    await c.store.saveBrowseState({
      'server': session.server.toString(),
      'username': 'another-user',
      'songDraft': 'private term',
    });
    await c.restore();
    while (c.resumingBrowse) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(c.songDraft, isEmpty);
    await c.flushBrowseState();
    c.dispose();
    await c.playbackResume.flush();
    await c.localMedia.flush();
    FlutterSecureStorage.setMockInitialValues({'lx.browseState': '{broken'});
    final other = controller([]);
    expect(await other.store.readBrowseState(), isEmpty);
    other.dispose();
  });

  test(
    'Netease cards reuse list portraits without platform enrichment',
    () async {
      final requests = <Uri>[];
      final c = controller(requests)..session = session;
      const entity = MusicEntity(
        {'id': '42', 'picUrl': 'https://example.test/list.jpg'},
        MusicSource.wy,
        true,
      );
      final portraits = await Future.wait([
        c.artistPortrait(entity),
        c.artistPortrait(entity),
      ]);
      expect(portraits, everyElement(entity.image));
      expect(requests.length, 0);
      const qq = MusicEntity(
        {'id': '43', 'picUrl': 'https://example.test/list.jpg'},
        MusicSource.tx,
        true,
      );
      expect(await c.artistPortrait(qq), qq.image);
      expect(requests.length, 0);
      c.dispose();
    },
  );
}
