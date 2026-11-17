import 'package:flutter/foundation.dart';

import '../../core/lx_api.dart';

class CommentsController extends ChangeNotifier {
  CommentsController(this.api, this.session, this.song, this.onUnauthorized);
  final LxApi api;
  final Session session;
  final Song song;
  final VoidCallback onUnauthorized;
  String type = 'hot';
  int page = 1, maxPage = 1, total = 0;
  bool loading = false;
  String? error;
  List<Map<String, dynamic>> items = [];
  int _generation = 0;
  Future<void> load({String? category, int? targetPage}) async {
    final version = ++_generation;
    final retained = api.refreshingBrowse ? List.of(items) : null;
    type = category ?? type;
    page = targetPage ?? (category != null ? 1 : page);
    loading = true;
    error = null;
    items = [];
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
        ),
      );
      if (version != _generation) return;
      if (result['comments'] is! List) throw const ApiFailure('评论数据格式不可用');
      items = (result['comments'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      total = int.tryParse('${result['total']}') ?? items.length;
      maxPage = (int.tryParse('${result['maxPage']}') ?? ((total + 19) ~/ 20))
          .clamp(1, 1000000);
    } on ApiFailure catch (e) {
      if (version != _generation) return;
      error = e.unauthorized ? '登录已失效' : '评论暂时无法加载，请重试';
      if (e.unauthorized) onUnauthorized();
    } catch (_) {
      if (version == _generation) error = '评论暂时无法加载，请重试';
    } finally {
      if (version == _generation) {
        if (error != null && retained != null) items = retained;
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
