import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'player_controller.dart';
import 'quality.dart';

void showQuality(BuildContext context, PlayerController player) {
  if (player.current == null) return;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        key: const ValueKey('quality-sheet'),
        height: MediaQuery.sizeOf(context).height * .68,
        child: ListenableBuilder(
          listenable: player,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '音质',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (player.changingQuality || player.resolving)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '正在尝试${AudioQuality.labelOf(player.qualityTarget)}…',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else if (player.qualityNotice != null ||
                        player.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          player.qualityNotice ?? player.error!,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: player.qualityFailed || player.error != null
                                ? Theme.of(context).colorScheme.error
                                : lxGreen,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  children: [
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.refresh_rounded, size: 20),
                      title: const Text(
                        '重新尝试首选音质',
                        style: TextStyle(fontSize: 14),
                      ),
                      enabled: !player.resolving && !player.changingQuality,
                      onTap: player.retryPreferredQuality,
                    ),
                    if (player.knownQualityOptions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          '暂无已标注音质',
                          style: TextStyle(color: lxMuted, fontSize: 13),
                        ),
                      ),
                    for (final quality in player.knownQualityOptions)
                      _qualityTile(player, quality),
                    if (player.unverifiedQualityOptions.isNotEmpty)
                      ExpansionTile(
                        key: const ValueKey('unverified-quality-options'),
                        title: const Text(
                          '尝试其他音质',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          '可用性待确认',
                          style: TextStyle(fontSize: 11, color: lxMuted),
                        ),
                        children: [
                          for (final quality in player.unverifiedQualityOptions)
                            _qualityTile(player, quality),
                        ],
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
}

Widget _qualityTile(PlayerController player, AudioQuality quality) => ListTile(
  dense: true,
  title: Text(
    quality.label,
    style: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: player.reportedQuality == quality.id ? lxGreen : lxInk,
    ),
  ),
  subtitle: ['128k', '192k', '320k', 'flac', 'flac24bit'].contains(quality.id)
      ? Text(
          quality.detail,
          style: const TextStyle(fontSize: 11, color: lxMuted),
        )
      : null,
  trailing: player.reportedQuality == quality.id
      ? const Icon(Icons.check_rounded, color: lxGreen, size: 20)
      : player.preferredQuality == quality.id
      ? const Text('首选', style: TextStyle(color: lxMuted, fontSize: 11))
      : null,
  enabled: !player.resolving && !player.changingQuality,
  onTap: () => player.changeQuality(quality.id),
);
