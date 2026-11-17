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
  Future<Object> _read(
    Session session,
    String path, {
    Map<String, String>? query,
  }) {
    final version = _version;

    return api.browseQuery(
      () => version == _version,
      () => api.read(session, path, query: query),
    );
  }

  final LxApi api;
  bool _checkingExpiry = false;
  Future<void> revalidate(Session session) async {
    if (_checkingExpiry || loading || page == 0) return;
    _checkingExpiry = true;
    final version = _version;
    final staged =
        DiscoveryController(api, () {
            if (version == _version) onUnauthorized();
          })
          ..restoreSnapshot(snapshot())
          ..sources = List.of(sources);
    try {
      final changed = await api.revalidateBrowse(() async {
        await staged.load(session, categories: !aggregate);
        if (staged.error != null) throw StateError('Incomplete browse refresh');
      }, current: () => version == _version);
      if (changed && version == _version && staged.error == null) {
        restoreSnapshot(staged.snapshot());
        notifyListeners();
      }
    } finally {
      staged.dispose();
      _checkingExpiry = false;
    }
  }

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
  Map<String, dynamic> snapshot() => {
    'source': source.name,
    'aggregate': aggregate,
    'keyword': keyword,
    'tag': tag,
    'tagName': tagName,
    'sort': sort,
    'groups': groups,
    'sorts': sorts,
    'page': page,
    'hasMore': hasMore,
    'revision': resultRevision,
    'items': playlists
        .map((e) => {'source': e.source.name, 'data': e.data})
        .toList(),
    'buckets': {
      for (final e in _buckets.entries)
        e.key.name: e.value.map((v) => v.data).toList(),
    },
    'pages': {for (final e in _pages.entries) e.key.name: e.value},
    'more': _more.map((e) => e.name).toList(),
    'defaults': {for (final e in _defaultSorts.entries) e.key.name: e.value},
    'window': _window.snapshot((e) => e.data),
  };
  void restoreSnapshot(Map value) {
    MusicSource platform(Object? id) =>
        MusicSource.values.where((e) => e.name == id).firstOrNull ??
        MusicSource.wy;
    source = platform(value['source']);
    aggregate = value['aggregate'] == true;
    keyword = '${value['keyword'] ?? ''}';
    tag = '${value['tag'] ?? ''}';
    tagName = '${value['tagName'] ?? '全部分类'}';
    sort = '${value['sort'] ?? ''}';
    groups = (value['groups'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    sorts = (value['sorts'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    playlists = (value['items'] as List? ?? [])
        .whereType<Map>()
        .where((e) => e['data'] is Map<String, dynamic>)
        .map((e) => PlaylistSummary(e['data'], platform(e['source'])))
        .toList();
    _buckets.clear();
    _pages.clear();
    _more.clear();
    _defaultSorts.clear();
    if (value['buckets'] is Map) {
      for (final e in (value['buckets'] as Map).entries) {
        _buckets[platform(e.key)] = (e.value as List)
            .whereType<Map<String, dynamic>>()
            .map((v) => PlaylistSummary(v, platform(e.key)))
            .toList();
      }
    }
    if (value['pages'] is Map) {
      for (final e in (value['pages'] as Map).entries) {
        _pages[platform(e.key)] = resultTotal(e.value) ?? 0;
      }
    }
    for (final e in value['more'] as List? ?? []) {
      _more.add(platform(e));
    }
    if (value['defaults'] is Map) {
      for (final e in (value['defaults'] as Map).entries) {
        _defaultSorts[platform(e.key)] = '${e.value}';
      }
    }
    page = resultTotal(value['page']) ?? 0;
    hasMore = value['hasMore'] == true;
    resultRevision = resultTotal(value['revision']) ?? 0;
    if (value['window'] is Map) {
      _window.restoreSnapshot(
        value['window'],
        (data) => PlaylistSummary(data, source),
      );
    }
    loading = false;
    error = null;
  }

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
        final data = await _read(
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
    final retained = !more && api.refreshingBrowse ? List.of(playlists) : null;
    final oldWindow = _window.copy();
    final oldBuckets = Map.of(_buckets), oldPages = Map.of(_pages);
    final oldMore = Set.of(_more);
    final oldPage = page, oldHasMore = hasMore;
    void restoreFailedRefresh() {
      if (version != _version ||
          retained == null ||
          error == null ||
          playlists.isNotEmpty) {
        return;
      }
      playlists = retained;
      _window.restore(oldWindow);
      _buckets
        ..clear()
        ..addAll(oldBuckets);
      _pages
        ..clear()
        ..addAll(oldPages);
      _more
        ..clear()
        ..addAll(oldMore);
      page = oldPage;
      hasMore = oldHasMore;
    }

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
    if (aggregate) {
      await _loadAggregate(session, more, version);
      restoreFailedRefresh();
      if (version == _version) notifyListeners();
      return;
    }
    try {
      if (categories) {
        final data = await _read(
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
        if (!sorts.any((item) => '${item['id']}' == sort)) {
          sort = sorts.isNotEmpty ? '${sorts.first['id']}' : 'hot';
        }
      }
      final requestedPage = page + 1;
      final data = await _read(
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
        restoreFailedRefresh();
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
              final tags = await _read(
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
            final data = await _read(
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
