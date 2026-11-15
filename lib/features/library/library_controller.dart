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
    this.total,
  });
  final List<Song> songs;
  final bool hasMore;
  final CollectionMetadata metadata;
  final String image;
  final int? total;
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

List<MusicCollection> orderCollections(
  List<MusicCollection> collections,
  List<String> order,
) {
  final remaining = {for (final item in collections) item.id: item};
  return [
    for (final id in order)
      if (remaining.containsKey(id)) remaining.remove(id)!,
    ...remaining.values,
  ];
}

class LibraryController extends ChangeNotifier {
  LibraryController(this.api, this.onUnauthorized);
  final LxApi api;
  final VoidCallback onUnauthorized;
  List<MusicCollection> collections = [];
  List<String> _sidebarOrder = [];
  List<MusicCollection> _ordered(Object? data) =>
      orderCollections(parseCollections(data), _sidebarOrder);
  List<Map<String, dynamic>> artists = [];
  List<Map<String, dynamic>> albums = [];
  bool loading = false;
  String? error;
  String? artistError;
  String? albumError;
  int _version = 0;
  int _mutationVersion = 0;
  bool _entityMutating = false;
  bool isEntityFavorite(Map<String, dynamic> entity, bool artist) =>
      (artist ? artists : albums).any(
        (v) =>
            '${v['id']}' == '${entity['id']}' &&
            v['source'] == entity['source'],
      );

