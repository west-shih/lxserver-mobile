import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/lx_api.dart';
import '../../shared/song_art.dart';
import '../../shared/platform_filters.dart';
import 'collection_screen.dart';
import 'collection_actions.dart';
import 'library_controller.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _tab = 0;
  bool _savingOrder = false, _dragging = false, _editing = false;
  List<MusicCollection>? _ordered;
  bool get _busy =>
      _savingOrder ||
      _dragging ||
      _editing ||
      widget.controller.library.mutating ||
      widget.controller.library.loading;

  Future<void> _reorder(int from, int to) async {
    final c = widget.controller;
    final session = c.session;
    if (_savingOrder ||
        _editing ||
        c.library.mutating ||
        session == null ||
        from == to) {
      return;
    }
    final ordered = List<MusicCollection>.of(c.library.collections);
    final before = ordered.map((v) => v.id).toList();
    ordered.insert(to, ordered.removeAt(from));
    setState(() {
      _savingOrder = true;
      _ordered = ordered;
    });
    try {
      await c.library.reorderCollections(
        session,
        ordered.map((v) => v.id).toList(),
        before,
      );
      if (mounted && c.library.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(c.library.error!)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiFailure ? e.message : '排序未保存，请刷新后重试'),
            action: SnackBarAction(label: '刷新', onPressed: () => _refresh()),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingOrder = false;
          _ordered = null;
        });
      }
    }
  }

  Future<void> _edit(MusicCollection collection) async {
    if (_busy || collection.isSystem) return;
    setState(() => _editing = true);
    try {
      await showCollectionActions(context, widget.controller, collection);
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Widget _collectionTile(MusicCollection collection, {int? dragIndex}) =>
      Material(
        key: ValueKey('library-collection-${collection.id}'),
        color: lxCanvas,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 5,
          ),
          leading: collection.id == 'love'
              ? Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4F5EB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.favorite_rounded, color: lxGreen),
                )
              : SongArt(url: collection.cover, size: 48),
          title: Text(
            collection.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${collection.songs.length} 首',
            style: const TextStyle(fontSize: 12, color: lxMuted),
          ),
          trailing: dragIndex == null
              ? null
              : ReorderableDragStartListener(
                  index: dragIndex,
                  enabled: !_busy && widget.controller.session != null,
                  child: const Tooltip(
                    message: '拖动排序；长按歌单编辑',
                    child: SizedBox(
                      width: 40,
                      height: 48,
                      child: Icon(Icons.menu_rounded, size: 20, color: lxMuted),
                    ),
                  ),
                ),
          onTap: _busy ? null : () => _collection(collection),
          onLongPress: collection.isSystem || _busy
              ? null
              : () => _edit(collection),
        ),
      );
  Future<void> _refresh() async {
    if (_busy) return;
    final session = widget.controller.session;
    if (session != null) await widget.controller.refreshLibrary();
  }

  void _collection(MusicCollection collection) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => CollectionScreen(
        controller: widget.controller,
        collection: collection,
        editable: true,
      ),
    ),
  );
  void _entity(Map<String, dynamic> entity, bool artist) {
    final c = widget.controller;
    final session = c.session;
    if (session == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CollectionScreen(
          controller: c,
          collection: MusicCollection(
            '${entity['id']}',
            '${entity['name'] ?? '收藏'}',
            [],
            image: '${entity['picUrl'] ?? ''}',
          ),
          fetchPage: (_) => c.library.entitySongs(session, entity, artist),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller.library,
    builder: (context, _) {
      final library = widget.controller.library;
      final collections = _ordered ?? library.collections;

      final entities = _tab == 1 ? library.artists : library.albums;
      final error = _tab == 0
          ? library.error
          : _tab == 1
          ? library.artistError
          : library.albumError;
      final count = _tab == 0 ? library.collections.length : entities.length;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          key: PageStorageKey('library-$_tab'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: EqualFilterRow(
                labels: const ['歌单', '歌手', '专辑'],
                selectedIndex: _tab,
                onSelected: _busy
                    ? null
                    : (index) => setState(() => _tab = index),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 2,
                child: library.loading || _savingOrder
                    ? const LinearProgressIndicator(minHeight: 2)
                    : null,
              ),
            ),
            if (error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: lxMuted),
                      ),
                      TextButton(onPressed: _refresh, child: const Text('重试')),
                    ],
                  ),
                ),
              ),
            if (count == 0 && !library.loading && error == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('暂无收藏', style: TextStyle(color: lxMuted)),
                ),
              )
            else if (_tab == 0)
              SliverReorderableList(
                itemCount: collections.length,
                onReorderItem: _reorder,
                onReorderStart: (_) => setState(() => _dragging = true),
                onReorderEnd: (_) {
                  if (mounted) setState(() => _dragging = false);
                },
                itemBuilder: (_, index) =>
                    _collectionTile(collections[index], dragIndex: index),
              )
            else
              SliverList.builder(
                itemCount: count,
                itemBuilder: (context, index) {
                  final entity = entities[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    leading: SongArt(
                      url: '${entity['picUrl'] ?? ''}',
                      size: 48,
                    ),
                    title: Text(
                      '${entity['name'] ?? '未命名收藏'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                    subtitle: _tab == 1
                        ? null
                        : Text(
                            '${entity['artistName'] ?? entity['singer'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: lxMuted,
                            ),
                          ),
                    onTap: () => _entity(entity, _tab == 1),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      );
    },
  );
}
