import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/lx_api.dart';
import '../discovery/discovery_controller.dart';
import 'collection_metadata.dart';
import 'library_song.dart';
import 'library_edit.dart';

class SongBatch {
  const SongBatch(
    this.songs,
    this.hasMore, {
    this.image = '',
    this.metadata = const CollectionMetadata(),
  });
  final List<Song> songs;
  final bool hasMore;
  final CollectionMetadata metadata;
  final String image;
}

class MusicCollection {
  const MusicCollection(
    this.id,
    this.name,
    this.songs, {
    this.image = '',
    this.source,
    this.sourceListId = '',
    this.metadata = const CollectionMetadata(),
  });
  final String id;
  final String name;
  final List<Song> songs;
  final String image;
  final MusicSource? source;
  final String sourceListId;
  final CollectionMetadata metadata;
  bool get isSystem => id == 'love' || id == 'default';
  bool get isLinked => source != null && sourceListId.isNotEmpty;
  String get cover => image;
}

List<MusicCollection> parseCollections(Object? json) {
  if (json is! Map<String, dynamic>) throw const ApiFailure('收藏响应格式不兼容');
  final custom = json['userList'];
  if (custom is! List) throw const ApiFailure('用户歌单格式不兼容');
  return [
    MusicCollection('love', '我的喜欢', parseSongs(json['loveList'])),
    MusicCollection('default', '默认列表', parseSongs(json['defaultList'])),
    ...custom.whereType<Map<String, dynamic>>().map(
      (v) => MusicCollection(
        '${v['id']}',
        '${v['name'] ?? '未命名歌单'}',
        parseSongs(v['list']),
        source: MusicSource.values
            .where((s) => s.name == v['source'])
            .firstOrNull,
        sourceListId: '${v['sourceListId'] ?? ''}',
        image: firstImage([
          v['Album'],
          v['album'],
          v['cover'],
          v['pic'],
          v['picUrl'],
        ]),
      ),
    ),
  ];
}

List<Song> parseSongs(Object? json, {MusicSource fallback = MusicSource.kw}) {
  if (json is! List) throw const ApiFailure('歌曲列表格式不兼容');
  return json
      .whereType<Map<String, dynamic>>()
      .map((v) => Song(v, fallback))
      .toList();
}

