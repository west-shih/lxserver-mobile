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

  Widget _art(double size) {
    final player = controller.player;
    final current = player.current?.id == song.id;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SongArt(url: song.image, size: size),
          if (current)
            ClipRRect(
              borderRadius: BorderRadius.circular(size * .2),
              child: Material(
                color: Colors.black45,
                child: IconButton(
                  tooltip: player.playing ? '暂停当前歌曲' : '继续播放当前歌曲',
                  onPressed: onSelect == null
                      ? () => player.toggle()
                      : selectionEnabled
                      ? onSelect
                      : null,
                  icon: Icon(
                    player.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.player,
    builder: (context, _) => ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: onSelect == null
          ? _art(48)
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
                _art(44),
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
    ),
  );
}
