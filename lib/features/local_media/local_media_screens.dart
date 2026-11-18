import '../../core/browse_cache.dart';

import 'package:flutter/material.dart';

import '../../shared/app_modal.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/lx_api.dart';
import '../../shared/song_art.dart';
import '../../shared/music_badge.dart';
import '../player/quality.dart';
import 'local_media_controller.dart';

String audioBytes(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
    : bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(0)} KB';

void showDownloadQuality(BuildContext context, AppController c, Song song) {
  final verified = [
    ...c.serverFiles.folders(song).keys,
    ...c.localMedia.folders(song).keys,
  ];
  final known = QualityPolicy.knownOptions(song, verified: verified);
  final unknown = QualityPolicy.unverifiedOptions(song, verified: verified);
  final options = [...known, ...unknown];
  String? selected =
      QualityPolicy.attempts(
        song,
        c.player.preferredQuality,
      ).where((id) => options.any((q) => q.id == id)).firstOrNull ??
      options.firstOrNull?.id;
  showAppSheet<void>(
    context: context,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, update) {
        Widget option(AudioQuality q) => ListTile(
          key: ValueKey('download-quality-${q.id}'),
          selected: selected == q.id,
          title: Text(q.label),
          trailing: selected == q.id
              ? const Icon(Icons.check_rounded, color: lxGreen)
              : null,
          onTap: () => update(() => selected = q.id),
        );
        return SizedBox(
          height: modalPanelHeight(
            sheet,
            124 + (known.length + (unknown.isEmpty ? 0 : 1)) * 60.0,
            minHeight: 220,
          ),
          child: Column(
            children: [
              const SheetHeader(title: '下载音质'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final q in known) option(q),
                    if (unknown.isNotEmpty)
                      ExpansionTile(
                        initiallyExpanded: unknown.any((q) => q.id == selected),
                        title: const Text('其他音质'),
                        subtitle: const Text('可用性待确认'),
                        children: [for (final q in unknown) option(q)],
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: selected == null
                        ? null
                        : () {
                            Navigator.pop(sheet);
                            downloadSong(context, c, song, quality: selected);
                          },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('下载'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> downloadSong(
  BuildContext context,
  AppController c,
  Song song, {
  String? quality,
  bool replace = false,
}) async {
  final session = c.session;
  if (session == null) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await c.localMedia.enqueue(
      session,
      song,
      quality ?? c.player.preferredQuality,
      replace: replace,
    );
    messenger.showSnackBar(const SnackBar(content: Text('已加入本机下载列表')));
  } on ApiFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<void> confirmClearSongCache(
  BuildContext context,
  AppController c,
  Song song, {
  String? quality,
}) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    dangerous: true,
    builder: (dialog) => AlertDialog(
      scrollable: true,
      title: const Text('清除本机缓存？'),
      content: const Text('已下载的文件会保留。正在播放的缓存会在切歌后清除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('清除'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final deferred = await c.localMedia.clearSongCache(song, quality: quality);
    messenger.showSnackBar(
      SnackBar(content: Text(deferred ? '正在播放的缓存将在切歌后清除' : '本机缓存已清除')),
    );
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('缓存未能清除，请重试')));
  }
}

void showFileDetails(BuildContext context, AppController c, Song song) {
  c.refreshServerFiles();
  showAppSheet<void>(
    context: context,
    title: '存储',
    closeLabel: '关闭',
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: ListenableBuilder(
          listenable: Listenable.merge([c.localMedia, c.serverFiles]),
          builder: (context, _) {
            final local = c.localMedia.folders(song);
            final server = c.serverFiles.folders(song);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                const Text('本机', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (local.isEmpty)
                  const ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('没有本机音频文件', style: TextStyle(color: lxMuted)),
                  ),
                for (final e in local.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AudioQuality.labelOf(e.key)),
                    subtitle: Text(
                      c.localMedia.pendingRemoval(song, e.key)
                          ? '切歌后清除'
                          : audioBytes(
                              c.localMedia.fileFor(song, e.key)?.bytes ?? 0,
                            ),
                      style: const TextStyle(color: lxMuted, fontSize: 12),
                    ),
                    trailing: MusicBadge(
                      e.value == 'downloads' ? '已下载' : '已缓存',
                      tone: e.value == 'downloads'
                          ? BadgeTone.blue
                          : BadgeTone.green,
                    ),
                    onTap: e.value == 'cache'
                        ? () => confirmClearSongCache(
                            context,
                            c,
                            song,
                            quality: e.key,
                          )
                        : null,
                  ),
                const Divider(height: 32),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'LXServer',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新服务器状态',
                      onPressed: () => c.refreshServerFiles(force: true),
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ],
                ),
                if (!c.serverFiles.available)
                  const ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '服务器文件状态暂不可用',
                      style: TextStyle(color: lxMuted),
                    ),
                  )
                else if (server.isEmpty)
                  const ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('未发现服务器音频文件', style: TextStyle(color: lxMuted)),
                  ),
                for (final e in server.entries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(AudioQuality.labelOf(e.key)),
                    trailing: MusicBadge(
                      e.value == 'music' ? '已下载' : '已缓存',
                      tone: e.value == 'music'
                          ? BadgeTone.blue
                          : BadgeTone.green,
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  '服务器文件在网页端管理',
                  style: TextStyle(color: lxMuted, fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final media = controller.localMedia;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('本机下载'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '下载任务'),
              Tab(text: '已下载'),
            ],
          ),
        ),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([media, controller]),
            builder: (context, _) => TabBarView(
              children: [
                media.jobs.isEmpty
                    ? const Center(
                        child: Text('暂无下载任务', style: TextStyle(color: lxMuted)),
                      )
                    : ListView(
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              '下载在应用运行时进行；暂停或中断后继续会重新下载当前歌曲。',
                              style: TextStyle(color: lxMuted, fontSize: 12),
                            ),
                          ),
                          for (final job in media.jobs)
                            _DownloadTile(job: job, media: media),
                        ],
                      ),
                media.downloads.isEmpty
                    ? const Center(
                        child: Text(
                          '下载的歌曲会保存在手机，可离线播放',
                          style: TextStyle(color: lxMuted),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final file in media.downloads)
                            ListTile(
                              leading: SongArt(
                                url: file.song.image,
                                localPath: media.artworkPath(file.song),
                                size: 44,
                              ),
                              title: Text(
                                file.song.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  MusicBadge(
                                    file.song.sourceLabel,
                                    tone: file.song.isOnline
                                        ? MusicBadge.source(file.song.source)
                                        : BadgeTone.gray,
                                  ),
                                  if (file.valid)
                                    MusicBadge(
                                      AudioQuality.labelOf(
                                        file.reportedQuality,
                                      ),
                                      tone: MusicBadge.quality(
                                        AudioQuality.labelOf(
                                          file.reportedQuality,
                                        ),
                                      ),
                                    )
                                  else
                                    const Text('文件需重新下载'),
                                  Text(
                                    audioBytes(file.bytes),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: lxMuted,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                final s = controller.session;
                                if (s != null) {
                                  controller.player.play(
                                    s,
                                    file.song,
                                    quality: file.quality,
                                  );
                                }
                              },
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  try {
                                    if (value == 'delete') {
                                      await media.deleteDownload(file);
                                    } else {
                                      await downloadSong(
                                        context,
                                        controller,
                                        file.song,
                                        quality: file.quality,
                                        replace: true,
                                      );
                                    }
                                  } on ApiFailure catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(content: Text(e.message)),
                                          );
                                    }
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'retry',
                                    child: Text('重新下载'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除本机下载'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.job, required this.media});
  final DownloadJob job;
  final LocalMediaController media;
  @override
  Widget build(BuildContext context) {
    final busy = [
      DownloadState.queued,
      DownloadState.resolving,
      DownloadState.downloading,
    ].contains(job.state);
    final state = switch (job.state) {
      DownloadState.queued => '等待中',
      DownloadState.resolving => '解析中',
      DownloadState.downloading => '下载中',
      DownloadState.paused => '已暂停',
      DownloadState.failed => '失败',
      DownloadState.completed => '已完成',
    };
    return ListTile(
      title: Text(job.song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: MusicBadge(
              job.song.sourceLabel,
              tone: job.song.isOnline
                  ? MusicBadge.source(job.song.source)
                  : BadgeTone.gray,
            ),
          ),
          Text(
            '$state · ${AudioQuality.labelOf(job.actualQuality ?? job.preference)} · ${audioBytes(job.received)}${job.total == null ? '' : ' / ${audioBytes(job.total!)}'}',
            style: const TextStyle(fontSize: 12),
          ),
          if (job.state == DownloadState.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: job.total == null || job.total == 0
                    ? null
                    : job.received / job.total!,
              ),
            ),
          if (job.error != null)
            Text(
              job.error!,
              style: TextStyle(
                fontSize: 11,
                color: job.state == DownloadState.failed
                    ? Theme.of(context).colorScheme.error
                    : lxMuted,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: busy ? '暂停下载' : '继续下载',
            onPressed: () => busy ? media.pause(job) : media.resume(job),
            icon: Icon(busy ? Icons.pause_rounded : Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '取消下载任务',
            onPressed: () => media.cancel(job),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// Measures browsing files off the build path and refreshes after settings changes.
class BrowseCacheUsage extends StatefulWidget {
  const BrowseCacheUsage({
    super.key,
    required this.controller,
    required this.builder,
  });
  final AppController controller;
  final Widget Function(BuildContext, int?, VoidCallback) builder;
  @override
  State<BrowseCacheUsage> createState() => _BrowseCacheUsageState();
}

class _BrowseCacheUsageState extends State<BrowseCacheUsage> {
  int? bytes;
  int version = 0;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didUpdateWidget(covariant BrowseCacheUsage oldWidget) {
    super.didUpdateWidget(oldWidget);
    refresh();
  }

  Future<void> refresh() async {
    final current = ++version;
    final value = await widget.controller.readBrowseCacheBytes();
    if (mounted && current == version) setState(() => bytes = value);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, bytes, refresh);
}

class CacheSettingsScreen extends StatelessWidget {
  const CacheSettingsScreen({super.key, required this.controller});
  final AppController controller;

  Future<void> _resetPreferences(
    BuildContext context,
    VoidCallback refresh,
  ) async {
    final session = controller.session;
    if (session == null) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('重置播放偏好？'),
        content: const Text(
          '清除当前账号在此服务器记住的歌曲音质档位。下次播放将按默认音质选择；当前播放、默认音质、队列和本机文件保持不变。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || controller.session != session) return;
    await controller.player.cache.resetTrackChoices(session);
    controller.player.refreshQualityAvailability();
    refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已重置播放偏好')));
    }
  }

  Future<void> _clear(
    BuildContext context,
    bool audio,
    VoidCallback refresh,
  ) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      dangerous: true,
      builder: (dialog) => AlertDialog(
        title: Text(audio ? '清理音频缓存？' : '清理浏览缓存？'),
        content: Text(
          audio
              ? '清理播放时自动保存的音频和歌词。主动下载的文件会保留，包括下载歌词。当前播放占用的缓存将在切歌后清理。'
              : '清理搜索结果、封面和评论等浏览缓存。当前页面已显示的内容会保留，音频缓存、下载和播放偏好不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      if (audio) {
        await controller.localMedia.clearCache();
      } else {
        await controller.api.browseCache?.clear();
      }
      refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              audio ? '缓存已清理，当前播放占用的文件在切歌后清理' : '已清理浏览缓存，当前页面保留已显示内容',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('缓存未能清理，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = controller.localMedia;
    return Scaffold(
      appBar: AppBar(title: const Text('缓存设置')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([media, controller]),
          builder: (context, _) => BrowseCacheUsage(
            controller: controller,
            builder: (context, browseBytes, refresh) {
              final audio = media.cacheBytes + media.cacheInProgressBytes;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  const Text(
                    '缓存总占用',
                    style: TextStyle(color: lxMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    browseBytes == null
                        ? '统计中…'
                        : audioBytes(
                            audio +
                                browseBytes +
                                controller.player.cache.storageBytes,
                          ),
                    key: const ValueKey('cache-total-usage'),
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: lxInk,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _CacheCard(
                    title: '音频缓存',
                    icon: Icons.music_note_outlined,
                    usage: audioBytes(audio),
                    description:
                        '播放时自动保存音频和歌词，空间不足时优先清理最久未播放的缓存。主动下载的音频和歌词独立保留。',
                    capacityLabel: '自动缓存上限',
                    limit: media.cacheLimitMb,
                    limits: LocalMediaController.cacheLimitsMb,
                    onLimit: (value) async {
                      await media.setCacheLimit(value);
                      refresh();
                    },
                    clearLabel: '清空音频缓存',
                    onClear: () => _clear(context, true, refresh),
                  ),
                  const SizedBox(height: 16),
                  _CacheCard(
                    title: '浏览缓存',
                    icon: Icons.layers_outlined,
                    usage: browseBytes == null
                        ? '统计中…'
                        : audioBytes(browseBytes),
                    description: '保存封面、搜索结果和评论等浏览内容，让页面打开更快。',
                    capacityLabel: '浏览缓存容量',
                    limit: controller.browseLimitMb,
                    limits: BrowseCache.limitsMb,
                    onLimit: (value) async {
                      await controller.setBrowseLimit(value);
                      refresh();
                    },
                    clearLabel: '清理浏览缓存',
                    onClear: () => _clear(context, false, refresh),
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 6,
                      ),
                      leading: const _CacheIcon(Icons.tune_rounded),
                      minLeadingWidth: 40,
                      horizontalTitleGap: 12,
                      titleAlignment: ListTileTitleAlignment.center,
                      title: const _CacheTitle(
                        title: '播放偏好',
                        description: '记住每首歌成功使用的音质档位。',
                      ),
                      trailing: TextButton(
                        onPressed: () => _resetPreferences(context, refresh),
                        child: const Text('重置'),
                      ),
                    ),
                  ),
                  if (media.storageError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        media.storageError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CacheIcon extends StatelessWidget {
  const _CacheIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F7F1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, size: 22, color: lxGreen),
  );
}

class _CacheTitle extends StatelessWidget {
  const _CacheTitle({required this.title, required this.description});
  final String title, description;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      IconButton(
        tooltip: '$title说明',
        icon: const Icon(Icons.info_outline_rounded, size: 16, color: lxMuted),
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        visualDensity: VisualDensity.compact,
        onPressed: () => showAppDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(title),
            content: Text(description),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _CacheCard extends StatefulWidget {
  const _CacheCard({
    required this.title,
    required this.icon,
    required this.usage,
    required this.description,
    required this.capacityLabel,
    required this.limit,
    required this.limits,
    required this.onLimit,
    required this.clearLabel,
    required this.onClear,
  });
  final String title, usage, description, capacityLabel, clearLabel;
  final IconData icon;
  final int limit;
  final List<int> limits;
  final Future<void> Function(int) onLimit;
  final Future<void> Function() onClear;
  @override
  State<_CacheCard> createState() => _CacheCardState();
}

class _CacheCardState extends State<_CacheCard> {
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CacheIcon(widget.icon),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _CacheTitle(
                  title: widget.title,
                  description: widget.description,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Text(
                  widget.usage,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: lxInk,
                  ),
                ),
              ),
              IconButton(
                tooltip: widget.clearLabel,
                onPressed: busy ? null : () => run(widget.onClear),
                icon: const Icon(Icons.cleaning_services_outlined, size: 20),
                style: IconButton.styleFrom(
                  foregroundColor: lxGreen,
                  padding: const EdgeInsets.all(8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFEEF2EF)),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.capacityLabel,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              DropdownButton<int>(
                value: widget.limit,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                dropdownColor: Colors.white,
                style: const TextStyle(fontSize: 14, color: lxInk),
                selectedItemBuilder: (context) => [
                  for (final limit in widget.limits)
                    Container(
                      width:
                          70 * MediaQuery.textScalerOf(context).scale(14) / 14,
                      alignment: Alignment.centerRight,
                      child: Text(
                        limit >= 1024 ? '${limit ~/ 1024} GB' : '$limit MB',
                      ),
                    ),
                ],
                icon: const SizedBox(
                  width: 40,
                  child: Icon(Icons.arrow_drop_down, color: lxMuted, size: 20),
                ),
                items: [
                  for (final limit in widget.limits)
                    DropdownMenuItem(
                      value: limit,
                      child: Text(
                        limit == 0
                            ? '关闭'
                            : limit >= 1024
                            ? '${limit ~/ 1024} GB'
                            : '$limit MB',
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) run(() => widget.onLimit(value));
                      },
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
