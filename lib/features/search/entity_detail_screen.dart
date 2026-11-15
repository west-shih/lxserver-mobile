import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/lx_api.dart';
import '../../shared/app_modal.dart';
import '../../shared/song_art.dart';
import '../../shared/song_tile.dart';
import '../../shared/play_all_control.dart';
import '../../shared/result_pagination.dart';
import '../../shared/playlist_edit_glyph.dart';
import '../../shared/collection_picker.dart';
import '../library/collection_edit_actions.dart';
import '../player/player_views.dart';
import '../player/quality.dart';
import 'entity_detail_controller.dart';
import 'entity_widgets.dart';
import 'music_entity.dart';

class EntityDetailScreen extends StatefulWidget {
  const EntityDetailScreen({
    super.key,
    required this.controller,
    required this.entity,
  });
  final AppController controller;
  final MusicEntity entity;
  @override
  State<EntityDetailScreen> createState() => _EntityDetailScreenState();
}

class _EntityDetailScreenState extends State<EntityDetailScreen> {
  late final EntityDetailController d;
  bool _albums = false, _expanded = false, _downloading = false;
  bool _selecting = false, _saving = false;
  final _selected = <String>{};
  List<Song> get _selectedSongs =>
      d.songs.where((s) => _selected.contains(s.id)).toList();
  bool get _busy => _downloading || _saving;
  void _finishSelection() => setState(() {
    _selecting = false;
    _selected.clear();
  });
  int _page = 0;
  final _scroll = ScrollController();
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    d = EntityDetailController(c.api, c.session!, widget.entity, c.expire);
    d.load();
    c.refreshServerFiles();
    c.addListener(_sessionChanged);
    // Refresh favorite state when arriving directly from a search result.
    c.library.load(d.session);
  }

  void _sessionChanged() {
    if (c.session != d.session) {
      d.invalidate();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    c.removeListener(_sessionChanged);
    d.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _turn(int page) {
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _download({List<Song>? selection}) async {
    final songs = List<Song>.of(selection ?? d.songs);
    if (songs.isEmpty || _busy) return;
    var quality = c.player.preferredQuality;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('下载 ${songs.length} 首歌曲'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('将下载到本机，可在个人中心查看下载列表。'),
              const SizedBox(height: 12),
              DropdownButton<String>(
                isExpanded: true,
                value: quality,
                items: AudioQuality.values
                    .map(
                      (q) =>
                          DropdownMenuItem(value: q.id, child: Text(q.label)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) update(() => quality = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('下载'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted || c.session != d.session) return;
    setState(() => _downloading = true);
    var count = 0;
    try {
      for (final song in songs) {
        if (c.session != d.session) break;
        await c.localMedia.enqueue(d.session, song, quality);
        count++;
      }
      if (mounted && c.session == d.session) _message('已将 $count 首歌曲加入本机下载列表');
    } catch (e) {
      if (mounted && c.session == d.session) {
        _message('已加入 $count 首；${e is ApiFailure ? e.message : '下载任务创建失败'}');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _message(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _collectSelected() async {
    final songs = List<Song>.of(_selectedSongs);
    if (songs.isEmpty || _busy) return;
    final target = await pickCollection(context, c, songCount: songs.length);
    if (target == null || !mounted || c.session != d.session) return;
    setState(() => _saving = true);
    try {
      await c.library.editSongs(d.session, target, addSongs: songs);
      if (mounted && c.session == d.session) {
        _message(c.library.error ?? '已收藏到「${target.name}」');
      }
    } catch (e) {
      if (mounted && c.session == d.session) {
        _message(e is ApiFailure ? e.message : '收藏失败，请刷新核对');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _playbackToolbar() => Row(
    children: [
      if (_selecting) ...[
        Checkbox(
          shape: const CircleBorder(),
          tristate: true,
          value: _selected.isEmpty
              ? false
              : _selected.length == d.songs.length
              ? true
              : null,
          onChanged: _busy
              ? null
              : (_) => setState(() {
                  if (_selected.length == d.songs.length) {
                    _selected.clear();
                  } else {
                    _selected.addAll(d.songs.map((s) => s.id));
                  }
                }),
        ),
        const Text('全选', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '已选 ${_selected.length} 首',
            style: const TextStyle(fontSize: 11, color: lxMuted),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _finishSelection,
          child: const Text('完成'),
        ),
      ] else ...[
        Expanded(
          child: PlayAllControl(
            buttonKey: const ValueKey('entity-play'),
            count: d.songs.length,
            loadedOnly: d.entity.artist,
            showLoadedLabel: false,
            onPlay: d.loading || d.songs.isEmpty
                ? null
                : () => c.player.play(d.session, d.songs.first, songs: d.songs),
          ),
        ),
        IconButton(
          tooltip: '选择歌曲',
          icon: const PlaylistEditGlyph(),
          onPressed: d.loading || d.songs.isEmpty
              ? null
              : () => setState(() {
                  _selecting = true;
                  _selected.clear();
                }),
        ),
      ],
    ],
  );

  Widget _stat(IconData icon, Color color, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: lxMuted)),
      ],
    ),
  );

  Widget _hero() {
    final e = d.entity;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: e.artist
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              if (e.artist)
                ClipOval(
                  child: SongArt(
                    url: e.image,
                    size: 80,
                    placeholderIcon: Icons.person_outline_rounded,
                    placeholderColor: Colors.white,
                    placeholderBackground: const Color(0xffe2e6e4),
                  ),
                )
              else
                SongArt(url: e.image, size: 102),
              const SizedBox(width: 12),
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: e.artist ? 80 : 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: e.artist ? 44 : 0,
                        ),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                e.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: e.artist && e.alias.isNotEmpty ? 0 : 4),
                      if (e.artist && e.alias.isNotEmpty) ...[
                        Text(
                          e.alias,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            color: lxMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      if (e.artist)
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 20),
                          child: Wrap(
                            spacing: 14,
                            runSpacing: 7,
                            children: [
                              if (e.number('albumSize') != null)
                                _stat(
                                  Icons.album_rounded,
                                  const Color(0xff3984ed),
                                  '${e.number('albumSize')} 专辑',
                                ),
                              if (e.number('musicSize') != null)
                                _stat(
                                  Icons.music_note_rounded,
                                  lxGreen,
                                  '${e.number('musicSize')} 歌曲',
                                ),
                            ],
                          ),
                        )
                      else if (e.singer.isNotEmpty)
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                            minimumSize: const Size(44, 36),
                          ),
                          onPressed: !e.canOpenArtist
                              ? null
                              : () => openEntity(
                                  context,
                                  c,
                                  MusicEntity(
                                    {'id': e.artistId, 'name': e.singer},
                                    e.source,
                                    true,
                                  ),
                                ),
                          child: Text(e.singer),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (!e.artist && e.date.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${e.date} 发行',
                style: const TextStyle(color: lxMuted, fontSize: 11),
              ),
            ),
          if (e.description.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 4),
              decoration: BoxDecoration(
                color: const Color(0xfff0f2f1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.description,
                    maxLines: _expanded ? null : 3,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xff66766e),
                      height: 1.8,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? '收起' : '展开'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([d, c.library, c]),
    builder: (context, _) {
      if (c.session != d.session) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('会话已改变，请返回后重新打开')),
        );
      }
      final e = d.entity;
      final saved = c.library.isEntityFavorite(e.favorite, e.artist);
      final size = c.collectionPageSize;
      final pages = (d.songs.length / size).ceil().clamp(1, 1000000);
      final current = _page.clamp(0, pages - 1);
      final paged = c.pagedCollections && !_albums;
      final visible = paged
          ? d.songs.skip(current * size).take(size).toList()
          : d.songs;
      return PopScope(
        canPop: !_selecting && !_busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _selecting && !_busy) _finishSelection();
        },
        child: Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                key: const ValueKey('entity-favorite'),
                tooltip: saved
                    ? (e.artist ? '取消收藏歌手' : '取消收藏专辑')
                    : (e.artist ? '收藏歌手' : '收藏专辑'),
                onPressed: c.library.mutating || _busy
                    ? null
                    : () => toggleEntity(context, c, e),
                icon: Icon(
                  saved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: saved ? const Color(0xffef4444) : lxMuted,
                ),
              ),
              const SizedBox(width: 8),
            ],
            titleSpacing: 0,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.artist ? '歌手详情' : '专辑详情',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 9),
                Transform.translate(
                  offset: Offset(0, MediaQuery.textScalerOf(context).scale(2)),
                  child: EntityBadge(source: e.source),
                ),
              ],
            ),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      SliverToBoxAdapter(child: _hero()),
                      if (d.infoError != null)
                        SliverToBoxAdapter(
                          child: _failure(d.infoError!, () => d.load()),
                        ),
                      SliverPersistentHeader(
                        key: const ValueKey('entity-tabs-header'),
                        pinned: true,
                        delegate: _EntityTabs(
                          e.artist,
                          _albums,
                          d.order,
                          (albums) {
                            if (_busy) return;
                            setState(() {
                              _albums = albums;
                              _page = 0;
                              _selected.clear();
                              _selecting = false;
                            });
                            if (albums && d.albums.isEmpty) d.loadAlbums();
                          },
                          (sort) {
                            if (_busy) return;
                            _page = 0;
                            _selected.clear();
                            _selecting = false;
                            d.load(sort: sort);
                          },
                        ),
                      ),
                      if (_albums) ...[
                        EntityGrid(controller: c, items: d.albums),
                        if (d.albumError != null)
                          SliverToBoxAdapter(
                            child: _failure(
                              d.albumError!,
                              () => d.loadAlbums(more: d.albums.isNotEmpty),
                            ),
                          ),
                        if (d.loadingAlbums)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                        if (!d.loadingAlbums &&
                            d.albumError == null &&
                            d.albums.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('暂无专辑')),
                            ),
                          ),
                        if (d.moreAlbums &&
                            !d.loadingAlbums &&
                            d.albumError == null)
                          SliverToBoxAdapter(
                            child: TextButton(
                              onPressed: () => d.loadAlbums(more: true),
                              child: const Text('加载更多专辑'),
                            ),
                          ),
                      ] else ...[
                        SliverPersistentHeader(
                          key: const ValueKey('entity-play-header'),
                          pinned: true,
                          delegate: _EntityPlaybackToolbar(
                            child: _playbackToolbar(),
                          ),
                        ),
                        if (d.loading)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                        if (d.error != null)
                          SliverToBoxAdapter(
                            child: _failure(d.error!, () => d.load()),
                          ),
                        if (!d.loading && d.error == null && d.songs.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('暂无歌曲')),
                            ),
                          ),
                        SliverList.builder(
                          itemCount: visible.length,
                          itemBuilder: (_, i) => SongTile(
                            song: visible[i],
                            controller: c,
                            queue: d.songs,
                            selected: _selecting
                                ? _selected.contains(visible[i].id)
                                : null,
                            selectionEnabled: !_busy,
                            onSelect: !_selecting
                                ? null
                                : () => setState(() {
                                    final id = visible[i].id;
                                    if (!_selected.add(id)) {
                                      _selected.remove(id);
                                    }
                                  }),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (paged && d.songs.isNotEmpty)
                  ResultPagination(
                    page: current,
                    pageCount: pages,
                    hasMore: current + 1 < pages,
                    onPrevious: current > 0 ? () => _turn(current - 1) : null,
                    onNext: current + 1 < pages
                        ? () => _turn(current + 1)
                        : null,
                    onJump: _turn,
                  ),
                if (_selecting)
                  CollectionEditActions(
                    showDelete: false,
                    onNext: _busy || _selected.isEmpty
                        ? null
                        : () {
                            final count = c.player.enqueueNext(
                              d.session,
                              _selectedSongs,
                            );
                            _message('已将 $count 首歌曲排为下一首播放');
                          },
                    onCollect: _busy || _selected.isEmpty
                        ? null
                        : _collectSelected,
                    onDownload: _busy || _selected.isEmpty
                        ? null
                        : () => _download(selection: _selectedSongs),
                  )
                else
                  MiniPlayer(player: c.player, controller: c, compact: paged),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _failure(String message, VoidCallback retry) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        Text(message, style: const TextStyle(color: lxMuted, fontSize: 12)),
        TextButton(onPressed: retry, child: const Text('重试')),
      ],
    ),
  );
}

