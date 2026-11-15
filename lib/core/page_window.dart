/// Keeps native pages separate from the user's display-page size.
class PageWindow<T> {
  PageWindow(this.identity);
  final String Function(T) identity;
  final Map<int, List<T>> _pages = {};
  final Map<int, bool> _more = {};
  int? total, nativeSize;
  bool get ready => nativeSize != null && _pages.isNotEmpty;

  void clear() {
    _pages.clear();
    _more.clear();
    total = nativeSize = null;
  }

  void add(
    int page,
    List<T> items, {
    int? total,
    int? size,
    required bool hasMore,
  }) {
    if (size != null && size > 0) nativeSize = size;
    if (total != null && total >= 0 && (total > 0 || items.isEmpty)) {
      this.total = total;
    }
    _pages[page] = List.of(items);
    _more[page] = hasMore;
  }

  int get contiguousPages {
    var page = 0;
    while (_pages.containsKey(page + 1)) {
      page++;
    }
    return page;
  }

  bool get hasMore => ready && total != null
      ? contiguousPages * nativeSize! < total!
      : _more[contiguousPages] ?? true;

  List<int> missing(int displayPage, int size) {
    final native = nativeSize!;
    final start = displayPage * size;
    final end = total == null || start + size < total! ? start + size : total!;
    if (end <= start) return [];
    return [
      for (
        var page = start ~/ native + 1;
        page <= (end - 1) ~/ native + 1;
        page++
      )
        if (!_pages.containsKey(page)) page,
    ];
  }

  List<T> items(int displayPage, int size) {
    final native = nativeSize!;
    final ids = <String>{};
    return [
      for (
        var offset = displayPage * size;
        offset < (displayPage + 1) * size;
        offset++
      )
        if (offset % native < (_pages[offset ~/ native + 1]?.length ?? 0))
          _pages[offset ~/ native + 1]![offset % native],
    ].where((item) => ids.add(identity(item))).toList();
  }

  List<T> get all {
    final keys = _pages.keys.toList()..sort();
    final ids = <String>{};
    return [for (final key in keys) ..._pages[key]!]
        .where((item) => ids.add(identity(item)))
        .toList();
  }
}

int? resultTotal(Object? value) {
  final parsed = num.tryParse('$value');
  return parsed != null && parsed.isFinite && parsed >= 0
      ? parsed.toInt()
      : null;
}

int displayPageCount(int total, int size) =>
    total <= 0 ? 1 : (total + size - 1) ~/ size;
