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
    this.selected,
    this.onSelect,
    this.reorderHandle,
    this.selectionEnabled = true,
  });
  final Song song;
  final bool? selected;
  final VoidCallback? onSelect;
  final Widget? reorderHandle;
  final bool selectionEnabled;
  final AppController controller;
  final List<Song> queue;
  void _play() {
    final session = controller.session;
    if (session != null) controller.player.play(session, song, songs: queue);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: onSelect == null
        ? SongArt(url: song.image, size: 48)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: selected ?? false,
                shape: const CircleBorder(),
                visualDensity: VisualDensity.compact,
                onChanged: selectionEnabled ? (_) => onSelect!() : null,
              ),
              const SizedBox(width: 6),
              SongArt(url: song.image, size: 44),
            ],
          ),
    title: Text(
      song.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 5),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          controller.serverFiles,
          controller.localMedia,
        ]),
        builder: (context, _) =>
            SongMetadata(controller: controller, song: song),
      ),
    ),
    onTap: onSelect == null
        ? _play
        : selectionEnabled
        ? onSelect
        : null,
    selected: selected ?? false,
    trailing: onSelect != null
        ? reorderHandle ?? const SizedBox(width: 24)
        : IconButton(
            tooltip: '${song.name}的更多操作',
            icon: const Icon(Icons.more_vert_rounded, color: lxMuted),
            onPressed: () =>
                showSongActions(context, controller, song, queue: queue),
          ),
  );
}
