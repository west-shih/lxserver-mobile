import '../../shared/compact_search.dart';

import 'package:flutter/material.dart';

import '../../shared/remembered_page.dart';

import '../../shared/app_modal.dart';
import '../../shared/collection_picker.dart';

import 'package:flutter/foundation.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/lx_api.dart';
import '../../core/page_window.dart';
import '../../shared/scrolling_title.dart';
import '../../shared/song_tile.dart';
import '../../shared/play_all_control.dart';
import '../../shared/playlist_edit_glyph.dart';
import '../../shared/result_pagination.dart';
import '../discovery/discovery_controller.dart';
import '../player/player_views.dart';
import '../player/quality.dart';
import 'library_controller.dart';
import 'collection_actions.dart';
import 'collection_metadata.dart';
import 'collection_header.dart';
import 'collection_edit_actions.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key,
    required this.controller,
    required this.collection,
    this.fetchPage,
    this.editable = false,
  });
  final AppController controller;
  final bool editable;
  final MusicCollection collection;
  final Future<SongBatch> Function(int)? fetchPage;
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen>
    with RememberedPage<CollectionScreen> {
  @override
  AppController get browseApp => widget.controller;
  @override
  String get browseKey =>
      'detail.collection:${widget.editable}:${widget.collection.source?.name}:${widget.collection.id}';
  @override
  ScrollController get browseScroll => _scroll;
  @override
  Map<String, dynamic> saveView() => {
    'page': _visiblePage,
    'nativePage': _page,
    'more': _more,
    'total': _reportedTotal,
    'songs': (widget.editable ? _collection.songs : _songs)
        .map((s) => s.raw)
        .toList(),
    'image': _remoteImage,
    'query': _search.text,
    'searching': _searching,
    'metadata': {
      'author': _metadata.author,
      'desc': _metadata.description,
      'play_count': _metadata.playCount,
      'time': _metadata.date,
    },
  };
  @override
  void restoreView(Map<String, dynamic> value) {
    if (!widget.editable && value['songs'] is List) {
      _songs = parseSongs(value['songs']);
    }
    _visiblePage = resultTotal(value['page']) ?? 0;
    _page = resultTotal(value['nativePage']) ?? 0;
    _more = value.containsKey('more')
        ? value['more'] == true
        : widget.fetchPage != null;
    _reportedTotal = resultTotal(value['total']);
    _remoteImage = '${value['image'] ?? ''}';
    if (value['metadata'] is Map) {
      _metadata = _metadata.merge(
        CollectionMetadata.fromJson(value['metadata']),
      );
    }
    _search.text = '${value['query'] ?? ''}';
    _searching = value['searching'] == true;
  }

  late List<Song> _songs;
  late CollectionMetadata _metadata;
  String _remoteImage = '';
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _heroKey = GlobalKey();
  final _selected = <String>{};
  List<String> _baseOrder = [];
  bool _dirtyOrder = false;
  bool _dragging = false;
  int _visiblePage = 0;
  int? _reportedTotal;
  bool _pageTurning = false;
  int _page = 0;
  bool _loading = false;
  bool _more = false;
  bool _collapsed = false;
  bool _searching = false;
  bool _selecting = false;
  bool _saving = false;
  String? _error;
  int get _pageSize => widget.controller.collectionPageSize;
  MusicCollection get _collection => widget.editable
      ? widget.controller.library.collections
                .where((v) => v.id == widget.collection.id)
                .firstOrNull ??
            widget.collection
      : widget.collection;
  String get _image => widget.editable
      ? _collection.cover
      : _remoteImage.isNotEmpty
      ? _remoteImage
      : _collection.cover;
  List<Song> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _songs
        .where(
          (s) =>
              '${s.name} ${s.singer} ${s.album}'.toLowerCase().contains(query),
        )
        .toList();
  }

  List<Song> get _selectedSongs =>
      _songs.where((s) => _selected.contains(s.id)).toList();
  @override
  void initState() {
    _songs = [...widget.collection.songs];
    _metadata = widget.collection.metadata;
    super.initState();
    _scroll.addListener(_onScroll);
    widget.controller.refreshServerFiles();
    if (_more && _page == 0) _load().then((_) => revalidateView());
  }

  bool _checkingExpiry = false;
  @override
  Future<void> revalidateView() async {
    final c = widget.controller;
    if (!mounted ||
        widget.editable ||
        widget.fetchPage == null ||
        c.offlineMode ||
        _checkingExpiry ||
        _loading ||
        _saving ||
        _selecting ||
        (_page == 0 && _error != null) ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _checkingExpiry = true;
    final session = c.session;
    final oldPage = _page, oldVisible = _visiblePage;
    final oldSongs = _songs;
    SongBatch? result;
    bool current() =>
        mounted &&
        session == c.session &&
        !_loading &&
        !_saving &&
        !_selecting &&
        _page == oldPage &&
        _visiblePage == oldVisible &&
        identical(oldSongs, _songs);
    try {
      final changed = await c.api.revalidateBrowse(() async {
        result = await widget.fetchPage!(1);
      }, current: current);
      if (!changed || !current()) return;
      final fresh = result!;
      setState(() {
        _songs = fresh.songs;
        _page = 1;
        _visiblePage = 0;
        _more = fresh.hasMore;
        _reportedTotal = fresh.total;
        _metadata = _metadata.merge(fresh.metadata);
        _remoteImage = firstImage([fresh.image, _remoteImage]);
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } on ApiFailure catch (e) {
      if (e.unauthorized && session == c.session) c.expire();
    } finally {
      _checkingExpiry = false;
    }
  }

  void _onScroll() {
    final render = _heroKey.currentContext?.findRenderObject();
    final extent = render is RenderBox && render.hasSize
        ? render.size.height
        : 140.0;
    final collapsed = !_searching && _scroll.offset > extent - 8;
    if (collapsed != _collapsed && mounted) {
      setState(() => _collapsed = collapsed);
    }
  }

  Future<void> _load() async {
    if (_loading || widget.fetchPage == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = _page + 1;
      final result = await widget.fetchPage!(page);
      if (!mounted) return;
      final ids = _songs.map((s) => s.id).toSet();
      final fresh = result.songs.where((s) => ids.add(s.id)).toList();
      setState(() {
        _songs = [..._songs, ...fresh];
        _page = page;
        _more = result.hasMore && fresh.isNotEmpty;
        _reportedTotal = _more ? result.total ?? _reportedTotal : _songs.length;
        _metadata = _metadata.merge(result.metadata);
        _remoteImage = firstImage([result.image, _remoteImage]);
      });
    } on ApiFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.unauthorized) widget.controller.expire();
    } catch (_) {
      if (mounted) setState(() => _error = '歌曲列表暂时无法加载');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_loading || _saving || _selecting || widget.fetchPage == null) return;
    final c = widget.controller;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await c.api.refreshBrowse(() => widget.fetchPage!(1));
      if (!mounted) return;
      setState(() {
        _songs = result.songs;
        _page = 1;
        _visiblePage = 0;
        _more = result.hasMore;
        _reportedTotal = result.total;
        _metadata = _metadata.merge(result.metadata);
        _remoteImage = firstImage([result.image, _remoteImage]);
      });
    } on ApiFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.unauthorized) c.expire();
    } catch (_) {
      if (mounted) setState(() => _error = '刷新失败，已保留原有内容');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _turn(int delta) async {
    await _turnTo(_visiblePage + delta);
  }

  Future<void> _turnTo(int next) async {
    if (_loading || _pageTurning || next < 0) return;
    final size = _pageSize;
    final query = _search.text.trim();
    setState(() => _pageTurning = true);
    try {
      while (query.isEmpty && _songs.length < (next + 1) * size && _more) {
        await _load();
        if (!mounted || size != _pageSize || query != _search.text.trim()) {
          return;
        }
        if (_error != null) break;
      }
      if (!mounted || size != _pageSize || query != _search.text.trim()) return;
      if (next * size >= _filtered.length) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error ?? '该页暂无结果，请尝试前面的页码')));
        return;
      }
      setState(() => _visiblePage = next);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } finally {
      if (mounted) setState(() => _pageTurning = false);
    }
  }

  void _searchMode(bool value) {
    _searchFocus.unfocus();
    setState(() {
      _searching = value;
      _search.clear();
      _visiblePage = 0;
      _collapsed = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  void _changed(String action) {
    if (action == 'delete') {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _songs = [..._collection.songs];
      _visiblePage = 0;
      _selected.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _selectionMode(bool value) {
    setState(() {
      _selecting = value;
      if (value) {
        _baseOrder = _songs.map((song) => song.id).toList();
        _dirtyOrder = false;
      } else {
        _selected.clear();
        _dirtyOrder = false;
      }
    });
  }

  bool get _canReorder =>
      widget.editable &&
      !_saving &&
      widget.controller.session != null &&
      _search.text.trim().isEmpty &&
      _songs.map((s) => s.id).toSet().length == _songs.length;

  void _reorder(int from, int to) {
    if (!_canReorder || from == to) return;
    final start = widget.controller.pagedCollections
        ? _visiblePage * _pageSize
        : 0;
    setState(() {
      final song = _songs.removeAt(start + from);
      _songs.insert(start + to, song);
      _dirtyOrder = !listEquals(_baseOrder, _songs.map((s) => s.id).toList());
    });
  }

  void _acceptEdit(List<Song> songs) {
    setState(() {
      _songs = [...songs];
      _baseOrder = songs.map((s) => s.id).toList();
      _dirtyOrder = false;
      _selected.retainAll(_baseOrder);
      _visiblePage = _visiblePage.clamp(
        0,
        ((songs.length / _pageSize).ceil() - 1).clamp(0, 1000000),
      );
    });
  }

  void _editFailure(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e is ApiFailure ? e.message : '歌单未能保存，请重试'),
        action: widget.editable
            ? SnackBarAction(
                label: '重新加载',
                onPressed: () async {
                  final c = widget.controller;
                  final session = c.session;
                  if (session == null) return;
                  await c.library.load(session);
                  if (!mounted || c.session != session) return;
                  if (c.library.error == null) {
                    _selected.clear();
                    _acceptEdit(_collection.songs);
                  }
                },
              )
            : null,
      ),
    );
  }

  Future<void> _finishEditing({bool fromBack = false}) async {
    if (_saving || _dragging) return;
    if (!_dirtyOrder) {
      _selectionMode(false);
      return;
    }
    if (fromBack) {
      final choice = await showAppDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: const Text('保存歌曲排序？'),
          content: const Text('拖动后的顺序尚未保存。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, 'cancel'),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, 'discard'),
              child: const Text('放弃'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, 'save'),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null || choice == 'cancel') return;
      if (choice == 'discard') {
        final byId = {for (final song in _songs) song.id: song};
        setState(
          () => _songs = [
            for (final id in _baseOrder)
              if (byId[id] != null) byId[id]!,
          ],
        );
        _selectionMode(false);
        return;
      }
    }
    final c = widget.controller;
    final session = c.session;
    if (session == null) return;
    setState(() => _saving = true);
    try {
      final songs = await c.library.editSongs(
        session,
        _collection,
        order: _songs.map((s) => s.id).toList(),
        expectedOrder: _baseOrder,
      );
      if (!mounted || c.session != session) return;
      _acceptEdit(songs);
      _selectionMode(false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(c.library.error ?? '已保存歌曲排序')));
    } catch (e) {
      _editFailure(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteSelected() async {
    if (_saving || !widget.editable || _selected.isEmpty) return;
    final c = widget.controller;
    final session = c.session;
    if (session == null) return;
    final remove = Set<String>.from(_selected);
    final confirmed = await showAppDialog<bool>(
      context: context,
      dangerous: true,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text('从歌单删除 ${remove.length} 首歌曲？'),
        content: Text(
          '删除会同步到服务器，本机下载与正在播放的队列保留。${_dirtyOrder ? '\n同时保存当前拖动后的顺序。' : ''}${_collection.isLinked ? '\n之后刷新同步原歌单时，这些歌曲可能重新加入。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || c.session != session) return;
    setState(() => _saving = true);
    try {
      final songs = await c.library.editSongs(
        session,
        _collection,
        removeIds: remove,
        order: _dirtyOrder
            ? _songs
                  .where((s) => !remove.contains(s.id))
                  .map((s) => s.id)
                  .toList()
            : null,
        expectedOrder: _dirtyOrder ? _baseOrder : null,
      );
      if (!mounted || c.session != session) return;
      _selected.clear();
      _acceptEdit(songs);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(c.library.error ?? '已从歌单删除所选歌曲')));
    } catch (e) {
      _editFailure(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copySelected() async {
    final c = widget.controller;
    final session = c.session;
    final songs = _selectedSongs;
    if (session == null || songs.isEmpty || _saving) return;
    final target = await pickCollection(context, c, songCount: songs.length);
    if (target == null || !mounted || c.session != session) return;
    setState(() => _saving = true);
    try {
      await c.library.editSongs(session, target, addSongs: songs);
      if (mounted && c.session == session) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(c.library.error ?? '已收藏到「${target.name}」')),
        );
      }
    } catch (e) {
      _editFailure(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _songRow(
    BuildContext context,
    int index,
    List<Song> visible, {
    bool reorderable = false,
  }) {
    final song = visible[index];
    final handle = Tooltip(
      message: widget.editable ? '拖动排序' : '原歌单只读，请在我的歌单中编辑副本',
      child: Icon(
        Icons.menu_rounded,
        size: 20,
        color: !_canReorder ? lxMuted.withValues(alpha: .4) : lxMuted,
      ),
    );
    return SongTile(
      key: reorderable ? ValueKey(song.id) : null,
      song: song,
      controller: widget.controller,
      queue: _songs,
      selected: _selecting ? _selected.contains(song.id) : null,
      selectionEnabled: !_saving && !_dragging,
      onSelect: !_selecting
          ? null
          : () => setState(() {
              if (!_selected.add(song.id)) _selected.remove(song.id);
            }),
      reorderHandle: !_selecting
          ? null
          : reorderable
          ? ReorderableDragStartListener(index: index, child: handle)
          : handle,
    );
  }

  Future<void> _collect() async {
    final c = widget.controller;
    final session = c.session;
    final collection = _collection;
    if (session == null ||
        collection.source == null ||
        widget.fetchPage == null ||
        _saving) {
      return;
    }
    final existing = c.library.collections
        .where(
          (v) =>
              v.source == collection.source && v.sourceListId == collection.id,
        )
        .firstOrNull;
    if (existing != null) {
      await performCollectionAction(context, c, existing, 'delete');
      return;
    }
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('收藏到我的歌单？'),
        content: const Text('将完整获取原歌单并保存到服务器。请避免同时在其他设备编辑歌单。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('收藏'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || c.session != session) return;
    setState(() => _saving = true);
    try {
      final added = await c.library.collectRemote(
        session,
        PlaylistSummary({
          'id': collection.id,
          'name': collection.name,
          'img': _image,
        }, collection.source!),
        (_, _, page) => widget.fetchPage!(page),
      );
      if (mounted && c.session == session) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(added ? '已收藏到我的歌单' : '歌单已存在，请刷新查看')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiFailure ? e.message : '收藏失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _batchDownload() async {
    final c = widget.controller;
    final songs = _selectedSongs;
    final session = c.session;
    if (songs.isEmpty || session == null) return;
    var selectedQuality = c.player.preferredQuality;
    final quality = await showAppSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheet).height * .6,
            child: Column(
              children: [
                SheetHeader(title: '下载 ${songs.length} 首歌曲'),
                Expanded(
                  child: ListView(
                    children: [
                      for (final q in AudioQuality.values)
                        ListTile(
                          selected: selectedQuality == q.id,
                          title: Text(q.label),
                          subtitle: Text(q.detail),
                          trailing: selectedQuality == q.id
                              ? const Icon(Icons.check_rounded, color: lxGreen)
                              : null,
                          onTap: () => update(() => selectedQuality = q.id),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(sheet, selectedQuality),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('下载'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (quality == null || !mounted || c.session != session) return;
    var count = 0;
    try {
      for (final song in songs) {
        if (c.session != session) break;
        await c.localMedia.enqueue(session, song, quality);
        count++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已将 $count 首歌曲加入本机下载列表')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiFailure ? e.message : '下载任务未能全部添加，请重试'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    finishRemembering();
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.controller,
      widget.controller.library,
    ]),
    builder: (context, _) {
      final c = widget.controller;
      final collection = _collection;
      final paged = c.pagedCollections;
      final query = _search.text.trim().toLowerCase();
      final filtered = _filtered;
      final total = query.isNotEmpty || widget.fetchPage == null || !_more
          ? filtered.length
          : _reportedTotal;
      final loadedPageCount = (filtered.length / _pageSize).ceil().clamp(
        1,
        1000000,
      );
      final pageCount = total == null
          ? loadedPageCount
          : displayPageCount(total, _pageSize);
      final currentPage = _visiblePage.clamp(0, pageCount - 1);
      final visible = paged
          ? filtered.skip(currentPage * _pageSize).take(_pageSize).toList()
          : filtered;
      final collected =
          !widget.editable &&
          c.library.collections.any(
            (v) =>
                v.source == collection.source &&
                v.sourceListId == collection.id,
          );
      return PopScope(
        canPop: !_searching && !_selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_selecting) {
            _finishEditing(fromBack: true);
          } else if (_searching) {
            _searchMode(false);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !_searching,
            title: _searching
                ? SizedBox(
                    height: compactSearchHeight(context),
                    child: TextField(
                      key: const ValueKey('collection-search'),
                      controller: _search,
                      focusNode: _searchFocus,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(fontSize: 14),
                      onChanged: (_) => setState(() => _visiblePage = 0),
                      decoration: compactSearchDecoration(
                        hintText: '搜索歌单内歌曲',
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除歌单搜索',
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _visiblePage = 0);
                                },
                              ),
                      ),
                    ),
                  )
                : _selecting
                ? ScrollingTitle(text: collection.name)
                : _collapsed
                ? ScrollingTitle(text: collection.name)
                : null,
            actions: _searching
                ? [
                    TextButton(
                      onPressed: () => _searchMode(false),
                      child: const Text('取消'),
                    ),
                  ]
                : [
                    if (!_selecting)
                      IconButton(
                        tooltip: '搜索歌单内歌曲',
                        onPressed: () => _searchMode(true),
                        icon: const Icon(Icons.search_rounded),
                      ),
                    if (!_selecting && widget.editable && !collection.isSystem)
                      CollectionMenu(
                        controller: c,
                        collection: collection,
                        onChanged: _changed,
                      ),
                  ],
          ),
          body: SafeArea(
            top: false,
            child: Material(
              color: Colors.white,
              child: Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refresh,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        controller: _scroll,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        slivers: [
                          if (!_searching && !_selecting)
                            SliverToBoxAdapter(
                              child: CollectionHeader(
                                key: _heroKey,
                                name: collection.name,
                                image: _image,
                                metadata: _metadata,
                                source: collection.source,
                                linked: collection.isLinked,
                              ),
                            ),
                          if (_searching)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  8,
                                  18,
                                  10,
                                ),
                                child: Text(
                                  '${filtered.length} 首匹配${_more ? ' · 仅搜索已加载歌曲' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: lxMuted,
                                  ),
                                ),
                              ),
                            ),
                          if (!_searching || _selecting)
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _CollectionToolbarDelegate(
                                height: 62,
                                child: Container(
                                  key: const ValueKey('collection-toolbar'),
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    6,
                                    10,
                                    8,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (_selecting) ...[
                                        Checkbox(
                                          shape: const CircleBorder(),
                                          tristate: true,
                                          value:
                                              filtered.isNotEmpty &&
                                                  filtered.every(
                                                    (s) => _selected.contains(
                                                      s.id,
                                                    ),
                                                  )
                                              ? true
                                              : filtered.any(
                                                  (s) =>
                                                      _selected.contains(s.id),
                                                )
                                              ? null
                                              : false,
                                          onChanged:
                                              _saving ||
                                                  _dragging ||
                                                  filtered.isEmpty
                                              ? null
                                              : (_) => setState(() {
                                                  if (filtered.every(
                                                    (s) => _selected.contains(
                                                      s.id,
                                                    ),
                                                  )) {
                                                    _selected.removeAll(
                                                      filtered.map((s) => s.id),
                                                    );
                                                  } else {
                                                    _selected.addAll(
                                                      filtered.map((s) => s.id),
                                                    );
                                                  }
                                                }),
                                        ),
                                        const Text(
                                          '全选',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _selected.isEmpty
                                                ? ''
                                                : '已选 ${_selected.length} 首',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: lxMuted,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: _saving || _dragging
                                              ? null
                                              : () => _finishEditing(),
                                          child: const Text('完成'),
                                        ),
                                      ] else ...[
                                        Expanded(
                                          child: PlayAllControl(
                                            buttonKey: const ValueKey(
                                              'collection-play',
                                            ),
                                            count: _songs.length,
                                            loadedOnly: _more,
                                            onPlay:
                                                _songs.isEmpty ||
                                                    c.session == null
                                                ? null
                                                : () => c.player.play(
                                                    c.session!,
                                                    _songs.first,
                                                    songs: _songs,
                                                  ),
                                          ),
                                        ),
                                        if (!widget.editable &&
                                            collection.source != null &&
                                            widget.fetchPage != null)
                                          IconButton(
                                            tooltip: collected
                                                ? '取消收藏歌单'
                                                : '收藏歌单',
                                            onPressed:
                                                _saving ||
                                                    c.library.mutating ||
                                                    c.session == null
                                                ? null
                                                : _collect,
                                            icon: Icon(
                                              collected
                                                  ? Icons.favorite_rounded
                                                  : Icons
                                                        .favorite_border_rounded,
                                              color: collected
                                                  ? lxGreen
                                                  : lxInk,
                                            ),
                                          ),
                                        IconButton(
                                          tooltip: '批量操作',
                                          onPressed: _songs.isEmpty
                                              ? null
                                              : () => _selectionMode(true),
                                          icon: const PlaylistEditGlyph(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (filtered.isEmpty && !_loading && _error == null)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Center(
                                  child: Text(
                                    query.isEmpty ? '这里还没有歌曲' : '没有匹配的歌曲',
                                    style: const TextStyle(color: lxMuted),
                                  ),
                                ),
                              ),
                            ),
                          if (_selecting && !widget.editable)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 8,
                                ),
                                child: Text(
                                  '原歌单只读；排序和删除请在“我的”中编辑收藏副本',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: lxMuted,
                                  ),
                                ),
                              ),
                            ),
                          if (_selecting && _canReorder)
                            SliverReorderableList(
                              itemCount: visible.length,
                              itemBuilder: (context, index) => _songRow(
                                context,
                                index,
                                visible,
                                reorderable: true,
                              ),
                              onReorderItem: _reorder,
                              onReorderStart: (_) =>
                                  setState(() => _dragging = true),
                              onReorderEnd: (_) {
                                if (mounted) setState(() => _dragging = false);
                              },
                              proxyDecorator: (child, _, _) => Material(
                                color: Colors.white,
                                elevation: 3,
                                borderRadius: BorderRadius.circular(12),
                                child: child,
                              ),
                            )
                          else
                            SliverList.builder(
                              itemCount: visible.length,
                              itemBuilder: (context, index) =>
                                  _songRow(context, index, visible),
                            ),
                          if (_error != null ||
                              _loading ||
                              (_more && (!paged || query.isNotEmpty)))
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Column(
                                  children: [
                                    if (_error != null)
                                      Text(
                                        _error!,
                                        style: const TextStyle(color: lxMuted),
                                      ),
                                    if (_loading)
                                      const Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    else
                                      TextButton(
                                        onPressed: _load,
                                        child: Text(
                                          _error == null ? '加载更多' : '重试',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (paged && (pageCount > 1 || (_more && query.isEmpty)))
                    ResultPagination(
                      key: const ValueKey('collection-pagination'),
                      page: currentPage,
                      pageCount: total == null ? null : pageCount,
                      loadedPageCount: loadedPageCount,
                      hasMore: _more && query.isEmpty,
                      onJump: _loading || _pageTurning || _saving || _dragging
                          ? null
                          : _turnTo,
                      onPrevious:
                          currentPage == 0 ||
                              _loading ||
                              _pageTurning ||
                              _dragging
                          ? null
                          : () => _turn(-1),
                      onNext:
                          _loading ||
                              _pageTurning ||
                              _dragging ||
                              (currentPage + 1 >= pageCount &&
                                  (!_more || query.isNotEmpty))
                          ? null
                          : () => _turn(1),
                    ),
                  if (_saving) const LinearProgressIndicator(minHeight: 2),
                  if (_selecting)
                    CollectionEditActions(
                      onNext:
                          _selected.isEmpty ||
                              c.session == null ||
                              _saving ||
                              _dragging
                          ? null
                          : () {
                              final count = c.player.enqueueNext(
                                c.session!,
                                _selectedSongs,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    count == 0
                                        ? '所选歌曲已是当前播放歌曲'
                                        : '已将 $count 首歌曲排为下一首播放',
                                  ),
                                ),
                              );
                            },
                      onCollect:
                          _selected.isEmpty ||
                              c.session == null ||
                              _saving ||
                              _dragging
                          ? null
                          : _copySelected,
                      onDownload:
                          _selected.isEmpty ||
                              c.session == null ||
                              _saving ||
                              _dragging
                          ? null
                          : _batchDownload,
                      onDelete:
                          !widget.editable ||
                              _selected.isEmpty ||
                              c.session == null ||
                              _saving ||
                              _dragging
                          ? null
                          : _deleteSelected,
                    )
                  else
                    MiniPlayer(player: c.player, controller: c, compact: true),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CollectionToolbarDelegate extends SliverPersistentHeaderDelegate {
  _CollectionToolbarDelegate({required this.height, required this.child});
  final double height;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: Colors.white,
    elevation: overlapsContent ? 1 : 0,
    child: child,
  );
  @override
  bool shouldRebuild(covariant _CollectionToolbarDelegate oldDelegate) => true;
}
