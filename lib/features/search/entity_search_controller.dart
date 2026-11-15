import 'package:flutter/foundation.dart';

import '../../core/lx_api.dart';
import '../../core/page_window.dart';
import 'music_entity.dart';

class EntitySearchController extends ChangeNotifier {
  EntitySearchController(this.api, this.onUnauthorized);
  final LxApi api;
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
        final data = await api.read(
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
      final data = await api.read(
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
