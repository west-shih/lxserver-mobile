import 'package:flutter/foundation.dart';

import '../../core/lx_api.dart';
import '../library/library_controller.dart';
import '../library/collection_metadata.dart';

class PlaylistSummary {
  PlaylistSummary(this.data, this.source);
  final Map<String, dynamic> data;
  final MusicSource source;
  String get id => '${data['id']}';
  String get name => '${data['name'] ?? '未命名歌单'}';
  String get image => '${data['img'] ?? ''}';
  CollectionMetadata get metadata => CollectionMetadata.fromJson(data);
  String get author => '${data['author'] ?? ''}';
  String get count => '${data['play_count'] ?? ''}';
}

class DiscoveryController extends ChangeNotifier {
  DiscoveryController(this.api, this.onUnauthorized);
  final LxApi api;
  final VoidCallback onUnauthorized;
  MusicSource source = MusicSource.kg;
  String tag = '';
  String tagName = '全部分类';
  String sort = '';
  List<Map<String, dynamic>> groups = [];
  List<Map<String, dynamic>> sorts = [];
  List<PlaylistSummary> playlists = [];
  String keyword = '';
  int page = 0;
  bool hasMore = false;
  bool loading = false;
  String? error;
  int _version = 0;
  Future<void> load(
    Session session, {
    bool more = false,
    bool categories = false,
  }) async {
    if (more && loading) return;
    final version = ++_version;
    loading = true;
    error = null;
    if (!more) {
      playlists = [];
      page = 0;
      hasMore = false;
    }
    notifyListeners();
    try {
      if (categories) {
        final data = await api.read(
          session,
          '/api/music/songList/tags',
          query: {'source': source.name},
        );
        if (version != _version) return;
        if (data is! Map) throw const ApiFailure('歌单分类格式不兼容');
        groups = (data['tags'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        sorts = (data['sortList'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        sort = sorts.isNotEmpty ? '${sorts.first['id']}' : 'hot';
      }
      final requestedPage = page + 1;
      final data = await api.read(
        session,
        keyword.isEmpty
            ? '/api/music/songList/list'
            : '/api/music/songList/search',
        query: {
          'source': source.name,
          'page': '$requestedPage',
          if (keyword.isEmpty) ...{
            'tagId': tag,
            'sortId': sort.isEmpty ? 'hot' : sort,
          } else
            'text': keyword,
        },
      );
      if (version != _version) return;
      if (data is! Map || data['list'] is! List) {
        throw const ApiFailure('歌单列表格式不兼容');
      }
      final received = (data['list'] as List)
          .whereType<Map<String, dynamic>>()
          .map((v) => PlaylistSummary(v, source));
      final ids = playlists.map((v) => v.id).toSet();
      final fresh = received.where((v) => ids.add(v.id)).toList();
      playlists = [...playlists, ...fresh];
      page = requestedPage;
      final total = num.tryParse('${data['total']}');
      final limit = num.tryParse('${data['limit']}');
      hasMore =
          fresh.isNotEmpty &&
          (total != null && limit != null ? page * limit < total : true);
    } on ApiFailure catch (e) {
      if (version != _version) return;
      error = e.message;
      if (e.unauthorized) onUnauthorized();
    } catch (_) {
      if (version == _version) error = '歌单数据不兼容，请尝试其他平台';
    } finally {
      if (version == _version) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> changeSource(Session session, MusicSource value) {
    source = value;
    tag = '';
    tagName = '全部分类';
    sort = '';
    groups = [];
    sorts = [];
    return load(session, categories: true);
  }

  PlaylistSummary originalSummary(MusicCollection collection) {
    final source = collection.source;
    if (source == null || collection.sourceListId.isEmpty) {
      throw const ApiFailure('该歌单没有可打开的原平台来源');
    }
    return playlists
            .where((p) => p.source == source && p.id == collection.sourceListId)
            .firstOrNull ??
        PlaylistSummary({
          'id': collection.sourceListId,
          'name': collection.name,
          'img': collection.cover,
        }, source);
  }

  Future<SongBatch> detail(
    Session session,
    PlaylistSummary summary,
    int page,
  ) async {
    final data = await api.read(
      session,
      '/api/music/songList/detail',
      query: {'source': summary.source.name, 'id': summary.id, 'page': '$page'},
    );
    if (data is! Map) throw const ApiFailure('歌单详情格式不兼容');
    final songs = parseSongs(data['list'], fallback: summary.source);
    final info = data['info'] is Map ? data['info'] as Map : const {};
    final total = num.tryParse('${data['total']}');
    final limit = num.tryParse('${data['limit']}');
    return SongBatch(
      songs,
      songs.isNotEmpty &&
          (total != null && limit != null ? page * limit < total : true),
      image: firstImage([info['img'], info['pic']]),
      metadata: summary.metadata.merge(CollectionMetadata.fromJson(info)),
    );
  }

  void reset() {
    ++_version;
    playlists = [];
    groups = [];
    sorts = [];
    keyword = '';
    tag = '';
    tagName = '全部分类';
    sort = '';
    page = 0;
    hasMore = false;
    loading = false;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    ++_version;
    super.dispose();
  }
}
