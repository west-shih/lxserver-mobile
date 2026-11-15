import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../features/library/library_controller.dart';
import 'app_modal.dart';

/// The native default/试听 list remains in the library, but is not a
/// destination for explicit collection actions.
Future<MusicCollection?> pickCollection(
  BuildContext context,
  AppController controller, {
  required int songCount,
}) async {
  final session = controller.session;
  if (session == null) return null;
  await controller.library.load(session);
  if (!context.mounted || controller.session != session) return null;
  final error = controller.library.error;
  final targets = controller.library.collections
      .where((collection) => collection.id != 'default')
      .toList();
  if (error != null || targets.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error ?? '暂无可收藏的歌单，请刷新后重试')));
    return null;
  }
  return showAppSheet<MusicCollection>(
    context: context,
    title: '收藏到歌单',
    subtitle: '已选 $songCount 首，重复歌曲不会重复添加',
    builder: (sheet) => SizedBox(
      height: modalPanelHeight(
        sheet,
        targets.length * 64.0,
        minHeight: 64,
        maxFraction: .6,
      ),
      child: ListView(
        children: [
          for (final collection in targets)
            ListTile(
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
  );
}
