import 'package:flutter/foundation.dart';

import '../../core/lx_api.dart';
import '../../core/page_window.dart';
import 'music_entity.dart';

class EntitySearchController extends ChangeNotifier {
  EntitySearchController(this.api, this.onUnauthorized);
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
    if (_checkingExpiry || loading || keyword.isEmpty || page == 0) return;
    _checkingExpiry = true;
    final version = _version;
    final staged = EntitySearchController(api, () {
      if (version == _version) onUnauthorized();
    })..restoreSnapshot(snapshot());
    try {
      final changed = await api.revalidateBrowse(() async {
        await staged.search(session, keyword);
        if (staged.error != null) throw StateError('Incomplete search refresh');
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
  SearchKind kind = SearchKind.song;
  MusicSource source = MusicSource.wy;
  String keyword = '';
  List<MusicEntity> items = [];
  int page = 0;
  int? total;
  bool loading = false, hasMore = false;
  String? error;
  int _version = 0;
  int revision = 0;
  final _window = PageWindow<MusicEntity>((e) => e.key);
  Map<String, dynamic> snapshot() => {
    'kind': kind.name,
    'source': source.name,
    'keyword': keyword,
    'items': items.map((e) => e.raw).toList(),
    'page': page,
    'total': total,
    'hasMore': hasMore,
    'revision': revision,
    'window': _window.snapshot((e) => e.raw),
  };
  void restoreSnapshot(Map value) {
    kind =
        SearchKind.values.where((e) => e.name == value['kind']).firstOrNull ??
        SearchKind.song;
    source =
        MusicSource.values
            .where((e) => e.name == value['source'])
            .firstOrNull ??
        MusicSource.wy;
    keyword = value['keyword'] is String ? value['keyword'] : '';
    MusicEntity decode(Map<String, dynamic> data) =>
        MusicEntity(data, source, kind == SearchKind.artist);
    items = (value['items'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(decode)
        .toList();
    page = resultTotal(value['page']) ?? 0;
    total = resultTotal(value['total']);
    hasMore = value['hasMore'] == true;
    revision = resultTotal(value['revision']) ?? 0;
    if (value['window'] is Map) {
      _window.restoreSnapshot(value['window'], decode);
    }
    loading = false;
    error = null;
  }

  bool get hasWindow => _window.ready && total != null;
  List<MusicEntity> pageItems(int page, int size) => hasWindow
      ? _window.items(page, size)
      : items.skip(page * size).take(size).toList();
  Future<void> ensurePage(Session session, int displayPage, int size) async {
    if (!hasWindow || loading) return;
    final version = ++_version;
    loading = true;
    error = null;
    notifyListeners();
    try {
      for (final native in _window.missing(displayPage, size)) {
        final data = await _read(
          session,
          '/api/music/search',
          query: {
            'name': keyword,
            'source': source.name,
            'type': kind.apiType,
            'page': '$native',
            'limit': '20',
          },
        );
        if (version != _version) return;
        if (data is! Map<String, dynamic>) throw const ApiFailure('搜索结果格式不兼容');
        final result = parseEntities(
          data['list'],
          source,
          kind == SearchKind.artist,
        );
        final known = items.map((e) => e.key).toSet();
        if (result.isEmpty || result.every((e) => known.contains(e.key))) {
          throw const ApiFailure('该页为空或重复，请尝试前面的页码');
        }
        final reported = resultTotal(data['total']);
        if (reported != null && reported > 0) total = reported;
        _window.add(native, result, total: total, size: 20, hasMore: true);
        items = _window.all;
      }
    } on ApiFailure catch (e) {
      if (version != _version) return;
      error = e.message;
      if (e.unauthorized) onUnauthorized();
    } catch (_) {
      if (version == _version) error = '该页加载失败，请重试';
    } finally {
      if (version == _version) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void clear() {
    ++_version;
    revision++;
    _window.clear();
    items = [];
    page = 0;
    total = null;
    loading = false;
    hasMore = false;
    error = null;
  }

  void reset() {
    clear();
    kind = SearchKind.song;
    keyword = '';
    source = MusicSource.wy;
    notifyListeners();
  }

  Future<void> select(
    Session session,
    SearchKind value,
    MusicSource platform,
    String query,
  ) async {
    clear();
    kind = value;
    source = platform;
    keyword = query.trim();
    notifyListeners();
    if (value != SearchKind.song && keyword.isNotEmpty) {
      await search(session, keyword);
    }
  }

  Future<void> search(
    Session session,
    String query, {
    bool more = false,
  }) async {
    if (kind == SearchKind.song ||
        !supportsEntities(source) ||
        (more && (loading || !hasMore))) {
      return;
    }
    final retained = !more && api.refreshingBrowse ? List.of(items) : null;
    final retainedWindow = _window.copy();
    final retainedPage = page, retainedTotal = total;
    final retainedMore = hasMore;
    if (!more) clear();
    keyword = query.trim();
    if (keyword.isEmpty) {
      notifyListeners();
      return;
    }
    final version = ++_version;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final next = page + 1;
      final data = await _read(
        session,
        '/api/music/search',
        query: {
          'name': keyword,
          'source': source.name,
          'type': kind.apiType,
          'page': '$next',
          'limit': '20',
        },
      );
      if (version != _version) return;
      if (data is! Map<String, dynamic>) throw const ApiFailure('搜索结果格式不兼容');
      final result = parseEntities(
        data['list'],
        source,
        kind == SearchKind.artist,
      );
      final ids = items.map((v) => v.key).toSet();
      final fresh = result.where((v) => ids.add(v.key)).toList();
      page = next;
      final reported = int.tryParse('${data['total']}');
      // 网易后续原生页可能不返回总数，保留首屏总数。
      if (reported != null && reported > 0) total = reported;
      _window.add(
        next,
        result,
        total: total,
        size: 20,
        hasMore: fresh.isNotEmpty && result.length >= 20,
      );
      items = _window.all;
      hasMore =
          fresh.isNotEmpty &&
          (total != null ? items.length < total! : result.length >= 20);
    } on ApiFailure catch (e) {
      if (version != _version) return;
      error = e.message;
      if (e.unauthorized) onUnauthorized();
    } catch (_) {
      if (version == _version) error = '搜索暂时失败，请重试';
    } finally {
      if (version == _version) {
        if (error != null && retained != null) {
          items = retained;
          page = retainedPage;
          total = retainedTotal;
          hasMore = retainedMore;
          _window.restore(retainedWindow);
        }
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    ++_version;
    super.dispose();
  }
}