class _EntityTabs extends SliverPersistentHeaderDelegate {
  _EntityTabs(this.artist, this.albums, this.order, this.select, this.sort);
  final bool artist, albums;
  final String order;
  final ValueChanged<bool> select;
  final ValueChanged<String> sort;
  @override
  double get minExtent => 44;
  @override
  double get maxExtent => 44;
  @override
  bool shouldRebuild(covariant _EntityTabs oldDelegate) => true;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: lxCanvas,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xffe5ece7))),
      ),
      child: Row(
        children: [
          _tab('歌曲', !albums, () => select(false)),
          if (artist) ...[
            const SizedBox(width: 18),
            _tab('专辑', albums, () => select(true)),
          ],
          const Spacer(),
          if (artist && !albums)
            DropdownButton<String>(
              value: order,
              underline: const SizedBox.shrink(),
              style: const TextStyle(fontSize: 12, color: lxInk),
              items: const [
                DropdownMenuItem(value: 'hot', child: Text('热门')),
                DropdownMenuItem(value: 'time', child: Text('最新')),
              ],
              onChanged: (v) {
                if (v != null && v != order) sort(v);
              },
            ),
        ],
      ),
    ),
  );
  Widget _tab(String title, bool active, VoidCallback action) => InkWell(
    onTap: action,
    splashFactory: NoSplash.splashFactory,
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        border: active
            ? const Border(bottom: BorderSide(color: lxGreen, width: 3))
            : null,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    ),
  );
}

class _EntityPlaybackToolbar extends SliverPersistentHeaderDelegate {
  _EntityPlaybackToolbar({required this.child});
  final Widget child;
  @override
  double get minExtent => 62;
  @override
  double get maxExtent => 62;
  @override
  bool shouldRebuild(covariant _EntityPlaybackToolbar oldDelegate) => true;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: lxCanvas,
    surfaceTintColor: Colors.transparent,
    child: Container(
      key: const ValueKey('entity-playback-toolbar'),
      height: 62,
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 8),
      decoration: const BoxDecoration(
        color: lxCanvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: child,
    ),
  );
}
