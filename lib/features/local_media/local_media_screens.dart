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
          actions: [
            IconButton(
              tooltip: '缓存设置',
              icon: const Icon(Icons.storage_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CacheSettingsScreen(controller: controller),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '下载任务'),
              Tab(text: '已下载'),
            ],
          ),
        ),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: media,
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

class CacheSettingsScreen extends StatelessWidget {
  const CacheSettingsScreen({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final media = controller.localMedia;
    return Scaffold(
      appBar: AppBar(title: const Text('缓存与存储')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: media,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                audioBytes(media.cacheBytes + media.cacheInProgressBytes),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text('本机音频缓存', style: TextStyle(color: lxMuted)),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动缓存上限'),
                trailing: DropdownButton<int>(
                  borderRadius: BorderRadius.circular(12),
                  dropdownColor: Colors.white,
                  value: media.cacheLimitMb,
                  items: [
                    for (final value in [0, 256, 512, 1024, 2048])
                      DropdownMenuItem(
                        value: value,
                        child: Text(
                          value == 0
                              ? '关闭'
                              : value >= 1024
                              ? '${value ~/ 1024} GB'
                              : '$value MB',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) media.setCacheLimit(value);
                  },
                ),
              ),
              const Text(
                '按最近使用自动清理。主动下载单独保存，不计入缓存上限，也不会随清缓存删除。',
                style: TextStyle(color: lxMuted, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.cleaning_services_rounded),
                label: const Text('清空音频缓存'),
                onPressed: () async {
                  try {
                    await media.clearCache();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('缓存已清理，当前播放占用的文件在切歌后清理')),
                      );
                    }
                  } on ApiFailure catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
              ),
              const Divider(height: 36),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('本机下载'),
                subtitle: Text(
                  '${media.downloads.length} 个文件 · ${audioBytes(media.downloads.fold(0, (n, f) => n + f.bytes))}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DownloadsScreen(controller: controller),
                  ),
                ),
              ),
              if (media.storageError != null)
                Text(
                  media.storageError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
