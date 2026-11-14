import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/theme.dart';
import '../core/lx_api.dart';
import 'song_metadata.dart';
import 'song_art.dart';
import 'song_actions.dart';

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.controller,
    required this.queue,
  });
  final Song song;
  final AppController controller;
  final List<Song> queue;
  void _play() {
    final session = controller.session;
    if (session != null) controller.player.play(session, song, songs: queue);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      controller.serverFiles,
      controller.localMedia,
    ]),
    builder: (context, _) => ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SongArt(url: song.image, size: 48),
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: SongMetadata(controller: controller, song: song),
      ),
      onTap: _play,
      trailing: IconButton(
        tooltip: '${song.name}的更多操作',
        icon: const Icon(Icons.more_vert_rounded, color: lxMuted),
        onPressed: () =>
            showSongActions(context, controller, song, queue: queue),
      ),
    ),
  );
}
