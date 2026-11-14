import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../shared/song_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _scroll = ScrollController();
  String? _queryKey;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _sources() {
    final c = widget.controller;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '音源状态',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  c.availability == null
                      ? c.sourceError ?? '尚未检查'
                      : '${c.availability!.readyCount} 个就绪音源 · ${c.availableSources.length} 个平台',
                  style: const TextStyle(color: lxMuted),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: c.checkingSources ? null : c.refreshSources,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(c.checkingSources ? '检查中…' : '刷新'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final key = '${c.keyword}:${c.aggregate}:${c.source.name}';
    if (_queryKey != key) {
      _queryKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    return RefreshIndicator(
      onRefresh: () async {
        if (c.keyword.isEmpty) {
          await c.refreshSources();
        } else {
          await c.search(c.keyword);
        }
      },
      child: CustomScrollView(
        key: const PageStorageKey('music-results-scroll'),
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('search-platforms'),
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: const Text('全部'),
                              selected: c.aggregate,
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) => c.selectAggregate(),
                            ),
                          ),
                          for (final source in c.availableSources)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(source.label),
                                selected: !c.aggregate && c.source == source,
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => c.changeSource(source),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '音源状态',
                    onPressed: _sources,
                    icon: const Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: lxMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (c.keyword.isNotEmpty && c.songs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Text(
                  '${c.songs.length} 首',
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
              itemCount: c.songs.length,
              itemBuilder: (_, index) =>
                  SongTile(song: c.songs[index], controller: c, queue: c.songs),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (c.searchError != null)
                      Text(
                        c.searchError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: lxMuted),
                      ),
                    if (c.searching)
                      const CircularProgressIndicator()
                    else if (c.hasMore)
                      TextButton(
                        onPressed: () => c.search(c.keyword, more: true),
                        child: const Text('加载更多'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
