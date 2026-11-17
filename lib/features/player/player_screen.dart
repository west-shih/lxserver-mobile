export 'quality_sheet.dart';
import '../../shared/song_metadata.dart';
import 'comments_sheet.dart';
import '../../app/controller.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/song_art.dart';
import '../../shared/song_actions.dart';
import 'lyrics_view.dart';
import 'player_controller.dart';
import 'player_controls.dart';
import 'playback_glyph.dart';

class _SongInfo extends StatelessWidget {
  const _SongInfo({required this.player, this.app});
  final PlayerController player;
  final AppController? app;
  @override
  Widget build(BuildContext context) {
    final song = player.current!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.name,
                  key: const ValueKey('player-song-title'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  song.singer,
                  key: const ValueKey('player-song-artist'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: lxMuted,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                if (app != null) ...[
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      app!.serverFiles,
                      app!.localMedia,
                    ]),
                    builder: (_, _) => SongMetadata(
                      key: const ValueKey('player-song-metadata'),
                      controller: app!,
                      song: song,
                      showSinger: false,
                      qualityOverride: player.qualityLabel,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (app != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: '歌曲更多操作',
              onPressed: () =>
                  showSongActions(context, app!, song, fromPlayer: true),
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.player, this.controller});
  final PlayerController player;
  final AppController? controller;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final PageController _pages;
  int _page = 0;
  @override
  void initState() {
    super.initState();
    _page = widget.controller?.pageState('player')['page'] == 1 ? 1 : 0;
    _pages = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(int index) => _pages.animateToPage(
    index,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.player,
    builder: (context, _) {
      final player = widget.player;
      final song = player.current;
      if (song == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('还没有正在播放的歌曲')),
        );
      }
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '收起播放器',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 2; i++)
                TextButton(
                  onPressed: () => _select(i),
                  style: TextButton.styleFrom(
                    foregroundColor: _page == i ? lxInk : lxMuted,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        i == 0 ? '封面' : '歌词',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: _page == i
                              ? FontWeight.w800
                              : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 5),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: _page == i ? 16 : 4,
                        height: 3,
                        decoration: BoxDecoration(
                          color: _page == i ? lxGreen : Colors.transparent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '播放队列',
              onPressed: () => showQueue(context, player),
              icon: const Icon(Icons.queue_music_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minimumHeight =
                  MediaQuery.textScalerOf(context).scale(1) > 1.3
                  ? 780.0
                  : 620.0;
              final height = math.max(constraints.maxHeight, minimumHeight);
              return SingleChildScrollView(
                physics: height > constraints.maxHeight
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  height: height,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        children: [
                          Expanded(
                            child: PageView(
                              key: const ValueKey('player-pages'),
                              controller: _pages,
                              onPageChanged: (index) {
                                setState(() => _page = index);
                                widget.controller?.rememberPage('player', {
                                  'page': index,
                                });
                              },
                              children: [
                                LayoutBuilder(
                                  builder: (context, area) => Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: SongArt(
                                        url: song.image,
                                        localPath: widget.controller?.localMedia
                                            .artworkPath(song),
                                        size: math
                                            .min(
                                              area.maxWidth - 48,
                                              area.maxHeight - 48,
                                            )
                                            .clamp(40, 360),
                                      ),
                                    ),
                                  ),
                                ),
                                LyricsView(
                                  key: ValueKey('lyrics-${song.id}'),
                                  player: player,
                                ),
                              ],
                            ),
                          ),
                          _SongInfo(player: player, app: widget.controller),
                          if (player.error != null ||
                              player.qualityNotice != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
                              child: Text(
                                player.error ?? player.qualityNotice!,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.5,
                                  color: player.error == null
                                      ? lxMuted
                                      : Colors.redAccent,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                            child: Slider(
                              value: player.position.inMilliseconds
                                  .toDouble()
                                  .clamp(
                                    0,
                                    player.duration.inMilliseconds
                                        .toDouble()
                                        .clamp(1, double.infinity),
                                  ),
                              max: player.duration.inMilliseconds
                                  .toDouble()
                                  .clamp(1, double.infinity),
                              onChanged:
                                  player.resolving ||
                                      player.duration == Duration.zero
                                  ? null
                                  : (v) => player.seek(
                                      Duration(milliseconds: v.toInt()),
                                    ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  clockText(player.position),
                                  style: const TextStyle(
                                    color: lxMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  clockText(player.duration),
                                  style: const TextStyle(
                                    color: lxMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  tooltip: player.mode.label,
                                  onPressed: () =>
                                      showPlaybackMode(context, player),
                                  icon: PlaybackModeIcon(
                                    mode: player.mode,
                                    size: 23,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '上一首',
                                  iconSize: 36,
                                  onPressed:
                                      player.canPrevious && !player.resolving
                                      ? player.previous
                                      : null,
                                  icon: const PlaybackGlyph(
                                    PlaybackGlyphType.previous,
                                    size: 32,
                                  ),
                                ),
                                PlayButton(player: player, large: true),
                                IconButton(
                                  tooltip: '下一首',
                                  iconSize: 36,
                                  onPressed: player.canNext && !player.resolving
                                      ? player.next
                                      : null,
                                  icon: const PlaybackGlyph(
                                    PlaybackGlyphType.next,
                                    size: 32,
                                  ),
                                ),
                                if (widget.controller != null)
                                  IconButton(
                                    tooltip: '歌曲评论',
                                    onPressed: song.isOnline
                                        ? () => showComments(
                                            context,
                                            widget.controller!,
                                            song,
                                          )
                                        : null,
                                    icon: const PlaybackGlyph(
                                      PlaybackGlyphType.comment,
                                      size: 25,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
