import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../shared/platform_filters.dart';
import '../../shared/result_pagination.dart';
import 'entity_widgets.dart';
import 'music_entity.dart';

class EntitySearchScreen extends StatefulWidget {
  const EntitySearchScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<EntitySearchScreen> createState() => _EntitySearchScreenState();
}

class _EntitySearchScreenState extends State<EntitySearchScreen> {
  int _page = 0;
  String _key = '';
  String? _fillKey;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _turn(int page) async {
    final c = widget.controller, d = widget.controller.entitySearch;
    final session = c.session;
    if (session == null || d.loading || page < 0) return;
    final key = _key;
    final size = c.collectionPageSize;
    if (d.hasWindow) {
      await d.ensurePage(session, page, size);
      if (!mounted || key != _key || size != c.collectionPageSize) return;
    } else {
      while (d.items.length < (page + 1) * size && d.hasMore) {
        final before = d.items.length;
        await d.search(session, d.keyword, more: true);
        if (!mounted || key != _key || size != c.collectionPageSize) return;
        if (d.error != null || d.items.length <= before) break;
      }
    }
    if (mounted && d.pageItems(page, size).isNotEmpty && d.error == null) {
      setState(() => _page = page);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.controller,
      widget.controller.library,
    ]),
    builder: (context, _) {
      final c = widget.controller, d = c.entitySearch;
      final key =
          '${d.kind}:${d.source}:${d.keyword}:${d.revision}:${c.collectionPageSize}:${c.pagedCollections}';
      if (key != _key) {
        _key = key;
        _page = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients && key == _key) _scroll.jumpTo(0);
        });
      }
      final size = c.collectionPageSize;
      final paged = c.pagedCollections;
      final loaded = (d.items.length / size).ceil().clamp(1, 1000000);
      final count = d.total == null
          ? loaded
          : (d.total! / size).ceil().clamp(1, 1000000);
      final current = _page.clamp(0, count - 1);
      final visible = paged ? d.pageItems(current, size) : d.items;
      if (paged &&
          d.items.isNotEmpty &&
          d.items.length < size &&
          d.hasMore &&
          !d.loading &&
          d.error == null &&
          _fillKey != key) {
        _fillKey = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && key == _key) _turn(0);
        });
      }
      final session = c.session;
      return Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await c.refreshSources(reloadResults: false);
                if (c.session == session &&
                    session != null &&
                    c.entitySources.isNotEmpty) {
                  await d.search(session, d.keyword);
                }
              },
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: PlatformFilters(
                      sources: c.entitySources,
                      selected: d.source,
                      onSelected: (source) {
                        if (session != null && source != d.source) {
                          d.select(session, d.kind, source, d.keyword);
                        }
                      },
                    ),
                  ),
                  if (c.sourceError != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          c.sourceError!,
                          style: const TextStyle(fontSize: 11, color: lxMuted),
                        ),
                      ),
                    ),
                  if (c.entitySources.isEmpty ||
                      (d.items.isEmpty && !d.loading && d.error == null))
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.search_rounded,
                                size: 32,
                                color: lxMuted,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                c.entitySources.isEmpty
                                    ? '暂无支持此搜索类型的可用平台'
                                    : d.keyword.isEmpty
                                    ? '搜索${d.kind.label}'
                                    : '没有找到相关${d.kind.label}',
                                style: const TextStyle(color: lxMuted),
                              ),
                              if (c.entitySources.isEmpty)
                                TextButton(
                                  onPressed: () => c.selectSearchKind(
                                    // Return to the five-platform song search.
                                    SearchKind.song,
                                    d.keyword,
                                  ),
                                  child: const Text('搜索歌曲'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (d.items.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                        child: Text(
                          '已加载 ${d.items.length} ${d.kind == SearchKind.artist ? '位歌手' : '张专辑'}',
                          style: const TextStyle(color: lxMuted, fontSize: 11),
                        ),
                      ),
                    ),
                    EntityGrid(controller: c, items: visible),
                  ],
                  if (d.error != null)
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          Text(
                            d.error!,
                            style: const TextStyle(color: lxMuted),
                          ),
                          TextButton(
                            onPressed: session == null
                                ? null
                                : () => d.search(
                                    session,
                                    d.keyword,
                                    more: d.page > 0,
                                  ),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  if (d.loading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  if (!paged && d.hasMore && !d.loading && d.error == null)
                    SliverToBoxAdapter(
                      child: TextButton(
                        onPressed: session == null
                            ? null
                            : () => d.search(session, d.keyword, more: true),
                        child: const Text('加载更多'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (paged && d.items.isNotEmpty)
            ResultPagination(
              page: current,
              pageCount: d.total == null
                  ? (d.hasMore ? null : loaded)
                  : (d.total! / size).ceil().clamp(1, 1000000),
              loadedPageCount: loaded,
              hasMore: d.hasMore || current + 1 < loaded,
              onPrevious: !d.loading && current > 0
                  ? () => _turn(current - 1)
                  : null,
              onNext:
                  !d.loading &&
                      (d.hasWindow
                          ? current + 1 < count
                          : d.hasMore || current + 1 < loaded)
                  ? () => _turn(current + 1)
                  : null,
              onJump: d.loading ? null : _turn,
            ),
        ],
      );
    },
  );
}
