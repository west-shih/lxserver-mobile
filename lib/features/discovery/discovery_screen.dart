import '../../app/browse_navigation.dart';
import '../../shared/remembered_page.dart';

import 'package:flutter/material.dart';

import '../../shared/app_modal.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/lx_api.dart';
import '../../core/page_window.dart';
import '../../shared/song_art.dart';
import '../../shared/music_badge.dart';
import '../../shared/platform_filters.dart';
import '../../shared/result_pagination.dart';
import '../library/collection_screen.dart';
import '../library/library_controller.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen>
    with RememberedPage<DiscoveryScreen> {
  @override
  AppController get browseApp => widget.controller;
  @override
  String get browseKey => 'home.discovery';
  @override
  ScrollController get browseScroll => _scroll;
  @override
  Map<String, dynamic> saveView() => {
    'page': _visiblePage,
    'queryKey': _queryKey,
  };
  @override
  void restoreView(Map<String, dynamic> value) {
    _visiblePage = value['page'] is int
        ? (value['page'] as int).clamp(0, 1000000)
        : 0;
    _queryKey = value['queryKey'] is String ? value['queryKey'] as String : '';
  }

  final _scroll = ScrollController();
  String? _queryKey, _filledKey;
  int _visiblePage = 0;
  bool _turning = false;
  int _turnVersion = 0;

  String get _key {
    final c = widget.controller;
    final d = c.discovery;
    return '${d.aggregate}:${d.source.name}:${d.tag}:${d.sort}:${d.keyword}:${d.resultRevision}:${c.pagedCollections}:${c.collectionPageSize}';
  }

  Future<void> _turn(int delta) => _turnTo(_visiblePage + delta);

  Future<void> _turnTo(int next) async {
    final c = widget.controller;
    final d = c.discovery;
    final session = c.session;
    if (_turning || d.loading || session == null || next < 0) return;
    final key = _key;
    final size = c.collectionPageSize;
    final turnVersion = ++_turnVersion;
    setState(() => _turning = true);
    try {
      if (d.hasWindow) {
        await d.ensurePage(session, next, size);
      } else {
        while (d.playlists.length < (next + 1) * size && d.hasMore) {
          final before = d.playlists.length;
          await d.load(session, more: true);
          if (!mounted || key != _key) return;
          if (d.error != null || d.playlists.length <= before) break;
        }
      }
      if (!mounted || key != _key) return;
      if (d.pageItems(next, size).isNotEmpty) {
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

  void _load({bool more = false, bool categories = false}) {
    final c = widget.controller;
    if (c.session != null) {
      c.discovery.load(c.session!, more: more, categories: categories);
    }
  }

  void _tags() {
    final d = widget.controller.discovery;
    showAppSheet<void>(
      context: context,
      title: '选择分类',
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: d.groups.isEmpty
              ? 240
              : MediaQuery.sizeOf(context).height * .65,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
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
    listenable: Listenable.merge([
      widget.controller,
      widget.controller.discovery,
    ]),
    builder: (context, _) {
      final c = widget.controller;
      final d = c.discovery;
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
      final paged = c.pagedCollections && !d.aggregate;
      final size = c.collectionPageSize;
      final loadedPages = (d.playlists.length / size).ceil().clamp(1, 1000000);
      final total =
          d.total ??
          (!d.hasMore && !d.loading && d.error == null
              ? d.playlists.length
              : null);
      final pages = total == null ? null : displayPageCount(total, size);
      final current = _visiblePage.clamp(0, (pages ?? loadedPages) - 1);
      final visible = paged ? d.pageItems(current, size) : d.playlists;
      if (paged &&
          !_turning &&
          !d.loading &&
          d.hasMore &&
          d.error == null &&
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
              onRefresh: () => c.api.refreshBrowse(() async {
                await c.refreshSources(reloadResults: false);
                if (c.session != null) {
                  await d.load(c.session!, categories: !d.aggregate);
                }
              }),
              child: CustomScrollView(
                key: const PageStorageKey('playlist-results-scroll'),
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: PlatformFilters(
                      sources: c.availableSources,
                      selected: d.aggregate ? null : d.source,
                      onSelected: c.selectDiscoverySource,
                    ),
                  ),
                  if (!d.aggregate && d.keyword.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: _tags,
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    d.tagName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                            if (d.sorts.length == 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  '${d.sorts.single['name']}',
                                  style: const TextStyle(
                                    color: lxInk,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            if (d.sorts.length > 1)
                              DropdownButton<String>(
                                borderRadius: BorderRadius.circular(12),
                                dropdownColor: Colors.white,
                                isDense: true,
                                value:
                                    d.sorts.any((v) => '${v['id']}' == d.sort)
                                    ? d.sort
                                    : null,
                                underline: const SizedBox(),
                                style: const TextStyle(
                                  color: lxInk,
                                  fontSize: 13,
                                ),
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
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final playlist = visible[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 5,
                          ),
                          leading: SongArt(url: playlist.image, size: 56),
                          title: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                MusicBadge(
                                  playlist.source.label,
                                  tone: MusicBadge.source(playlist.source),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    [
                                          playlist.author,
                                          if (playlist.count.isNotEmpty)
                                            '${playlist.count} 次播放',
                                        ]
                                        .where((value) => value.isNotEmpty)
                                        .join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: lxMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                if (playlist.metadata.date.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 110,
                                    ),
                                    child: Text(
                                      playlist.metadata.date,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        color: lxMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          onTap: () {
                            final session = c.session;
                            if (session == null) return;
                            Navigator.push(
                              context,
                              browseRoute(
                                CollectionScreen(
                                  controller: c,
                                  collection: MusicCollection(
                                    playlist.id,
                                    playlist.name,
                                    [],
                                    image: playlist.image,
                                    source: playlist.source,
                                    metadata: playlist.metadata,
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
                    if (d.loading || d.error != null || (!paged && d.hasMore))
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Column(
                            children: [
                              if (d.error != null)
                                Text(
                                  d.error!,
                                  style: const TextStyle(
                                    color: lxMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              if (paged && d.error != null && !d.loading)
                                TextButton(
                                  onPressed: () => _load(more: true),
                                  child: const Text('重试'),
                                ),
                              if (d.loading)
                                const CircularProgressIndicator()
                              else if (!paged && (d.hasMore || d.error != null))
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
            ),
          ),
          if (paged &&
              (pages != null ? pages > 1 : d.hasMore || loadedPages > 1))
            ResultPagination(
              page: current,
              pageCount: pages,
              loadedPageCount: loadedPages,
              onJump: _turning || d.loading ? null : _turnTo,
              hasMore: d.hasMore,
              onPrevious: current == 0 || _turning || d.loading
                  ? null
                  : () => _turn(-1),
              onNext:
                  _turning ||
                      d.loading ||
                      (pages != null
                          ? current + 1 >= pages
                          : (current + 1) * size >= d.playlists.length &&
                                !d.hasMore)
                  ? null
                  : () => _turn(1),
            ),
        ],
      );
    },
  );
}
