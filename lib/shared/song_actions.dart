import 'package:flutter/material.dart';

import 'app_modal.dart';

import '../app/controller.dart';
import '../core/lx_api.dart';
import '../features/player/quality_sheet.dart';
import 'song_art.dart';
import '../features/local_media/local_media_screens.dart';

void showSongActions(
  BuildContext context,
  AppController controller,
  Song song, {
  List<Song>? queue,
  bool fromPlayer = false,
}) {
  final origin = context;
  final messenger = ScaffoldMessenger.of(context);
  showAppSheet<void>(
    context: context,
    title: '歌曲操作',
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: SongArt(url: song.image),
              title: Text(
                song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(song.singer),
            ),
            if (!fromPlayer)
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('立即播放'),
                onTap: () {
                  Navigator.pop(context);
                  final session = controller.session;
                  if (session != null) {
                    controller.player.play(session, song, songs: queue);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('加入播放队列'),
              onTap: () {
                Navigator.pop(context);
                final session = controller.session;
                if (session != null) {
                  controller.player.enqueue(session, song);
                }
                messenger.showSnackBar(
                  const SnackBar(content: Text('已加入播放队列')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('下载到手机'),
              onTap: () {
                Navigator.pop(context);
                showDownloadQuality(origin, controller, song);
              },
            ),
            if (fromPlayer)
              ListTile(
                leading: const Icon(Icons.music_note_rounded),
                title: const Text('音质选择'),
                onTap: () {
                  Navigator.pop(context);
                  if (controller.player.current?.id == song.id) {
                    showQuality(origin, controller.player);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('信息'),
              onTap: () {
                Navigator.pop(context);
                showFileDetails(origin, controller, song);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}
