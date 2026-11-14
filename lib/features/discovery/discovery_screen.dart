import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../shared/song_art.dart';
import '../library/collection_screen.dart';
import '../library/library_controller.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _scroll = ScrollController();
  String? _queryKey;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _load({bool more = false, bool categories = false}) {
    final c = widget.controller;
    if (c.session != null) {
      c.discovery.load(c.session!, more: more, categories: categories);
    }
  }

  void _tags() {
    final d = widget.controller.discovery;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              const Text(
                '选择分类',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: ChoiceChip(
                  label: const Text('全部分类'),
                  selected: d.tag.isEmpty,
                  onSelected: (_) {
                    Navigator.pop(context);
                    d.tag = '';
                    d.tagName = '全部分类';
                    _load();
                  },
                ),
              ),
              for (final group in d.groups) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '${group['name'] ?? ''}',
                    style: const TextStyle(
                      color: lxMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final tag
                        in (group['list'] as List? ?? []).whereType<Map>())
                      ChoiceChip(
                        label: Text('${tag['name']}'),
                        selected: d.tag == '${tag['id']}',
                        onSelected: (_) {
                          Navigator.pop(context);
                          d.tag = '${tag['id']}';
                          d.tagName = '${tag['name']}';
                          _load();
                        },
                      ),
                  ],
                ),
              ],
              if (d.groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Text('当前平台没有返回更多分类', style: TextStyle(color: lxMuted)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller.discovery,
    builder: (context, _) {
      final c = widget.controller;
      final d = c.discovery;
      final key = '${d.source.name}:${d.tag}:${d.sort}:${d.keyword}';
      if (_queryKey != key) {
        _queryKey = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
        });
      }
      return RefreshIndicator(
        onRefresh: () async {
          if (c.session != null) await d.load(c.session!, categories: true);
        },
        child: CustomScrollView(
          key: const PageStorageKey('playlist-results-scroll'),
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
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final source in c.availableSources)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(source.label),
                                  selected: d.source == source,
                                  showCheckmark: false,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) {
                                    if (c.session != null) {
                                      d.changeSource(c.session!, source);
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新歌单',
                      onPressed: d.loading
                          ? null
                          : () => _load(categories: true),
                      icon: const Icon(
                        Icons.refresh_rounded,
                        size: 20,
                        color: lxMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (d.keyword.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _tags,
                            icon: const Icon(Icons.tune_rounded, size: 16),
                            label: Text(
                              d.tagName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      if (d.sorts.isNotEmpty)
                        DropdownButton<String>(
                          value: d.sorts.any((v) => '${v['id']}' == d.sort)
                              ? d.sort
                              : null,
                          underline: const SizedBox(),
                          style: const TextStyle(color: lxInk, fontSize: 13),
                          items: d.sorts
                              .map(
                                (v) => DropdownMenuItem(
                                  value: '${v['id']}',
                                  child: Text('${v['name']}'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              d.sort = v;
                              _load();
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
            if (c.availableSources.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('暂无可用音源', style: TextStyle(color: lxMuted)),
                ),
              )
            else if (d.playlists.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: d.loading
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                d.error ?? '暂无歌单',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: lxMuted),
                              ),
                              if (d.error != null)
                                TextButton(
                                  onPressed: () =>
                                      _load(categories: d.sorts.isEmpty),
                                  child: const Text('重试'),
                                ),
                            ],
                          ),
                  ),
                ),
              )
            else ...[
              SliverList.builder(
                itemCount: d.playlists.length,
                itemBuilder: (context, i) {
                  final playlist = d.playlists[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    leading: SongArt(url: playlist.image, size: 56),
                    title: Text(
                      playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      [
                        playlist.author,
                        if (playlist.count.isNotEmpty) '${playlist.count} 次播放',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: lxMuted, fontSize: 11),
                    ),
                    onTap: () {
                      final session = c.session;
                      if (session == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CollectionScreen(
                            controller: c,
                            collection: MusicCollection(
                              playlist.id,
                              playlist.name,
                              [],
                              image: playlist.image,
                            ),
                            fetchPage: (page) =>
                                d.detail(session, playlist, page),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (d.error != null)
                        Text(
                          d.error!,
                          style: const TextStyle(color: lxMuted, fontSize: 12),
                        ),
                      if (d.loading)
                        const CircularProgressIndicator()
                      else if (d.hasMore || d.error != null)
                        TextButton(
                          onPressed: () => _load(more: true),
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
    },
  );
}
