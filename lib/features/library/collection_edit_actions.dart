import 'package:flutter/material.dart';

import '../../app/theme.dart';

class CollectionEditActions extends StatelessWidget {
  const CollectionEditActions({
    super.key,
    this.onNext,
    this.onCollect,
    this.onDownload,
    this.onDelete,
  });
  final VoidCallback? onNext, onCollect, onDownload, onDelete;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _action('下一首播放', Icons.playlist_play_rounded, onNext),
        _action('收藏到歌单', Icons.playlist_add_rounded, onCollect),
        _action('下载', Icons.download_rounded, onDownload),
        _action('删除', Icons.delete_outline_rounded, onDelete),
      ],
    ),
  );
  Widget _action(String label, IconData icon, VoidCallback? onTap) => Expanded(
    child: Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24,
                color: onTap == null ? lxMuted.withValues(alpha: .4) : lxInk,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 11,
                  color: onTap == null ? lxMuted.withValues(alpha: .4) : lxInk,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
