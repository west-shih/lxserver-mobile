import 'package:flutter/foundation.dart';

import '../../core/lx_api.dart';
import '../../core/page_window.dart';
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
  MusicSource source = MusicSource.wy;
  bool aggregate = false;
  List<MusicSource> sources = musicSourceOrder;
  final Map<MusicSource, List<PlaylistSummary>> _buckets = {};
  final Map<MusicSource, int> _pages = {};
  final Set<MusicSource> _more = {};
  final Map<MusicSource, String> _defaultSorts = {};
  final Map<MusicSource, String> sourceFailures = {};
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
  int resultRevision = 0;
  final _window = PageWindow<PlaylistSummary>(
    (item) => '${item.source.name}:${item.id}',
  );
  int? get total => aggregate ? null : _window.total;
  bool get hasWindow => !aggregate && _window.ready && total != null;
  List<PlaylistSummary> pageItems(int displayPage, int size) => hasWindow
      ? _window.items(displayPage, size)
      : playlists.skip(displayPage * size).take(size).toList();

  Future<void> ensurePage(Session session, int displayPage, int size) async {
    if (!hasWindow) return;
    final version = ++_version;
    final platform = source;
    final query = keyword;
    loading = true;
    error = null;
    notifyListeners();
    try {
      for (final nativePage in _window.missing(displayPage, size)) {
        final data = await api.read(
          session,
          query.isEmpty
              ? '/api/music/songList/list'
              : '/api/music/songList/search',
          query: {
            'source': platform.name,
            'page': '$nativePage',
            if (query.isEmpty) ...{
              'tagId': tag,
              'sortId': sort.isEmpty ? 'hot' : sort,
            } else
              'text': query,
          },
        );
        if (version != _version) return;
        if (data is! Map || data['list'] is! List) {
          throw const ApiFailure('歌单列表格式不兼容');
        }
        final items = (data['list'] as List)
            .whereType<Map<String, dynamic>>()
            .map((v) => PlaylistSummary(v, platform))
            .toList();
        if (items.isEmpty) break;
        final known = _window.all.map((item) => item.id).toSet();
        if (items.every((item) => known.contains(item.id))) {
          throw const ApiFailure('该页返回重复结果，请尝试前面的页码');
        }
        final nativeSize = resultTotal(data['limit']) ?? _window.nativeSize!;
        final reported = resultTotal(data['total']);
        _window.add(
          nativePage,
          items,
          total: reported,
          size: nativeSize,
          hasMore:
              items.isNotEmpty &&
              (reported == null || nativePage * nativeSize < reported),
        );
        playlists = _window.all;
        page = _window.contiguousPages;
        hasMore = _window.hasMore;
        notifyListeners();
      }
      if (version == _version && _window.items(displayPage, size).isEmpty) {
        throw const ApiFailure('该页暂无结果，请尝试前面的页码');
      }
    } on ApiFailure catch (e) {
      if (version != _version) return;
      error = e.message;
      if (e.unauthorized) onUnauthorized();
      rethrow;
    } finally {
      if (version == _version) {
        loading = false;
        notifyListeners();
      }
    }
  }

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
      resultRevision++;
      _window.clear();
      playlists = [];
      page = 0;
      hasMore = false;
    }
    notifyListeners();
    if (aggregate) return _loadAggregate(session, more, version);
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
          .map((v) => PlaylistSummary(v, source))
          .toList();
      final ids = playlists.map((v) => v.id).toSet();
      final fresh = received.where((v) => ids.add(v.id)).toList();
      playlists = [...playlists, ...fresh];
      page = requestedPage;
      final total = num.tryParse('${data['total']}');
      final limit = num.tryParse('${data['limit']}');
      hasMore =
          fresh.isNotEmpty &&
          (total != null && limit != null ? page * limit < total : true);
      _window.add(
        requestedPage,
        received,
        total: resultTotal(data['total']),
        size: limit != null && limit > 0 ? limit.toInt() : null,
        hasMore: hasMore,
      );
      if (hasWindow) {
        playlists = _window.all;
        page = _window.contiguousPages;
        hasMore = fresh.isNotEmpty && _window.hasMore;
      }
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
    aggregate = false;
    source = value;
    tag = '';
    tagName = '全部分类';
    sort = '';
    groups = [];
    sorts = [];
    return load(session, categories: true);
  }

  Future<void> selectAggregate(Session session) {
    aggregate = true;
    tag = '';
    tagName = '全部分类';
    sort = '';
    groups = [];
    sorts = [];
    return load(session);
  }

  Future<void> _loadAggregate(Session session, bool more, int version) async {
    if (!more) {
      _buckets.clear();
      _pages.clear();
      _more.clear();
      sourceFailures.clear();
      _more.addAll(sources);
    }
    final targets = List<MusicSource>.of(sources);
    final query = keyword;
    try {
      await Future.wait(
        targets.where(_more.contains).map((platform) async {
          try {
            if (query.isEmpty && !_defaultSorts.containsKey(platform)) {
              final tags = await api.read(
                session,
                '/api/music/songList/tags',
                query: {'source': platform.name},
              );
              if (version != _version) return;
              if (tags is! Map || tags['sortList'] is! List) {
                throw const ApiFailure('歌单排序格式不兼容');
              }
              final sorts = (tags['sortList'] as List).whereType<Map>();
              _defaultSorts[platform] = sorts.isEmpty
                  ? 'hot'
                  : '${sorts.first['id']}';
            }
            final next = (_pages[platform] ?? 0) + 1;
            final data = await api.read(
              session,
              query.isEmpty
                  ? '/api/music/songList/list'
                  : '/api/music/songList/search',
              query: {
                'source': platform.name,
                'page': '$next',
                if (query.isEmpty) ...{
                  'tagId': '',
                  'sortId': _defaultSorts[platform]!,
                } else
                  'text': query,
              },
            );
            if (version != _version) return;
            if (data is! Map || data['list'] is! List) {
              throw const ApiFailure('歌单列表格式不兼容');
            }
            final bucket = _buckets.putIfAbsent(platform, () => []);
            final ids = bucket.map((v) => v.id).toSet();
            final fresh = (data['list'] as List)
                .whereType<Map<String, dynamic>>()
                .map((v) => PlaylistSummary(v, platform))
                .where((v) => ids.add(v.id))
                .toList();
            bucket.addAll(fresh);
            _pages[platform] = next;
            final total = num.tryParse('${data['total']}');
            final limit = num.tryParse('${data['limit']}');
            if (fresh.isEmpty ||
                (total != null && limit != null && next * limit >= total)) {
              _more.remove(platform);
            }
            sourceFailures.remove(platform);
          } on ApiFailure catch (e) {
            if (version != _version) return;
            sourceFailures[platform] = e.message;
            if (e.unauthorized) onUnauthorized();
          } catch (_) {
            if (version == _version) sourceFailures[platform] = '歌单加载失败';
          }
          if (version != _version) return;
          final length = _buckets.values.fold(
            0,
            (max, list) => list.length > max ? list.length : max,
          );
          playlists = [
            for (var i = 0; i < length; i++)
              for (final platform in targets)
                if (i < (_buckets[platform]?.length ?? 0))
                  _buckets[platform]![i],
          ];
          hasMore = _more.isNotEmpty;
          error = sourceFailures.isEmpty
              ? null
              : '暂时无法加载：${sourceFailures.keys.map((v) => v.label).join('、')}，其他平台结果不受影响';
          notifyListeners();
        }),
      );
      if (version == _version) {
        page++;
        if (targets.isEmpty) error = '暂无可用音源';
      }
    } finally {
      if (version == _version) {
        loading = false;
        notifyListeners();
      }
    }
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
      total: resultTotal(data['total']),
    );
  }

  void reset() {
    resultRevision++;
    _window.clear();
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
    _buckets.clear();
    _pages.clear();
    _more.clear();
    _defaultSorts.clear();
    sourceFailures.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    ++_version;
    super.dispose();
  }
}
