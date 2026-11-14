import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../shared/song_art.dart';
import 'collection_screen.dart';
import 'library_controller.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _tab = 0;
  Future<void> _refresh() async {
    final session = widget.controller.session;
    if (session != null) await widget.controller.refreshLibrary();
  }

  void _collection(MusicCollection collection) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => CollectionScreen(
        controller: widget.controller,
        collection: collection,
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: SegmentedButton<int>(
                  style: SegmentedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 13),
                    visualDensity: VisualDensity.compact,
                  ),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('歌单')),
                    ButtonSegment(value: 1, label: Text('歌手')),
                    ButtonSegment(value: 2, label: Text('专辑')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (v) => setState(() => _tab = v.first),
                ),
              ),
            ),
            if (library.loading)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
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
            else
              SliverList.builder(
                itemCount: count,
                itemBuilder: (context, index) {
                  if (_tab == 0) {
                    final collection = library.collections[index];
                    return ListTile(
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
                              child: const Icon(
                                Icons.favorite_rounded,
                                color: lxGreen,
                              ),
                            )
                          : SongArt(url: collection.cover, size: 48),
                      title: Text(
                        collection.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${collection.songs.length} 首',
                        style: const TextStyle(fontSize: 12, color: lxMuted),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: lxMuted,
                      ),
                      onTap: () => _collection(collection),
                    );
                  }
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
