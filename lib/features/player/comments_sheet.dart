import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/lx_api.dart';
import 'comments_controller.dart';

void showComments(BuildContext context, AppController app, Song song) {
  if (app.session == null) return;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CommentsSheet(app: app, song: song),
  );
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.app, required this.song});
  final AppController app;
  final Song song;
  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  late final c = CommentsController(
    widget.app.api,
    widget.app.session!,
    widget.song,
    widget.app.expire,
  );
  @override
  void initState() {
    super.initState();
    c.load();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '歌曲评论',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.song.name} · ${widget.song.sourceLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: lxMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭评论',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (final type in ['hot', 'new'])
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ChoiceChip(
                        label: Text(type == 'hot' ? '最热评论' : '最新评论'),
                        selected: c.type == type,
                        showCheckmark: false,
                        onSelected: (_) => c.load(category: type),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '${c.total}',
                    style: const TextStyle(color: lxMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: c.loading
                  ? const Center(child: CircularProgressIndicator())
                  : c.error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(c.error!),
                          TextButton(
                            onPressed: c.load,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => c.load(targetPage: 1),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        itemCount: c.items.isEmpty ? 1 : c.items.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 32, color: Color(0xFFE5EDE8)),
                        itemBuilder: (_, i) => c.items.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: Text(
                                    '暂无评论',
                                    style: TextStyle(color: lxMuted),
                                  ),
                                ),
                              )
                            : _Comment(c.items[i]),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: '上一页评论',
                    onPressed: !c.loading && c.page > 1
                        ? () => c.load(targetPage: c.page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(
                    '${c.page} / ${c.maxPage}',
                    style: const TextStyle(color: lxMuted, fontSize: 12),
                  ),
                  IconButton(
                    tooltip: '下一页评论',
                    onPressed:
                        !c.loading && c.error == null && c.page < c.maxPage
                        ? () => c.load(targetPage: c.page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Comment extends StatelessWidget {
  const _Comment(this.data);
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final name = '${data['userName'] ?? '听友'}';
    final replies = (data['reply'] is List ? data['reply'] as List : [])
        .whereType<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFE0F3E9),
              child: Text(
                name.isEmpty ? '♪' : name.characters.first,
                style: const TextStyle(color: lxGreen, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.thumb_up_outlined, size: 14, color: lxMuted),
            const SizedBox(width: 5),
            Text(
              '${data['likedCount'] ?? 0}',
              style: const TextStyle(color: lxMuted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${data['text'] ?? ''}',
          style: const TextStyle(height: 1.65, fontSize: 14),
        ),
        if (data['timeStr'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${data['timeStr']}',
              style: const TextStyle(color: lxMuted, fontSize: 11),
            ),
          ),
        if (replies.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5F2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final reply in replies)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '${reply['userName'] ?? '听友'}：${reply['text'] ?? ''}',
                      style: const TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
