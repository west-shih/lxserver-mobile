import '../../app/browse_navigation.dart';

import 'package:flutter/material.dart';

import '../../shared/app_modal.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../local_media/local_media_screens.dart';
import '../player/quality.dart';

void showPreferredQuality(BuildContext context, AppController controller) {
  showAppSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHeader(
          title: '首选音质',
          subtitle: '用于后续播放；当前歌曲保持不变，不可用时自动降低音质',
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final quality in AudioQuality.values)
                ListTile(
                  selected: controller.player.preferredQuality == quality.id,
                  title: Text(quality.label),
                  subtitle: Text(quality.detail),
                  trailing: controller.player.preferredQuality == quality.id
                      ? const Icon(Icons.check_rounded, color: lxGreen)
                      : null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    try {
                      await controller.player.setPreferredQuality(quality.id);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('首选音质已修改，但未能保存到本机')),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class PersonalCenterScreen extends StatelessWidget {
  const PersonalCenterScreen({super.key, required this.controller});
  final AppController controller;

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      dangerous: true,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('退出当前账号？'),
        content: const Text('播放将停止，本机下载保留。你可以重新登录或切换服务器。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.logout();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.localMedia]),
    builder: (context, _) {
      final session = controller.session;
      if (session == null) return const SizedBox.shrink();
      final media = controller.localMedia;
      return Scaffold(
        appBar: AppBar(title: const Text('个人中心')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0C9979), Color(0xFF155957)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: const Color(0x33FFFFFF),
                        child: Text(
                          session.username.characters.first.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: '退出登录 / 切换服务器',
                        child: TextButton.icon(
                          onPressed: () => _logout(context),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0x22FFFFFF),
                            minimumSize: const Size(48, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          icon: const Icon(Icons.logout_rounded, size: 16),
                          label: Text(
                            controller.offlineMode ? '离线模式' : '已登录',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    session.username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    session.server.toString(),
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _StorageCard(
                    title: '本机下载',
                    value: '${media.downloads.length} 首',
                    detail: audioBytes(
                      media.downloads.fold<int>(
                        0,
                        (sum, file) => sum + file.bytes,
                      ),
                    ),
                    icon: Icons.download_done_rounded,
                    color: const Color(0xFF3867C8),
                    onTap: () => Navigator.push(
                      context,
                      browseRoute(DownloadsScreen(controller: controller)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BrowseCacheUsage(
                    controller: controller,
                    builder: (context, browseBytes, refresh) => _StorageCard(
                      title: '缓存设置',
                      value: browseBytes == null
                          ? '统计中…'
                          : audioBytes(
                              media.cacheBytes +
                                  media.cacheInProgressBytes +
                                  browseBytes +
                                  controller.player.cache.storageBytes,
                            ),
                      detail: '音频、浏览与播放偏好',
                      icon: Icons.storage_rounded,
                      color: lxGreen,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          browseRoute(
                            CacheSettingsScreen(controller: controller),
                          ),
                        );
                        refresh();
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    key: const ValueKey('collection-browsing-setting'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    minTileHeight: 56,
                    titleAlignment: ListTileTitleAlignment.center,
                    leading: const Icon(
                      Icons.auto_stories_outlined,
                      color: lxGreen,
                    ),
                    title: const Text('列表浏览'),
                    trailing: DropdownButton<int>(
                      key: const ValueKey('collection-page-size-setting'),
                      borderRadius: BorderRadius.circular(12),
                      dropdownColor: Colors.white,
                      value: controller.pagedCollections
                          ? controller.collectionPageSize
                          : 0,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(fontSize: 14, color: lxInk),
                      selectedItemBuilder: (_) => [
                        for (final label in [
                          '连续列表',
                          for (final size in AppController.collectionPageSizes)
                            '每页 $size 项',
                        ])
                          Container(
                            width: 110,
                            alignment: Alignment.centerRight,
                            child: Text(label),
                          ),
                      ],
                      items: [
                        const DropdownMenuItem(value: 0, child: Text('连续列表')),
                        for (final size in AppController.collectionPageSizes)
                          DropdownMenuItem(
                            value: size,
                            child: Text('每页 $size 项'),
                          ),
                      ],
                      onChanged: (value) async {
                        if (value == null) return;
                        try {
                          if (value != 0) {
                            await controller.setCollectionPageSize(value);
                          }
                          await controller.setPagedCollections(value != 0);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('设置保存失败，请重试')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    minTileHeight: 56,
                    titleAlignment: ListTileTitleAlignment.center,
                    leading: const Icon(
                      Icons.high_quality_rounded,
                      color: lxGreen,
                    ),
                    title: const Text('首选音质'),
                    trailing: ListenableBuilder(
                      listenable: controller.player,
                      builder: (_, _) => SizedBox(
                        height: 48,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AudioQuality.labelOf(
                                controller.player.preferredQuality,
                              ),
                              style: const TextStyle(
                                fontSize: 14,
                                color: lxInk,
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 24,
                              color: Colors.grey.shade700,
                            ),
                          ],
                        ),
                      ),
                    ),
                    onTap: () => showPreferredQuality(context, controller),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title, value, detail;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: .07),
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 18),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(color: lxMuted, fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}
