import 'package:flutter/material.dart';

import '../../shared/app_modal.dart';

import '../../app/theme.dart';
import '../../core/lx_api.dart';
import '../../shared/song_art.dart';
import 'collection_metadata.dart';

class CollectionHeader extends StatelessWidget {
  const CollectionHeader({
    super.key,
    required this.name,
    required this.image,
    required this.metadata,
    this.source,
    this.linked = false,
  });
  final String name;
  final String image;
  final MusicSource? source;
  final bool linked;
  final CollectionMetadata metadata;
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [lxCanvas, Color(0xFFFBFDFC), Colors.white],
        stops: [0, .45, 1],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    ),
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SongArt(url: image, size: 96),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: lxInk,
                    ),
                  ),
                  if (source != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '来自 ${source!.label}',
                          style: const TextStyle(fontSize: 11, color: lxMuted),
                        ),
                      ),
                    ),
                  if (metadata.author.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        '创建者：${metadata.author}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: lxMuted),
                      ),
                    )
                  else if (linked)
                    const Padding(
                      padding: EdgeInsets.only(top: 7),
                      child: Text(
                        '已收藏的在线歌单',
                        style: TextStyle(fontSize: 12, color: lxMuted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (metadata.playCount.isNotEmpty || metadata.date.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                if (metadata.playCount.isNotEmpty)
                  _detail(
                    Icons.headphones_rounded,
                    '${metadata.playCount} 次播放',
                  ),
                if (metadata.date.isNotEmpty)
                  _detail(Icons.calendar_today_outlined, metadata.date),
              ],
            ),
          ),
        if (metadata.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              onTap: () => showAppSheet<void>(
                context: context,
                title: '歌单简介',
                subtitle: name,
                closeLabel: '关闭',
                showDragHandle: true,
                isScrollControlled: true,
                builder: (context) => SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          metadata.description,
                          style: const TextStyle(height: 1.6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      metadata.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: lxMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: lxMuted,
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  Widget _detail(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: lxMuted),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(fontSize: 11, color: lxMuted)),
    ],
  );
}
