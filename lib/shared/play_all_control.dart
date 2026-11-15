import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Shared compact play control for playlist, artist and album toolbars.
class PlayAllControl extends StatelessWidget {
  const PlayAllControl({
    super.key,
    required this.count,
    required this.onPlay,
    this.loadedOnly = false,
    this.showLoadedLabel = true,
    this.buttonKey,
  });
  final int count;
  final VoidCallback? onPlay;
  final bool loadedOnly;
  final bool showLoadedLabel;
  final Key? buttonKey;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton.filled(
        key: buttonKey,
        tooltip: loadedOnly ? '播放已加载歌曲' : '播放全部',
        onPressed: onPlay,
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          fixedSize: const Size(32, 32),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.play_arrow_rounded, size: 23),
      ),
      const SizedBox(width: 10),
      const Text(
        '播放全部',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          '$count 首${loadedOnly && showLoadedLabel ? ' · 已加载' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: lxMuted),
        ),
      ),
    ],
  );
}
