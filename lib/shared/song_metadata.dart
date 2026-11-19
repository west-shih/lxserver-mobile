import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/theme.dart';
import '../core/lx_api.dart';
import '../features/player/quality.dart';
import 'music_badge.dart';
import '../features/local_media/local_media_screens.dart';

class SongMetadata extends StatelessWidget {
  const SongMetadata({
    super.key,
    required this.controller,
    required this.song,
    this.showSinger = true,
    this.showCurrentQuality = false,
  });
  final AppController controller;
  final Song song;
  final bool showSinger;
  final bool showCurrentQuality;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.player,
    builder: (context, _) => _buildMetadata(context),
  );

  Widget _buildMetadata(BuildContext context) {
    final folders = controller.serverFiles.folders(song);
    final local = controller.localMedia.folders(song);
    final session = controller.session;
    final remembered = session == null
        ? null
        : AudioQuality.find(controller.player.rememberedQuality(session, song));
    final advertised = remembered == null && !showCurrentQuality
        ? QualityPolicy.badgeInfo(
            song,
            verified: [...folders.keys, ...local.keys],
          )
        : null;
    final option = showCurrentQuality
        ? AudioQuality.find(controller.player.reportedQuality)
        : remembered ?? AudioQuality.find(advertised?.id);
    final quality = showCurrentQuality
        ? controller.player.qualityLabel
        : (remembered?.id == 'master' ? 'Master' : remembered?.label) ??
              advertised?.label;
    final cached = controller.localMedia.badge(song);
    final badges = <Widget>[
      MusicBadge(
        song.sourceLabel,
        tone: song.isOnline ? MusicBadge.source(song.source) : BadgeTone.gray,
      ),
      if (quality != null)
        Tooltip(
          message: option == null
              ? quality
              : QualityPolicy.optionDetail(option, song) ?? option.detail,
          child: MusicBadge(quality, tone: MusicBadge.quality(quality)),
        ),
      if (cached != null)
        Tooltip(
          message: local.entries
              .map(
                (e) =>
                    '${AudioQuality.labelOf(e.key)} ${e.value == 'downloads' ? '本机已下载' : '本机已缓存'}',
              )
              .join(' · '),
          child: InkWell(
            onTap: cached == '已缓存'
                ? () => confirmClearSongCache(context, controller, song)
                : null,
            borderRadius: BorderRadius.circular(6),
            child: MusicBadge(
              cached,
              tone: cached == '已下载' ? BadgeTone.blue : BadgeTone.green,
            ),
          ),
        ),
    ];
    if (!showSinger) {
      return Wrap(
        spacing: 8,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: badges,
      );
    }
    final singer = Text(
      song.singer,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: lxMuted,
        fontSize: 12,
        height: 1.3,
        leadingDistribution: TextLeadingDistribution.even,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(10) > 13 ||
            constraints.maxWidth < 150) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 4, runSpacing: 3, children: badges),
              const SizedBox(height: 3),
              singer,
            ],
          );
        }
        return Row(
          children: [
            for (final badge in badges) ...[badge, const SizedBox(width: 4)],
            const SizedBox(width: 2),
            Expanded(child: singer),
          ],
        );
      },
    );
  }
}
