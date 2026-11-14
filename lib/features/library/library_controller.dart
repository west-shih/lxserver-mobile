import 'package:flutter/foundation.dart';

import '../../core/lx_api.dart';

class SongBatch {
  const SongBatch(this.songs, this.hasMore);
  final List<Song> songs;
  final bool hasMore;
}

class MusicCollection {
  const MusicCollection(this.id, this.name, this.songs, {this.image = ''});
  final String id;
  final String name;
  final List<Song> songs;
  final String image;
  String get cover => image.isNotEmpty
      ? image
      : songs.where((s) => s.image.isNotEmpty).firstOrNull?.image ?? '';
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
        if (json is! Map<String, dynamic>) throw const ApiFailure('收藏响应格式不兼容');
        final custom = json['userList'];
        if (custom is! List) throw const ApiFailure('用户歌单格式不兼容');
        collections = [
          MusicCollection('love', '我的喜欢', parseSongs(json['loveList'])),
          MusicCollection('default', '默认列表', parseSongs(json['defaultList'])),
          ...custom.whereType<Map<String, dynamic>>().map(
            (v) => MusicCollection(
              '${v['id']}',
              '${v['name'] ?? '未命名歌单'}',
              parseSongs(v['list']),
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

  void reset() {
    ++_version;
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
    ++_version;
    super.dispose();
  }
}