  Future<void> setEntityFavorite(
    Session session,
    Map<String, dynamic> entity,
    bool artist,
    bool desired,
  ) async {
    if (mutating) throw const ApiFailure('收藏正在保存，请稍后重试');
    final mutation = ++_mutationVersion;
    ++_version; // Invalidate any older library refresh before replacing a list.
    loading = false;
    mutating = true;
    _entityMutating = true;
    notifyListeners();
    final path = artist
        ? '/api/user/library/artists'
        : '/api/user/library/albums';
    bool matches(Map<String, dynamic> v) =>
        '${v['id']}' == '${entity['id']}' && v['source'] == entity['source'];
    try {
      final snapshot = await api.read(session, path);
      if (snapshot is! List ||
          snapshot.any((item) => item is! Map<String, dynamic>)) {
        throw const ApiFailure('收藏列表格式不兼容，未覆盖服务端数据');
      }
      final fresh = _entities(snapshot);
      if (mutation != _mutationVersion) return;
      final exists = fresh.any(matches);
      final next = desired
          ? [...fresh, if (!exists) entity]
          : fresh.where((v) => !matches(v)).toList();
      if (exists != desired) {
        final result = await api.writeEntities(session, artist, next);
        if (mutation != _mutationVersion) return;
        if (result is! Map || result['success'] != true) {
          throw const ApiFailure('服务端未确认收藏保存，请刷新核对');
        }
      }
      final confirmed = _entities(await api.read(session, path));
      if (mutation != _mutationVersion) return;
      if (artist) {
        artists = confirmed;
        artistError = null;
      } else {
        albums = confirmed;
        albumError = null;
      }
      if (confirmed.any(matches) != desired) {
        throw const ApiFailure('收藏回读状态不一致，请刷新核对');
      }
    } on ApiFailure catch (e) {
      if (mutation == _mutationVersion && e.unauthorized) onUnauthorized();
      rethrow;
    } finally {
      if (mutation == _mutationVersion) {
        mutating = false;
        _entityMutating = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  bool _disposed = false;
  Future<void> load(Session session) async {
    if (_entityMutating) return;
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
        collections = _ordered(json);
      }, (message) => error = message),
      part(
        '/api/user/settings',
        (json) {
          if (json is Map<String, dynamic>) {
            _sidebarOrder = sidebarOrder(json);
            collections = orderCollections(collections, _sidebarOrder);
          }
        },
        (_) {}, // Optional display settings must not hide the music library.
      ),
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
    await _editSnapshot(
      session,
      (data) => editLibrarySnapshot(
        data,
        collection.id,
        removeIds: removeIds,
        addSongs: addSongs,
        order: order,
        expectedOrder: expectedOrder,
      ),
    );
    return collections.where((v) => v.id == collection.id).firstOrNull?.songs ??
        [];
  }

  Future<void> reorderCollections(
    Session session,
    List<String> order,
    List<String> expectedOrder,
  ) async {
    if (mutating) throw const ApiFailure('歌单正在保存，请稍后重试');
    final version = _version;
    final mutationVersion = ++_mutationVersion;
    mutating = true;
    notifyListeners();
    LibraryEditResult? confirmed;
    var settingsSaved = false;
    try {
      final replies = await Future.wait([
        api.read(session, '/api/user/list'),
        api.read(session, '/api/user/settings'),
      ]);
      if (version != _version || mutationVersion != _mutationVersion) {
        throw const ApiFailure('会话或歌单状态已改变，请刷新后重试');
      }
      final settings = replies[1];
      if (settings is! Map<String, dynamic>) {
        throw const ApiFailure('账号设置格式不兼容，未保存排序');
      }
      final savedOrder = settings['favoriteSidebarOrder'];
      if (savedOrder != null &&
          (savedOrder is! List || savedOrder.any((id) => id is! String))) {
        throw const ApiFailure('账号显示顺序格式不兼容，未保存排序');
      }
      final latest = parseCollections(replies[0]);
      final previous = sidebarOrder(settings);
      final visible = orderCollections(
        latest,
        previous,
      ).map((v) => v.id).toList();
      if (!listEquals(visible, expectedOrder)) {
        throw const ApiFailure('歌单列表已发生变化，请刷新后重试');
      }
      if (order.length != visible.length ||
          order.toSet().length != order.length ||
          !setEquals(order.toSet(), visible.toSet())) {
        throw const ApiFailure('排序数据不完整，未保存');
      }
      final custom = latest.where((v) => !v.isSystem).map((v) => v.id).toList();
      final edited = reorderLibrarySnapshot(
        replies[0],
        order.where(custom.contains).toList(),
        custom,
      );
      if (edited.changed) {
        final result = await api.writeList(session, edited.snapshot);
        if (result is! Map || result['success'] != true) {
          throw const ApiFailure('服务端未确认歌单排序保存成功');
        }
        confirmed = edited;
      }
      if (mutationVersion != _mutationVersion) {
        throw const ApiFailure('会话已改变，请重新加载');
      }
      final next = mergeSidebarOrder(previous, order);
      if (!listEquals(previous, next)) {
        final result = await api.writeUserSettings(session, {
          ...settings,
          'favoriteSidebarOrder': next,
        });
        if (result is! Map || result['success'] != true) {
          throw const ApiFailure('服务端未确认显示顺序保存成功');
        }
      }
      if (mutationVersion != _mutationVersion) {
        throw const ApiFailure('会话已改变，请重新加载');
      }
      settingsSaved = true;
      _sidebarOrder = next;
      final readVersion = ++_version;
      loading = false;
      collections = _ordered(edited.snapshot);
      error = null;
      notifyListeners();
      try {
        final fresh = await Future.wait([
          api.read(session, '/api/user/list'),
          api.read(session, '/api/user/settings'),
        ]);
        if (readVersion == _version && mutationVersion == _mutationVersion) {
          if (fresh[1] is! Map<String, dynamic>) {
            throw const ApiFailure('账号设置格式不兼容');
          }
          _sidebarOrder = sidebarOrder(fresh[1] as Map<String, dynamic>);
          collections = _ordered(fresh[0]);
        }
      } on ApiFailure catch (e) {
        if (e.unauthorized) rethrow;
        if (mutationVersion == _mutationVersion) error = '排序已保存，但重新读取失败，请刷新';
      } catch (_) {
        if (mutationVersion == _mutationVersion) error = '排序已保存，但重新读取失败，请刷新';
      }
    } on ApiFailure catch (e) {
      if (mutationVersion == _mutationVersion) {
        if (e.unauthorized) onUnauthorized();
        if (!e.unauthorized && confirmed != null && !settingsSaved) {
          ++_version;
          loading = false;
          collections = _ordered(confirmed.snapshot);
          throw const ApiFailure('私人歌单顺序已保存，但显示顺序未确认保存，请刷新后重试');
        }
      }
      rethrow;
    } finally {
      if (mutationVersion == _mutationVersion) {
        mutating = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<void> _editSnapshot(
    Session session,
    LibraryEditResult Function(Object) transform,
  ) async {
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
      final edited = transform(data);
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
      collections = _ordered(edited.snapshot);
      error = null;
      notifyListeners();
      if (edited.changed) {
        try {
          final fresh = await api.read(session, '/api/user/list');
          if (mutationVersion == _mutationVersion && readVersion == _version) {
            collections = _ordered(fresh);
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
    _entityMutating = false;
    collections = [];
    _sidebarOrder = [];
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
