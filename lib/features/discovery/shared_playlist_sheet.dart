import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/browse_navigation.dart';
import '../../core/lx_api.dart';
import '../../shared/app_modal.dart';
import '../library/collection_screen.dart';
import '../library/library_controller.dart';

import 'discovery_controller.dart';

Future<void> showSharedPlaylist(BuildContext context, AppController app) async {
  final summary = await showAppSheet<PlaylistSummary>(
    context: context,
    title: '打开分享的歌单',
    builder: (_) => _SharedPlaylistForm(app: app),
  );
  if (summary == null || !context.mounted || app.session == null) return;
  final session = app.session!;
  await Navigator.push(
    context,
    browseRoute(
      CollectionScreen(
        controller: app,
        collection: MusicCollection(
          summary.id,
          summary.name,
          [],
          source: summary.source,
          image: summary.image,
          metadata: summary.metadata,
        ),
        fetchPage: (page) => app.discovery.detail(session, summary, page),
      ),
    ),
  );
}

class _SharedPlaylistForm extends StatefulWidget {
  const _SharedPlaylistForm({required this.app});
  final AppController app;
  @override
  State<_SharedPlaylistForm> createState() => _SharedPlaylistFormState();
}

class _SharedPlaylistFormState extends State<_SharedPlaylistForm> {
  final input = TextEditingController();
  MusicSource? source;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final sources = widget.app.availableSources;
    final current = widget.app.discovery.source;
    source = sources.contains(current) ? current : sources.firstOrNull;
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> open() async {
    final session = widget.app.session;
    if (busy || session == null || source == null) return;
    final value = input.text.trim();
    if (value.isEmpty) {
      setState(() => error = '请输入歌单链接或歌单 ID（酷狗填写酷狗码）');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final summary = await widget.app.discovery.openShared(
        session,
        source!,
        value,
      );
      if (!mounted || widget.app.session != session) return;
      Navigator.pop(context, summary);
    } on ApiFailure catch (e) {
      if (e.unauthorized) widget.app.expire();
      if (mounted) {
        setState(
          () => error = source == MusicSource.kg
              ? '酷狗歌单打开失败。请使用普通版分享链接或酷狗码，确认来源一致后重试。${e.message}'
              : e.message,
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = '歌单打开失败，请检查来源和链接后重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<MusicSource>(
          initialValue: source,
          style: modalInputTextStyle,
          decoration: const InputDecoration(labelText: '歌单来源'),
          items: widget.app.availableSources
              .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
              .toList(),
          onChanged: busy
              ? null
              : (value) => setState(() {
                  source = value;
                  error = null;
                }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: input,
          style: modalInputTextStyle,
          enabled: !busy,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '输入歌单链接或歌单 ID'),
          onSubmitted: (_) => open(),
        ),
        const SizedBox(height: 16),
        const Text(
          '请选择与链接一致的来源，不支持跨源打开。\n酷狗请用普通版分享链接或酷狗码，不支持歌单 ID 或概念版链接。\n网易「我喜欢」歌单需要 Token，能否打开取决于服务端配置。\n打开后可在详情页收藏，不会自动导入。',
          style: modalSupportingTextStyle,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy || source == null ? null : open,
          child: Text(busy ? '正在打开…' : '立即打开'),
        ),
      ],
    ),
  );
}
