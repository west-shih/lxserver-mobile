import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/lx_api.dart';
import '../../core/page_window.dart';
import '../../shared/song_tile.dart';
import '../../shared/platform_filters.dart';
import '../../shared/result_pagination.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _scroll = ScrollController();
  String? _queryKey, _filledKey;
  int _visiblePage = 0;
  bool _turning = false;
  int _turnVersion = 0;

  String get _key {
    final c = widget.controller;
    return '${c.keyword}:${c.aggregate}:${c.source.name}:${c.searchRevision}:${c.pagedCollections}:${c.collectionPageSize}';
  }

  Future<void> _turn(int delta) => _turnTo(_visiblePage + delta);

  Future<void> _turnTo(int next) async {
    final c = widget.controller;
    if (_turning || c.searching || next < 0) return;
    final key = _key;
    final size = c.collectionPageSize;
    final turnVersion = ++_turnVersion;
    setState(() => _turning = true);
    try {
      if (c.hasSearchWindow) {
        await c.ensureSearchPage(next, size);
      } else {
        while (c.songs.length < (next + 1) * size && c.hasMore) {
          final before = c.songs.length;
          await c.search(c.keyword, more: true);
          if (!mounted || key != _key) return;
          if (c.searchError != null || c.songs.length <= before) break;
        }
      }
      if (!mounted || key != _key) return;
      if (c.searchPageItems(next, size).isNotEmpty) {
        setState(() => _visiblePage = next);
        if (_scroll.hasClients && _scroll.offset != 0) _scroll.jumpTo(0);
      }
    } catch (e) {
      if (mounted && key == _key) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiFailure ? e.message : '该页暂时无法加载，请重试')),
        );
      }
    } finally {
      if (mounted && turnVersion == _turnVersion) {
        setState(() => _turning = false);
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final key = _key;
    if (_queryKey != key) {
      _queryKey = key;
      _visiblePage = 0;
      _turning = false;
      _turnVersion++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    final paged = c.pagedCollections && !c.aggregate;
    final size = c.collectionPageSize;
    final loadedPages = (c.songs.length / size).ceil().clamp(1, 1000000);
    final total =
        c.searchTotal ??
        (!c.hasMore && !c.searching && c.searchError == null
            ? c.songs.length
            : null);
    final pages = total == null ? null : displayPageCount(total, size);
    final current = _visiblePage.clamp(0, (pages ?? loadedPages) - 1);
    final visible = paged ? c.searchPageItems(current, size) : c.songs;
    if (paged &&
        !_turning &&
        !c.searching &&
        c.hasMore &&
        c.searchError == null &&
        visible.length < size &&
        _filledKey != key) {
      _filledKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && key == _key) _turn(0);
      });
    }
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: c.refreshSources,
            child: CustomScrollView(
              key: const PageStorageKey('music-results-scroll'),
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: PlatformFilters(
                    scrollKey: const ValueKey('search-platforms'),
                    sources: c.availableSources,
                    selected: c.aggregate ? null : c.source,
                    onSelected: (source) => !c.aggregate && c.source == source
                        ? c.selectAggregate()
                        : c.changeSource(source),
                  ),
                ),
                if (c.keyword.isNotEmpty && c.songs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: Text(
                        '${c.aggregate || c.searchTotal == null ? '已加载 ' : ''}${c.searchTotal ?? c.songs.length} 首',
                        style: const TextStyle(fontSize: 12, color: lxMuted),
                      ),
                    ),
                  ),
                if (c.songs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: c.searching
                            ? const CircularProgressIndicator()
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    c.keyword.isEmpty
                                        ? Icons.music_note_outlined
                                        : Icons.search_off_rounded,
                                    color: lxMuted,
                                    size: 32,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    c.availableSources.isEmpty
                                        ? '暂无可用音源'
                                        : c.keyword.isEmpty
                                        ? '搜索歌曲或歌手'
                                        : c.searchError ?? '没有找到相关歌曲',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: lxMuted,
                                      height: 1.5,
                                    ),
                                  ),
                                  if (c.searchError != null)
                                    TextButton(
                                      onPressed: () => c.search(c.keyword),
                                      child: const Text('重试'),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  )
                else ...[
                  SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, index) => SongTile(
                      song: visible[index],
                      controller: c,
                      queue: c.songs,
                    ),
                  ),
                  if (c.searching ||
                      c.searchError != null ||
                      (!paged && c.hasMore))
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Column(
                          children: [
                            if (c.searchError != null)
                              Text(
                                c.searchError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: lxMuted,
                                ),
                              ),
                            if (paged && c.searchError != null && !c.searching)
                              TextButton(
                                onPressed: () =>
                                    c.search(c.keyword, more: true),
                                child: const Text('重试'),
                              ),
                            if (c.searching)
                              const CircularProgressIndicator()
                            else if (!paged && c.hasMore)
                              TextButton(
                                onPressed: () =>
                                    c.search(c.keyword, more: true),
                                child: const Text('加载更多'),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (paged && (pages != null ? pages > 1 : c.hasMore || loadedPages > 1))
          ResultPagination(
            page: current,
            pageCount: pages,
            loadedPageCount: loadedPages,
            onJump: _turning || c.searching ? null : _turnTo,
            hasMore: c.hasMore,
            onPrevious: current == 0 || _turning || c.searching
                ? null
                : () => _turn(-1),
            onNext:
                _turning ||
                    c.searching ||
                    (pages != null
                        ? current + 1 >= pages
                        : (current + 1) * size >= c.songs.length && !c.hasMore)
                ? null
                : () => _turn(1),
          ),
      ],
    );
  }
}
