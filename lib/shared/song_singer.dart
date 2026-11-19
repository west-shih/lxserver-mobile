import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../core/lx_api.dart';
import '../features/search/entity_widgets.dart';
import '../features/search/music_entity.dart';
import 'app_modal.dart';

class SongSinger extends StatefulWidget {
  const SongSinger({
    super.key,
    required this.song,
    required this.controller,
    required this.style,
  });

  final Song song;
  final AppController? controller;
  final TextStyle style;

  @override
  State<SongSinger> createState() => _SongSingerState();
}

class _SongSingerState extends State<SongSinger> {
  bool _opening = false;

  Future<String?> _choose(String title, Map<String, String> options) =>
      showAppSheet<String>(
        context: context,
        title: title,
        builder: (sheet) => ListView(
          shrinkWrap: true,
          children: [
            for (final entry in options.entries)
              ListTile(
                title: Text(entry.value),
                onTap: () => Navigator.pop(sheet, entry.key),
              ),
          ],
        ),
      );

  Future<void> _open(
    AppController controller,
    Session session,
    Song song,
  ) async {
    if (_opening) return;
    _opening = true;
    final source = song.source;
    bool stillCurrent() =>
        widget.song.id == song.id && controller.session == session;
    try {
      final names = song.singer
          .split('、')
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet();
      if (names.isEmpty) return;
      final name = names.length == 1
          ? names.single
          : await _choose('选择歌手', {for (final name in names) name: name});
      if (!mounted || !stillCurrent() || name == null) return;

      final meta = song.raw['meta'];
      final id = names.length == 1
          ? [
                  for (final key in ['artistId', 'singerId', 'singermid']) ...[
                    song.raw[key],
                    if (meta is Map) meta[key],
                  ],
                ]
                .map((value) => '${value ?? ''}'.trim())
                .where((id) => isArtistDetailId(source, id))
                .firstOrNull
          : null;
      if (id != null) {
        openEntity(
          context,
          controller,
          MusicEntity({'id': id, 'name': name}, source, true),
        );
        return;
      }

      final candidates = await controller.entitySearch.findArtists(
        session,
        source,
        name,
      );
      if (!mounted || !stillCurrent()) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('未找到对应歌手')));
        return;
      }
      final artist = candidates.length == 1 && candidates.single.name == name
          ? candidates.single
          : await _chooseArtist(candidates);
      if (mounted && stillCurrent() && artist != null) {
        openEntity(context, controller, artist);
      }
    } catch (error) {
      if (!mounted || !stillCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error is ApiFailure ? error.message : '歌手查询失败，请重试'),
        ),
      );
    } finally {
      _opening = false;
    }
  }

  Future<MusicEntity?> _chooseArtist(List<MusicEntity> artists) =>
      showAppSheet<MusicEntity>(
        context: context,
        title: '选择歌手',
        builder: (sheet) => ListView(
          shrinkWrap: true,
          children: [
            for (final artist in artists)
              ListTile(
                title: Text(artist.name),
                subtitle: Text(artist.alias.isEmpty ? artist.id : artist.alias),
                onTap: () => Navigator.pop(sheet, artist),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final controller = widget.controller;
    final session = controller?.session;
    final clickable =
        controller != null &&
        session != null &&
        song.isOnline &&
        controller.entitySources.contains(song.source) &&
        song.singer.trim().isNotEmpty &&
        song.singer != '未知歌手';
    final text = Text(
      song.singer,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
    if (!clickable) return text;
    return InkWell(onTap: () => _open(controller, session, song), child: text);
  }
}