class LibraryController extends ChangeNotifier {
  LibraryController(this.api, this.onUnauthorized);
  final LxApi api;
  final VoidCallback onUnauthorized;
  List<MusicCollection> collections = [];
  List<Map<String, dynamic>> artists = [];
  List<Map<String, dynamic>> albums = [];
  bool loading = false;
  String? error;
  String? artistError;
  String? albumError;
  int _version = 0;
  int _mutationVersion = 0;
  bool _disposed = false;
  Future<void> load(Session session) async {
    final version = ++_version;
    loading = true;
    error = null;
    artistError = null;
    albumError = null;
    notifyListeners();
    Future<void> part(
      String path,
      void Function(Object) update,
      void Function(String) failure,
    ) async {
      try {
        final data = await api.read(session, path);
        if (version == _version) update(data);
      } on ApiFailure catch (e) {
        if (version != _version) return;
        failure(e.message);
        if (e.unauthorized) onUnauthorized();
      } catch (_) {
        if (version == _version) failure('数据格式不兼容，请检查服务端版本');
      }
      if (version == _version) notifyListeners();
    }

    await Future.wait([
      part('/api/user/list', (json) {
        collections = parseCollections(json);
      }, (message) => error = message),
      part(
        '/api/user/library/artists',
        (json) => artists = _entities(json),
        (message) => artistError = message,
      ),
      part(
        '/api/user/library/albums',
        (json) => albums = _entities(json),
        (message) => albumError = message,
      ),
    ]);
    if (version == _version) {
      loading = false;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> _entities(Object data) {
    if (data is! List) throw const ApiFailure('收藏列表格式不兼容');
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<SongBatch> entitySongs(
    Session session,
    Map<String, dynamic> entity,
    bool artist,
  ) async {
    final platform = MusicSource.values
        .where((s) => s.name == entity['source'])
        .firstOrNull;
    if (platform == null) throw const ApiFailure('该收藏的平台暂不支持');
    final data = await api.read(
      session,
      artist ? '/api/music/artistSongs' : '/api/music/albumSongs',
      query: {'source': platform.name, 'id': '${entity['id']}'},
    );
    return SongBatch(
      parseSongs(data is Map ? data['list'] : data, fallback: platform),
      false,
    );
  }

  Future<SongBatch> remoteSongs(
    Session session,
    PlaylistSummary summary,
    Future<SongBatch> Function(Session, PlaylistSummary, int) fetch,
  ) async {
    final songs = <Song>[];
    final ids = <String>{};
    var image = '';
    var metadata = const CollectionMetadata();
    for (var page = 1; page <= 1000; page++) {
      final batch = await fetch(session, summary, page);
      image = firstImage([image, batch.image]);
      metadata = metadata.merge(batch.metadata);
      final fresh = batch.songs.where((song) => ids.add(song.id)).toList();
      songs.addAll(fresh);
      if (!batch.hasMore) {
        return SongBatch(songs, false, image: image, metadata: metadata);
      }
      if (fresh.isEmpty) throw const ApiFailure('原歌单分页重复或不完整，未覆盖现有歌曲');
    }
    throw const ApiFailure('原歌单超过分页限制，未覆盖现有歌曲');
  }

  Future<bool> collectRemote(
    Session session,
    PlaylistSummary summary,
    Future<SongBatch> Function(Session, PlaylistSummary, int) fetch,
  ) async {
    if (mutating) throw const ApiFailure('歌单正在更新，请稍后重试');
    final version = _version;
    final mutationVersion = ++_mutationVersion;
    mutating = true;
    notifyListeners();
    try {
      final complete = await remoteSongs(session, summary, fetch);
      if (version != _version) return false;
      final json = await api.read(session, '/api/user/list');
      if (version != _version) return false;
      if (json is! Map<String, dynamic> ||
          json['userList'] is! List ||
          json['loveList'] is! List ||
          json['defaultList'] is! List) {
        throw const ApiFailure('歌单格式不兼容，未保存');
      }
      final lists = (json['userList'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      if (lists.any(
        (v) =>
            v['source'] == summary.source.name &&
            '${v['sourceListId']}' == summary.id,
      )) {
        await load(session);
        return false;
      }
      final random = Random.secure();
      final id =
          '${summary.source.name}_${List.generate(4, (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')).join()}';
      lists.add({
        'id': id,
        'name': summary.name,
        'source': summary.source.name,
        'sourceListId': summary.id,
        'Album': firstImage([complete.image, summary.image]),
        'locationUpdateTime': null,
        'list': complete.songs.map(librarySong).toList(),
      });
      final result = await api.writeList(session, {...json, 'userList': lists});
      if (result is! Map || result['success'] != true) {
        throw const ApiFailure('服务端未确认收藏成功');
      }
      if (version == _version) {
        await load(session);
      }
      return true;
    } on ApiFailure catch (e) {
      if (version == _version && e.unauthorized) onUnauthorized();
      rethrow;
    } finally {
      if (mutationVersion == _mutationVersion) {
        mutating = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  bool mutating = false;
  Future<void> changeCollection(
    Session session,
    MusicCollection collection, {
    List<Song>? replacement,
    String? image,
    String? name,
  }) async {
    if (collection.isSystem || mutating) {
      throw const ApiFailure('歌单操作未完成，请刷新后重试');
    }
    if (name != null && name.trim().isEmpty) {
      throw const ApiFailure('歌单名称不能为空');
    }
    final version = _version;
    final mutationVersion = ++_mutationVersion;
    mutating = true;
    notifyListeners();
    try {
      final data = await api.read(session, '/api/user/list');
      if (version != _version) return;
      if (data is! Map<String, dynamic> ||
          data['userList'] is! List ||
          data['loveList'] is! List ||
          data['defaultList'] is! List) {
        throw const ApiFailure('歌单操作未完成，请刷新后重试');
      }
      final lists = (data['userList'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      final index = lists.indexWhere((v) => '${v['id']}' == collection.id);
      if (index < 0) throw const ApiFailure('歌单操作未完成，请刷新后重试');
      if (name != null) {
        lists[index] = {...lists[index], 'name': name.trim()};
      } else if (replacement == null) {
        lists.removeAt(index);
      } else {
        if (lists[index]['source'] != collection.source?.name ||
            '${lists[index]['sourceListId']}' != collection.sourceListId) {
          throw const ApiFailure('歌单操作未完成，请刷新后重试');
        }
        lists[index] = {
          ...lists[index],
          'list': replacement.map(librarySong).toList(),
          if (image != null && image.trim().isNotEmpty) 'Album': image.trim(),
        };
      }
      final result = await api.writeList(session, {...data, 'userList': lists});
      if (result is! Map || result['success'] != true) {
        throw const ApiFailure('歌单操作未完成，请刷新后重试');
      }
      if (version == _version) {
        await load(session);
      }
    } on ApiFailure catch (e) {
      if (version == _version && e.unauthorized) onUnauthorized();
      rethrow;
    } finally {
      if (mutationVersion == _mutationVersion) {
        mutating = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<List<Song>> editSongs(
    Session session,
    MusicCollection collection, {
    Set<String> removeIds = const {},
    List<Song> addSongs = const [],
    List<String>? order,
    List<String>? expectedOrder,
  }) async {
    if (mutating) throw const ApiFailure('歌单正在保存，请稍后重试');
    final version = _version;
    final mutationVersion = ++_mutationVersion;
    mutating = true;
    notifyListeners();
    try {
      final data = await api.read(session, '/api/user/list');
      if (version != _version || mutationVersion != _mutationVersion) {
        throw const ApiFailure('会话或歌单状态已改变，请重试');
      }
      final edited = editLibrarySnapshot(
        data,
        collection.id,
        removeIds: removeIds,
        addSongs: addSongs,
        order: order,
        expectedOrder: expectedOrder,
      );
      if (edited.changed) {
        final result = await api.writeList(session, edited.snapshot);
        if (result is! Map || result['success'] != true) {
          throw const ApiFailure('服务端未确认歌单保存成功');
        }
      }
      if (mutationVersion != _mutationVersion) {
        throw const ApiFailure('会话已改变，请重新加载歌单');
      }
      final readVersion = ++_version;
      loading = false;
      collections = parseCollections(edited.snapshot);
      error = null;
      notifyListeners();
      if (edited.changed) {
        try {
          final fresh = await api.read(session, '/api/user/list');
          if (mutationVersion == _mutationVersion && readVersion == _version) {
            collections = parseCollections(fresh);
            notifyListeners();
          }
        } on ApiFailure catch (e) {
          if (e.unauthorized) rethrow;
          if (mutationVersion == _mutationVersion) error = '修改已保存，但重新读取失败，请刷新';
        } catch (_) {
          if (mutationVersion == _mutationVersion) error = '修改已保存，但重新读取失败，请刷新';
        }
      }
      if (mutationVersion != _mutationVersion) {
        throw const ApiFailure('会话已改变，请重新加载歌单');
      }
      return collections
              .where((v) => v.id == collection.id)
              .firstOrNull
              ?.songs ??
          edited.songs;
    } on ApiFailure catch (e) {
      if (mutationVersion == _mutationVersion && e.unauthorized) {
        onUnauthorized();
      }
      rethrow;
    } finally {
      if (mutationVersion == _mutationVersion) {
        mutating = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  void reset() {
    ++_version;
    ++_mutationVersion;
    mutating = false;
    collections = [];
    artists = [];
    albums = [];
    loading = false;
    error = null;
    artistError = null;
    albumError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_mutationVersion;
    ++_version;
    super.dispose();
  }
}
