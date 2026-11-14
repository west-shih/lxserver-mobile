import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/lx_api.dart';
import '../../shared/song_art.dart';
import '../../shared/song_tile.dart';
import '../player/player_views.dart';
import 'library_controller.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key,
    required this.controller,
    required this.collection,
    this.fetchPage,
  });
  final AppController controller;
  final MusicCollection collection;
  final Future<SongBatch> Function(int)? fetchPage;
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  late List<Song> _songs;
  int _page = 0;
  bool _loading = false;
  bool _more = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.controller.refreshServerFiles();
    _songs = [...widget.collection.songs];
    _more = widget.fetchPage != null;
    if (_more) _load();
  }

  Future<void> _load({bool restart = false}) async {
    if (_loading || widget.fetchPage == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = restart ? 1 : _page + 1;
      final result = await widget.fetchPage!(page);
      if (!mounted) return;
      final existing = restart ? <Song>[] : _songs;
      final ids = existing.map((s) => s.id).toSet();
      final fresh = result.songs.where((s) => ids.add(s.id)).toList();
      setState(() {
        _songs = [...existing, ...fresh];
        _page = page;
        _more = result.hasMore && fresh.isNotEmpty;
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

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.collection.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  SongArt(url: widget.collection.cover, size: 92),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.collection.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_songs.length} 首${_more ? ' · 可继续加载' : ''}',
                          style: const TextStyle(color: lxMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _songs.isEmpty || c.session == null
                      ? null
                      : () => c.player.play(
                          c.session!,
                          _songs.first,
                          songs: _songs,
                        ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放全部已加载歌曲'),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _songs.isEmpty && !_loading && _error == null
                  ? const Center(
                      child: Text('这里还没有歌曲', style: TextStyle(color: lxMuted)),
                    )
                  : ListView.builder(
                      itemCount: _songs.length + 1,
                      itemBuilder: (context, index) {
                        if (index < _songs.length) {
                          return SongTile(
                            song: _songs[index],
                            controller: c,
                            queue: _songs,
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              if (_error != null)
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: lxMuted),
                                ),
                              if (_loading)
                                const CircularProgressIndicator()
                              else if (_more || _error != null)
                                TextButton(
                                  onPressed: _load,
                                  child: Text(_error == null ? '加载更多' : '重试'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            MiniPlayer(player: c.player, controller: c),
          ],
        ),
      ),
    );
  }
}
