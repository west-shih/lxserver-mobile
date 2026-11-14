import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/theme.dart';
import 'player_controller.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.player});
  final PlayerController player;
  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  int _active = -1;
  Object? _lyrics;
  bool _follow = true;
  bool _loading = false;
  String? _error;
  List<GlobalKey> _keys = [];
  @override
  void initState() {
    super.initState();
    widget.player.addListener(_update);
    _update();
  }

  @override
  void dispose() {
    widget.player.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final player = widget.player;
    final changed = !identical(_lyrics, player.lyrics);
    final active = player.lyrics.indexAt(player.position);
    final stateChanged =
        _loading != player.loadingLyrics || _error != player.lyricError;
    _loading = player.loadingLyrics;
    _error = player.lyricError;
    if (changed) {
      _lyrics = player.lyrics;
      _keys = List.generate(player.lyrics.lines.length, (_) => GlobalKey());
      _follow = true;
    }
    if (changed || active != _active || stateChanged) {
      _active = active;
      if (mounted) setState(() {});
      if (_follow) _scroll();
    }
  }

  void _scroll() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !_follow || _active < 0 || _active >= _keys.length) return;
    final target = _keys[_active].currentContext;
    if (target != null && target.findRenderObject() != null) {
      Scrollable.maybeOf(target)?.position.ensureVisible(
        target.findRenderObject()!,
        alignment: .4,
        duration: const Duration(milliseconds: 320),
      );
    }
  });
  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    if (player.loadingLyrics) {
      return const Center(child: CircularProgressIndicator());
    }
    if (player.lyricError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                player.lyricError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: lxMuted),
              ),
              TextButton(
                onPressed: player.loadLyrics,
                child: const Text('重试歌词'),
              ),
            ],
          ),
        ),
      );
    }
    if (player.lyrics.lines.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Text(
          player.lyrics.plain.isEmpty ? '暂无歌词，享受音乐吧。' : player.lyrics.plain,
          style: const TextStyle(color: lxMuted, fontSize: 19, height: 2),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (notification.direction != ScrollDirection.idle && _follow) {
                setState(() => _follow = false);
              }
              return false;
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(player.lyrics.lines.length, (index) {
                  final line = player.lyrics.lines[index];
                  return InkWell(
                    key: _keys[index],
                    borderRadius: BorderRadius.circular(12),
                    onTap: player.duration == Duration.zero || player.resolving
                        ? null
                        : () => player.seek(line.time),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            line.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 23,
                              height: 1.6,
                              fontWeight: index == _active
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: index == _active ? lxGreen : lxMuted,
                            ),
                          ),
                          if (line.translation.isNotEmpty)
                            Text(
                              line.translation,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.7,
                                color: index == _active ? lxInk : lxMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
        if (!_follow)
          TextButton.icon(
            onPressed: () {
              setState(() => _follow = true);
              _scroll();
            },
            icon: const Icon(Icons.my_location_rounded, size: 16),
            label: const Text('回到当前歌词'),
          ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '点击歌词调整进度',
            style: TextStyle(color: lxMuted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
