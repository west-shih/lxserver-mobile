import '../../app/browse_navigation.dart';

import 'package:flutter/material.dart';

import '../../shared/app_modal.dart';

import '../../app/controller.dart';
import '../../core/lx_api.dart';
import 'collection_screen.dart';
import 'library_controller.dart';

class CollectionMenu extends StatefulWidget {
  const CollectionMenu({
    super.key,
    required this.controller,
    required this.collection,
    this.onChanged,
  });
  final AppController controller;
  final MusicCollection collection;
  final ValueChanged<String>? onChanged;
  @override
  State<CollectionMenu> createState() => _CollectionMenuState();
}

class _CollectionMenuState extends State<CollectionMenu> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller.library,
    builder: (context, _) => PopupMenuButton<String>(
      tooltip: '歌单操作',
      enabled: !_busy && !widget.controller.library.mutating,
      icon: _busy
          ? const Icon(Icons.hourglass_empty_rounded, size: 20)
          : const Icon(Icons.more_horiz_rounded),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('重命名')),
        if (widget.collection.isLinked) ...[
          const PopupMenuItem(value: 'refresh', child: Text('刷新同步')),
          const PopupMenuItem(value: 'open', child: Text('打开原始歌单')),
        ],
        const PopupMenuItem(value: 'delete', child: Text('删除歌单')),
      ],
      onSelected: (action) async {
        setState(() => _busy = true);
        final changed = await performCollectionAction(
          context,
          widget.controller,
          widget.collection,
          action,
        );
        if (!mounted) return;
        setState(() => _busy = false);
        if (changed) widget.onChanged?.call(action);
      },
    ),
  );
}

Future<bool> performCollectionAction(
  BuildContext context,
  AppController c,
  MusicCollection collection,
  String action,
) async {
  final session = c.session;
  if (session == null) return false;
  final summary = collection.isLinked
      ? c.discovery.originalSummary(collection)
      : null;
  if (action == 'open') {
    if (summary == null) return false;
    await Navigator.push(
      context,
      browseRoute(
        CollectionScreen(
          controller: c,
          collection: MusicCollection(
            summary.id,
            summary.name,
            [],
            image: summary.image,
            source: summary.source,
            metadata: summary.metadata,
          ),
          fetchPage: (page) => c.discovery.detail(session, summary, page),
        ),
      ),
    );
    return false;
  }
  String? nextName;
  if (action == 'rename') {
    var draft = collection.name;
    final form = GlobalKey<FormState>();
    nextName = await showAppSheet<String>(
      context: context,
      title: '重命名歌单',
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: draft,
                style: modalInputTextStyle,
                autofocus: true,
                decoration: const InputDecoration(labelText: '歌单名称'),
                onChanged: (value) => draft = value,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入歌单名称' : null,
                onFieldSubmitted: (value) {
                  if (form.currentState!.validate()) {
                    Navigator.pop(sheet, value.trim());
                  }
                },
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (form.currentState!.validate()) {
                      Navigator.pop(sheet, draft.trim());
                    }
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (nextName == null ||
        nextName == collection.name ||
        !context.mounted ||
        c.session != session) {
      return false;
    }
  }
  final confirmed = action == 'rename'
      ? true
      : await showAppDialog<bool>(
          context: context,
          dangerous: action == 'delete',
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(action == 'delete' ? '删除歌单？' : '刷新同步歌单？'),
            content: Text(
              action == 'delete'
                  ? '将从服务器删除「${collection.name}」，其他设备也会受到影响。本机下载保留。'
                  : '用原平台最新歌曲替换「${collection.name}」的内容。请避免同时在其他设备编辑歌单。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认'),
              ),
            ],
          ),
        );
  if (confirmed != true || !context.mounted || c.session != session) {
    return false;
  }
  try {
    SongBatch? refreshed;
    if (action == 'refresh') {
      if (summary == null) throw const ApiFailure('该歌单没有可同步的原平台来源');
      refreshed = await c.api.refreshBrowse(
        () => c.library.remoteSongs(session, summary, c.discovery.detail),
      );
    }
    if (c.session != session) return false;
    await c.library.changeCollection(
      session,
      collection,
      replacement: refreshed?.songs,
      image: refreshed?.image,
      name: nextName,
    );
    if (context.mounted && c.session == session) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('歌单已更新')));
    }
    return c.session == session;
  } catch (e) {
    if (e is ApiFailure && e.unauthorized) c.expire();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiFailure ? e.message : '操作失败，请刷新后重试')),
      );
    }
  }
  return false;
}

Future<void> showCollectionActions(
  BuildContext context,
  AppController controller,
  MusicCollection collection,
) async {
  if (collection.isSystem || controller.library.mutating) return;
  final action = await showAppSheet<String>(
    context: context,
    title: collection.name,
    showDragHandle: true,
    builder: (context) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('重命名'),
            onTap: () => Navigator.pop(context, 'rename'),
          ),
          if (collection.isLinked) ...[
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('刷新同步'),
              onTap: () => Navigator.pop(context, 'refresh'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('打开原始歌单'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('删除歌单', style: TextStyle(color: modalDanger)),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (action != null && context.mounted) {
    await performCollectionAction(context, controller, collection, action);
  }
}
