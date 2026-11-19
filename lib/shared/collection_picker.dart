import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../core/lx_api.dart';
import '../features/library/create_collection_dialog.dart';
import '../features/library/library_controller.dart';
import 'app_modal.dart';

/// The native default/试听 list remains in the library, but is not a
/// destination for explicit collection actions.
Future<MusicCollection?> pickCollection(
  BuildContext context,
  AppController controller, {
  required List<Song> songs,
}) async {
  final session = controller.session;
  if (session == null) return null;
  await controller.library.load(session);
  if (!context.mounted || controller.session != session) return null;
  final error = controller.library.error;
  final targets = controller.library.collections
      .where((collection) => collection.id != 'default')
      .toList();
  return showAppSheet<MusicCollection>(
    context: context,
    title: '收藏到歌单',
    subtitle: '已选 ${songs.length} 首，重复歌曲不会重复添加',
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.add_rounded),
          title: const Text('新建歌单'),
          enabled: !controller.offlineMode,
          onTap: () async {
            if (controller.session != session || controller.offlineMode) return;
            final created = await showCreateCollection(
              sheet,
              controller,
              songs: songs,
            );
            if (created && sheet.mounted) Navigator.pop(sheet);
          },
        ),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error))
        else
          Flexible(
            child: ListView(
              primary: false,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final collection in targets)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      collection.id == 'love'
                          ? Icons.favorite_outline_rounded
                          : Icons.queue_music_rounded,
                    ),
                    title: Text(
                      collection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${collection.songs.length} 首'),
                    onTap: () => Navigator.pop(sheet, collection),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
