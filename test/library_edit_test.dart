import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/library/library_controller.dart';
import 'package:lxserver_mobile/features/player/player_controller.dart';

final session = Session(
  Uri.parse('https://example.test'),
  'fixture',
  'fixture-token',
);
Map<String, dynamic> row(int n, {String source = 'tx'}) => {
  'songmid': '$n',
  'source': source,
  'name': 'Song $n',
  'meta': {'fixture': 'keep-$n'},
};
Map<String, dynamic> snapshot() => {
  'loveList': [row(1), row(1, source: 'wy')],
  'defaultList': [row(2), row(3)],
  'userList': [
    {
      'id': 'custom',
      'name': 'Fixture',
      'Album': 'https://example.test/cover.jpg',
      'extra': 7,
      'list': [row(4), row(5), row(6)],
    },
    {
      'id': 'other',
      'name': 'Other',
      'list': [row(9)],
    },
  ],
  'rootExtra': true,
};
http.Response response(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status);

class Harness {
  Map<String, dynamic> data = snapshot();
  int writes = 0;
  int status = 200;
  bool rejectReadback = false;
  int expired = 0;
  late final LibraryController library = LibraryController(
    LxApi(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          writes++;
          if (status != 200) return response({}, status);
          data = jsonDecode(request.body) as Map<String, dynamic>;
          return response({'success': true});
        }
        if (request.url.path == '/api/user/list') {
          if (rejectReadback && writes > 0) return response({}, 500);
          return response(data);
        }
        return response([]);
      }),
    ),
    () => expired++,
  );
  List<String> ids(String id) {
    final raw = id == 'love'
        ? data['loveList']
        : id == 'default'
        ? data['defaultList']
        : (data['userList'] as List).firstWhere((v) => v['id'] == id)['list'];
    return (raw as List)
        .map(
          (v) => Song(Map<String, dynamic>.from(v as Map), MusicSource.kw).id,
        )
        .toList();
  }
}

