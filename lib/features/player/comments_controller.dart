import 'package:flutter/foundation.dart';

import '../../core/lx_api.dart';

class CommentsController extends ChangeNotifier {
  CommentsController(
    this.api,
    this.session,
    this.song,
    this.onUnauthorized, {
    this.pageSize = 20,
  });
  final LxApi api;
  final Session session;
  final Song song;
  final VoidCallback onUnauthorized;
  final int pageSize;
  bool get sequentialOnly => song.source == MusicSource.mg && type == 'new';
  int loadedPageCount = 0;
  String type = 'hot';
  int page = 1, maxPage = 1, total = 0;
  bool loading = false;
  bool appendFailed = false;
  String? error;
  List<Map<String, dynamic>> items = [];
  int _generation = 0;
  Future<void> load({
    String? category,
    int? targetPage,
    bool append = false,
  }) async {
    final version = ++_generation;
    final retained = api.refreshingBrowse || append ? items : null;
    final previousPage = page;
    if (category != null) {
      loadedPageCount = 0;
      total = 0;
      maxPage = 1;
    }
    type = category ?? type;
    page = targetPage ?? (category != null ? 1 : page);
    loading = true;
    error = null;
    appendFailed = false;
    if (retained == null) items = [];
    notifyListeners();
    try {
      final requestedType = type, requestedPage = page;
      final result = await api.browseQuery(
        () => version == _generation,
        () => api.comments(
          session,
          song,
          type: requestedType,
          page: requestedPage,
          limit: pageSize,
        ),
      );
      if (version != _generation) return;
      if (result['comments'] is! List) throw const ApiFailure('评论数据格式不可用');
      final batch = (result['comments'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      items = append ? [...retained!, ...batch] : batch;
      if (requestedPage == 1 && api.refreshingBrowse) loadedPageCount = 0;
      if (requestedPage == loadedPageCount + 1) loadedPageCount++;
      total = int.tryParse('${result['total']}') ?? items.length;
      maxPage =
          (int.tryParse('${result['maxPage']}') ??
                  ((total + pageSize - 1) ~/ pageSize))
              .clamp(1, 1000000);
      if (batch.isEmpty) maxPage = requestedPage;
    } on ApiFailure catch (e) {
      if (version != _generation) return;
      error = e.unauthorized ? '登录已失效' : '评论加载失败：${e.message}';
      if (e.unauthorized) onUnauthorized();
    } catch (_) {
      if (version == _generation) error = '评论暂时无法加载，请重试';
    } finally {
      if (version == _generation) {
        appendFailed = error != null && append;
        if (error != null && retained != null) {
          items = retained;
          page = previousPage;
        }
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
