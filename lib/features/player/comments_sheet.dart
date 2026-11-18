import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/artwork_image.dart';
import '../../core/lx_api.dart';
import '../../shared/app_modal.dart';
import '../../shared/result_pagination.dart';
import '../../shared/song_art.dart';
import 'comments_controller.dart';

void showComments(BuildContext context, AppController app, Song song) {
  if (app.session == null) return;
  showAppSheet<void>(
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
    pageSize: widget.app.collectionPageSize,
  );
  bool get _paged => widget.app.pagedCollections;
  bool get _hasMore => c.page < c.maxPage;

  void _loadNext() {
    if (!c.loading && _hasMore) {
      c.load(targetPage: c.page + 1, append: !_paged);
    }
  }

  Future<void> _refresh() => c.api.refreshBrowse(() => c.load(targetPage: 1));

  void _retryWithItems() {
    if (c.appendFailed) {
      _loadNext();
    } else {
      _refresh();
    }
  }

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
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .78,
    ),
    child: ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '歌曲评论',
            subtitle: '${widget.song.name} · ${widget.song.sourceLabel}',
            trailing: Tooltip(
              message: '关闭评论',
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ),
            subtitleTrailing: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    '${c.total} 条',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: lxMuted, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  borderRadius: BorderRadius.circular(12),
                  dropdownColor: Colors.white,
                  isDense: true,
                  value: c.type,
                  underline: const SizedBox(),
                  style: const TextStyle(color: lxInk, fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: 'hot', child: Text('最热评论')),
                    DropdownMenuItem(value: 'new', child: Text('最新评论')),
                  ],
                  onChanged: (type) {
                    if (type != null && type != c.type) c.load(category: type);
                  },
                ),
              ],
            ),
          ),
          Flexible(
            child: c.loading && c.items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      heightFactor: 1,
                      child: CircularProgressIndicator(),
                    ),
                  )
                : c.error != null && c.items.isEmpty
                ? Center(
                    heightFactor: 1,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c.error!),
                        TextButton(onPressed: c.load, child: const Text('重试')),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: NotificationListener<ScrollUpdateNotification>(
                      onNotification: (notification) {
                        if (!_paged &&
                            c.error == null &&
                            (notification.scrollDelta ?? 0) > 0 &&
                            notification.metrics.extentAfter < 240) {
                          _loadNext();
                        }
                        return false;
                      },
                      child: ListView.separated(
                        key: ValueKey((c.type, _paged ? c.page : 1)),
                        shrinkWrap: true,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        itemCount: c.items.isEmpty
                            ? 1
                            : c.items.length +
                                  ((!_paged && (_hasMore || c.loading)) ||
                                          c.error != null
                                      ? 1
                                      : 0),
                        separatorBuilder: (_, _) =>
                            const Divider(height: 32, color: Color(0xFFE5EDE8)),
                        itemBuilder: (_, i) {
                          if (c.items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('暂无评论')),
                            );
                          }
                          if (i < c.items.length) return _Comment(c.items[i]);
                          if (c.loading) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (c.error != null) {
                            return Column(
                              children: [
                                Text(c.error!),
                                TextButton(
                                  onPressed: _retryWithItems,
                                  child: const Text('重试'),
                                ),
                              ],
                            );
                          }
                          return TextButton(
                            onPressed: _loadNext,
                            child: const Text('加载更多'),
                          );
                        },
                      ),
                    ),
                  ),
          ),
          if (_paged)
            ResultPagination(
              page: c.page - 1,
              pageCount: c.sequentialOnly ? null : c.maxPage,
              loadedPageCount: c.loadedPageCount,
              hasMore: _hasMore,
              onPrevious: !c.loading && c.page > 1
                  ? () => c.load(targetPage: c.page - 1)
                  : null,
              onNext: c.loading || c.error != null || !_hasMore
                  ? null
                  : _loadNext,
              onJump: c.loading ? null : (page) => c.load(targetPage: page + 1),
            ),
        ],
      ),
    ),
  );
}

class _Comment extends StatelessWidget {
  const _Comment(this.data, {this.isReply = false});
  final Map<dynamic, dynamic> data;
  final bool isReply;
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
            if (_commentImageUrl(data['avatar']) case final url?)
              SongArt(
                url: url,
                size: 32,
                borderRadius: 16,
                placeholderIcon: Icons.person_outline,
              )
            else
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
          style: TextStyle(height: 1.65, fontSize: isReply ? 12 : 14),
        ),
        if (data['images'] case final List images)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final image in images)
                if (_commentImageUrl(image) case final url?) _CommentImage(url),
            ],
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
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _Comment(reply, isReply: true),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

String? _commentImageUrl(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  final url = text.startsWith('//') ? 'https:$text' : text;
  final uri = Uri.tryParse(url);
  return uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? url
      : null;
}

class _CommentImage extends StatelessWidget {
  const _CommentImage(this.url);
  final String url;

  @override
  Widget build(BuildContext context) {
    final image = ArtworkImage(url, headers: artworkHeaders(url));
    final pixels = (144 * MediaQuery.devicePixelRatioOf(context)).ceil();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Image(
        image: ResizeImage(image, width: pixels),
        width: 144,
        height: 108,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
        frameBuilder: (context, child, frame, _) {
          if (frame == null) return child;
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Material(
              child: InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => Dialog(
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        InteractiveViewer(child: Image(image: image)),
                        IconButton(
                          tooltip: '关闭图片',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}