void main() {
  test('Creates empty and populated private lists and retries by ID', () async {
    final h = Harness();
    addTearDown(h.library.dispose);
    final emptyId = h.library.newCollectionId();
    final populatedId = h.library.newCollectionId();
    final song = Song(row(1), MusicSource.tx);
    await h.library.createCollection(session, id: emptyId, name: ' Empty ');
    expect(h.ids(emptyId), isEmpty);
    await h.library.createCollection(
      session,
      id: populatedId,
      name: 'With songs',
      songs: [
        song,
        song,
        Song(row(1, source: 'wy'), MusicSource.wy),
      ],
    );
    expect(h.ids(populatedId), ['tx:1', 'wy:1']);
    expect(
      await h.library.createCollection(
        session,
        id: populatedId,
        name: 'Retry draft',
        songs: [song],
      ),
      'With songs',
    );
    expect(h.writes, 2);
    expect(h.ids(populatedId), ['tx:1', 'wy:1']);
    final lists = h.data['userList'] as List;
    expect(lists.take(2), snapshot()['userList']);
    expect(lists[2], {
      'id': emptyId,
      'name': 'Empty',
      'source': 'webplayer',
      'list': [],
    });
    expect(h.data['defaultList'], snapshot()['defaultList']);
    expect(h.data['loveList'], snapshot()['loveList']);
    expect(h.data['rootExtra'], true);
  });

  test('Deleting from system favorites respects platform identity and preserves unrelated songs and fields', () async {
    final h = Harness();
    await h.library.load(session);
    final result = await h.library.editSongs(
      session,
      h.library.collections.first,
      removeIds: {'tx:1'},
    );
    expect(result.map((s) => s.id), ['wy:1']);
    expect(h.ids('love'), ['wy:1']);
    expect(h.ids('default'), ['tx:2', 'tx:3']);
    expect(h.data['rootExtra'], true);
    expect((h.data['userList'] as List).first['extra'], 7);
    expect(h.writes, 1);
    h.library.dispose();
  });
  test('Sort saves latest raw metadata in requested order and preserves playlist metadata', () async {
    final h = Harness();
    await h.library.load(session);
    ((h.data['userList'] as List).first['list'] as List)[1]['meta']['fixture'] =
        'newer';
    await h.library.editSongs(
      session,
      h.library.collections[2],
      order: ['tx:6', 'tx:4', 'tx:5'],
      expectedOrder: ['tx:4', 'tx:5', 'tx:6'],
    );
    expect(h.ids('custom'), ['tx:6', 'tx:4', 'tx:5']);
    final custom = (h.data['userList'] as List).first as Map;
    expect(custom['Album'], 'https://example.test/cover.jpg');
    expect(custom['extra'], 7);
    expect(custom['list'][2]['meta']['fixture'], 'newer');
    expect(h.ids('other'), ['tx:9']);
    h.library.dispose();
  });
  test(
    'Concurrent insertion or reordering rejects stale sorting without a POST',
    () async {
      for (final changed in [
        [row(4), row(5), row(6), row(7)],
        [row(5), row(4), row(6)],
      ]) {
        final h = Harness();
        await h.library.load(session);
        (h.data['userList'] as List).first['list'] = changed;
        await expectLater(
          h.library.editSongs(
            session,
            h.library.collections[2],
            order: ['tx:6', 'tx:4', 'tx:5'],
            expectedOrder: ['tx:4', 'tx:5', 'tx:6'],
          ),
          throwsA(isA<ApiFailure>()),
        );
        expect(h.writes, 0);
        expect(h.library.mutating, false);
        h.library.dispose();
      }
    },
  );
  test('Delete preserves concurrently added songs when no stale order is submitted', () async {
    final h = Harness();
    await h.library.load(session);
    ((h.data['userList'] as List).first['list'] as List).add(row(7));
    await h.library.editSongs(
      session,
      h.library.collections[2],
      removeIds: {'tx:5'},
    );
    expect(h.ids('custom'), ['tx:4', 'tx:6', 'tx:7']);
    h.library.dispose();
  });
  test(
    'Combined deletion and staged ordering are applied in one snapshot',
    () async {
      final h = Harness();
      await h.library.load(session);
      await h.library.editSongs(
        session,
        h.library.collections[2],
        removeIds: {'tx:5'},
        order: ['tx:6', 'tx:4'],
        expectedOrder: ['tx:4', 'tx:5', 'tx:6'],
      );
      expect(h.ids('custom'), ['tx:6', 'tx:4']);
      expect(h.writes, 1);
      h.library.dispose();
    },
  );
  test('Copy deduplicates by platform song identity and uses native LX shape for new songs', () async {
    final h = Harness();
    await h.library.load(session);
    await h.library.editSongs(
      session,
      h.library.collections.first,
      addSongs: [
        Song(row(1), MusicSource.tx),
        Song(row(4), MusicSource.tx),
        Song(row(4), MusicSource.tx),
      ],
    );
    expect(h.ids('love'), ['tx:1', 'wy:1', 'tx:4']);
    final added = (h.data['loveList'] as List).last as Map;
    expect(added['id'], 'tx_4');
    expect(added['meta']['songId'], '4');
    expect((h.data['loveList'] as List).first['meta']['fixture'], 'keep-1');
    h.library.dispose();
  });
  test(
    'Default list can be sorted, but invalid permutations are never written',
    () async {
      final h = Harness();
      await h.library.load(session);
      await expectLater(
        h.library.editSongs(
          session,
          h.library.collections[1],
          order: ['tx:3'],
          expectedOrder: ['tx:2', 'tx:3'],
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(h.writes, 0);
      await h.library.editSongs(
        session,
        h.library.collections[1],
        order: ['tx:3', 'tx:2'],
        expectedOrder: ['tx:2', 'tx:3'],
      );
      expect(h.ids('default'), ['tx:3', 'tx:2']);
      h.library.dispose();
    },
  );
  test('No-op edits avoid POST and denied writes leave local collections unchanged', () async {
    final h = Harness();
    await h.library.load(session);
    await h.library.editSongs(
      session,
      h.library.collections.first,
      removeIds: {'tx:absent'},
      addSongs: [Song(row(1), MusicSource.tx)],
    );
    expect(h.writes, 0);
    final before = h.library.collections;
    h.status = 403;
    await expectLater(
      h.library.editSongs(
        session,
        h.library.collections.first,
        removeIds: {'tx:1'},
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(identical(h.library.collections, before), true);
    expect(h.ids('love'), ['tx:1', 'wy:1']);
    expect(h.library.mutating, false);
    h.library.dispose();
  });
  test(
    'An authentication failure expires the session, without retrying writes',
    () async {
      final h = Harness();
      await h.library.load(session);
      h.status = 401;
      await expectLater(
        h.library.editSongs(
          session,
          h.library.collections.first,
          removeIds: {'tx:1'},
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(h.expired, 1);
      expect(h.writes, 1);
      h.library.dispose();
    },
  );
  test('Confirmed write retains the applied state when readback fails and never reposts', () async {
    final h = Harness();
    await h.library.load(session);
    h.rejectReadback = true;
    final songs = await h.library.editSongs(
      session,
      h.library.collections.first,
      removeIds: {'tx:1'},
    );
    expect(songs.map((s) => s.id), ['wy:1']);
    expect(h.library.error, contains('修改已保存'));
    expect(h.writes, 1);
    expect(h.library.mutating, false);
    h.library.dispose();
  });
  test('Next-play insertion moves queued selections after the current song without changing playback state', () {
    final p = PlayerController(LxApi(), () => {});
    final songs = List.generate(6, (i) => Song(row(i), MusicSource.tx));
    p.enqueueAll(session, songs);
    p.index = 2;
    p.position = const Duration(seconds: 37);
    p.enqueueNext(session, [songs[5], songs[1], songs[2], songs[1]]);
    expect(p.current!.id, 'tx:2');
    expect(p.queue.map((s) => s.id), [
      'tx:0',
      'tx:2',
      'tx:5',
      'tx:1',
      'tx:3',
      'tx:4',
    ]);
    expect(p.index, 1);
    expect(p.position, const Duration(seconds: 37));
    expect(p.playing, false);
    p.dispose();
  });
  test(
    'Next-play without an active song creates a paused accessible queue',
    () {
      final p = PlayerController(LxApi(), () => {});
      final songs = [
        Song(row(1), MusicSource.tx),
        Song(row(2), MusicSource.tx),
      ];
      expect(p.enqueueNext(session, [...songs, songs.first]), 2);
      expect(p.current!.id, songs.first.id);
      expect(p.queue.map((s) => s.id), songs.map((s) => s.id));
      expect(p.playing, false);
      expect(p.position, Duration.zero);
      p.dispose();
    },
  );
  test('An older background read cannot roll back a completed edit', () async {
    var data = snapshot();
    final stale = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    final oldReply = Completer<http.Response>();
    Future<void>? background;
    var listReads = 0;
    late LibraryController library;
    library = LibraryController(
      LxApi(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            data = jsonDecode(request.body) as Map<String, dynamic>;
            background = library.load(session);
            return response({'success': true});
          }
          if (request.url.path == '/api/user/list') {
            listReads++;
            if (listReads == 3) return oldReply.future;
            return response(data);
          }
          return response([]);
        }),
      ),
      () {},
    );
    await library.load(session);
    await library.editSongs(
      session,
      library.collections.first,
      removeIds: {'tx:1'},
    );
    expect(library.collections.first.songs.map((s) => s.id), ['wy:1']);
    oldReply.complete(response(stale));
    await background;
    expect(library.collections.first.songs.map((s) => s.id), ['wy:1']);
    expect(library.loading, false);
    library.dispose();
  });
}
