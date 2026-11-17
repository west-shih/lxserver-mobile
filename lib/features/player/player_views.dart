import '../../app/browse_navigation.dart';
import '../../app/controller.dart';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/song_art.dart';
import 'player_controller.dart';
import 'player_controls.dart';
import 'player_screen.dart';
export 'player_controls.dart';
export 'player_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.player,
    this.controller,
    this.compact = false,
  });
  final PlayerController player;
  final bool compact;
  final AppController? controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: player,
    builder: (context, _) {
      final song = player.current;
      if (song == null) return const SizedBox.shrink();
      return Container(
        margin: EdgeInsets.fromLTRB(16, compact ? 0 : 8, 16, compact ? 0 : 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE1EBE5)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0B163F2A),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => Navigator.of(context).push(
                browseRoute(
                  PlayerScreen(player: player, controller: controller),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    SongArt(
                      url: song.image,
                      localPath: controller?.localMedia.artworkPath(song),
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            player.error ??
                                (player.resolving ? '正在获取音频…' : song.singer),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: player.error == null
                                  ? lxMuted
                                  : Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PlayButton(player: player),
                    IconButton(
                      tooltip: '播放队列',
                      onPressed: () => showQueue(context, player),
                      icon: const Icon(Icons.queue_music_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(
                value: player.duration.inMilliseconds > 0
                    ? (player.position.inMilliseconds /
                              player.duration.inMilliseconds)
                          .clamp(0, 1)
                    : 0,
                minHeight: 2,
                backgroundColor: const Color(0xFFEEF4F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      );
    },
  );
}
