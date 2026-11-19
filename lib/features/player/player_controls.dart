import 'package:flutter/material.dart';

import '../../shared/app_modal.dart';

import '../../app/theme.dart';
import '../../shared/song_art.dart';
import 'player_controller.dart';
import 'playback_mode.dart';
import 'playback_glyph.dart';

class PlaybackModeIcon extends StatelessWidget {
  const PlaybackModeIcon({
    super.key,
    required this.mode,
    this.size = 23,
    this.color,
  });
  final PlaybackMode mode;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ModePainter(
          mode,
          color ?? IconTheme.of(context).color ?? lxInk,
        ),
      ),
    ),
  );
}

class _ModePainter extends CustomPainter {
  const _ModePainter(this.mode, this.color);
  final PlaybackMode mode;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    switch (mode) {
      case PlaybackMode.order:
        for (final y in [8.0, 16.0]) {
          path
            ..moveTo(5, y)
            ..lineTo(19, y)
            ..moveTo(16.3, y - 2.7)
            ..lineTo(19, y)
            ..lineTo(16.3, y + 2.7);
        }
      case PlaybackMode.list:
      case PlaybackMode.single:
        path
          ..moveTo(4, 10)
          ..lineTo(4, 8)
          ..quadraticBezierTo(4, 5, 7, 5)
          ..lineTo(19, 5)
          ..moveTo(16.4, 2.4)
          ..lineTo(19, 5)
          ..lineTo(16.4, 7.6)
          ..moveTo(20, 14)
          ..lineTo(20, 16)
          ..quadraticBezierTo(20, 19, 17, 19)
          ..lineTo(5, 19)
          ..moveTo(7.6, 16.4)
          ..lineTo(5, 19)
          ..lineTo(7.6, 21.6);
        if (mode == PlaybackMode.single) {
          path
            ..moveTo(10.5, 10.8)
            ..lineTo(12, 9.5)
            ..lineTo(12, 14.5);
        }
      case PlaybackMode.random:
        path
          ..moveTo(4.5, 6)
          ..lineTo(7, 6)
          ..cubicTo(11, 6, 13, 18, 17, 18)
          ..lineTo(20, 18)
          ..moveTo(17.4, 15.4)
          ..lineTo(20, 18)
          ..lineTo(17.4, 20.6)
          ..moveTo(4.5, 18)
          ..lineTo(7, 18)
          ..quadraticBezierTo(8.7, 18, 10, 15.2)
          ..moveTo(14, 8.8)
          ..quadraticBezierTo(15.3, 6, 17, 6)
          ..lineTo(20, 6)
          ..moveTo(17.4, 3.4)
          ..lineTo(20, 6)
          ..lineTo(17.4, 8.6);
    }
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ModePainter old) =>
      old.mode != mode || old.color != color;
}

void showPlaybackMode(BuildContext context, PlayerController player) {
  showAppSheet<void>(
    context: context,
    title: '播放模式',
    showDragHandle: true,
    builder: (context) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in PlaybackMode.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: player.mode == mode
                      ? const Color(0xFFE4F4EC)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: PlaybackModeIcon(
                      mode: mode,
                      color: player.mode == mode ? lxGreen : lxMuted,
                    ),
                    title: Text(
                      mode.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: player.mode == mode
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: player.mode == mode ? lxGreen : lxInk,
                      ),
                    ),
                    trailing: player.mode == mode
                        ? const Icon(Icons.check_rounded, color: lxGreen)
                        : null,
                    onTap: () {
                      player.setMode(mode);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

String clockText(Duration value) =>
    '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

void showQueue(BuildContext context, PlayerController player) {
  showAppSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    keepMinimumHeight: true,
    builder: (context) => ListenableBuilder(
      listenable: player,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '接下来播放',
            subtitle: '${player.queue.length} 首',
            closeLabel: '关闭',
          ),
          Flexible(
            child: player.queue.isEmpty
                ? const Center(heightFactor: 1, child: Text('队列还是空的，去搜索一首喜欢的歌'))
                : Material(
                    type: MaterialType.transparency,
                    clipBehavior: Clip.hardEdge,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: player.queue.length,
                      itemBuilder: (context, i) {
                        final song = player.queue[i];
                        return ListTile(
                          selected: i == player.index,
                          leading: SongArt(url: song.image, size: 44),
                          title: Text(
                            song.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: i == player.index ? lxGreen : lxInk,
                            ),
                          ),
                          subtitle: Text(
                            song.singer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (i == player.index)
                                const Icon(
                                  Icons.graphic_eq,
                                  color: lxGreen,
                                  size: 18,
                                ),
                              IconButton(
                                tooltip: '移出队列',
                                onPressed: player.resolving
                                    ? null
                                    : () => player.remove(i),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 20,
                                  color: lxMuted,
                                ),
                              ),
                            ],
                          ),
                          enabled: !player.resolving,
                          onTap: () => player.select(i),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

class PlayButton extends StatelessWidget {
  const PlayButton({super.key, required this.player, this.large = false});
  final PlayerController player;
  final bool large;
  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: player.error != null
        ? '重试播放'
        : player.playing
        ? '暂停'
        : '播放',
    onPressed: player.resolving ? null : player.toggle,
    style: IconButton.styleFrom(
      backgroundColor: lxGreen,
      foregroundColor: Colors.white,
      fixedSize: Size.square(large ? 76 : 44),
      shape: const CircleBorder(),
    ),
    icon: player.resolving
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: lxGreen),
          )
        : player.error != null
        ? Icon(Icons.refresh_rounded, size: large ? 38 : 24)
        : PlaybackGlyph(
            player.playing ? PlaybackGlyphType.pause : PlaybackGlyphType.play,
            size: large ? 40 : 26,
          ),
  );
}
