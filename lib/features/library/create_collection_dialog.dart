import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/lx_api.dart';
import '../../shared/app_modal.dart';

Future<bool> showCreateCollection(
  BuildContext context,
  AppController controller, {
  List<Song> songs = const [],
}) async {
  final session = controller.session;
  if (session == null || controller.offlineMode) return false;
  final library = controller.library;
  final id = library.newCollectionId();
  var name = '';
  var saving = false;
  String? error;
  final savedName = await showAppDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> submit() async {
          if (saving || controller.session != session) return;
          if (name.trim().isEmpty) {
            setState(() => error = '歌单名称不能为空');
            return;
          }
          setState(() {
            saving = true;
            error = null;
          });
          try {
            final savedName = await library.createCollection(
              session,
              id: id,
              name: name,
              songs: songs,
            );
            if (dialog.mounted) Navigator.pop(dialog, savedName);
          } catch (failure) {
            if (!dialog.mounted) return;
            setState(() {
              saving = false;
              error = failure is ApiFailure ? failure.message : '创建失败，请重试';
            });
          }
        }

        return PopScope(
          canPop: !saving,
          child: AlertDialog(
            scrollable: true,
            title: const Text('新建歌单'),
            content: TextField(
              autofocus: true,
              enabled: !saving,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: '歌单名称', errorText: error),
              onChanged: (value) {
                name = value;
                if (error != null) setState(() => error = null);
              },
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialog),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: saving ? null : submit,
                child: Text(songs.isEmpty ? '创建' : '创建并加入'),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (savedName == null || !context.mounted || controller.session != session) {
    return false;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        library.error ??
            (songs.isEmpty ? '已创建「$savedName」' : '已收藏到「$savedName」'),
      ),
    ),
  );
  return true;
}
