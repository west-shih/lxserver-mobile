import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'page_jump_sheet.dart';

class ResultPagination extends StatelessWidget {
  const ResultPagination({
    super.key,
    required this.page,
    required this.pageCount,
    required this.hasMore,
    this.onPrevious,
    this.onNext,
    this.onJump,
    this.loadedPageCount = 1,
  });
  final int page, loadedPageCount;
  final int? pageCount;
  final bool hasMore;
  final VoidCallback? onPrevious, onNext;
  final ValueChanged<int>? onJump;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xFFE5EDE8))),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _button('上一页', Icons.chevron_left_rounded, onPrevious),
        Text(
          '第 ${page + 1}${pageCount == null ? '' : ' / $pageCount'} 页',
          style: const TextStyle(fontSize: 12, color: lxMuted),
        ),
        _button('下一页', Icons.chevron_right_rounded, onNext),
        SizedBox(
          height: 32,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: lxGreen,
              minimumSize: const Size(36, 32),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: Theme.of(context).textTheme.labelLarge!
                  .copyWith(fontSize: 12),
            ),
            onPressed: onJump == null || (pageCount ?? loadedPageCount) <= 1
                ? null
                : () async {
                    final target = await showPageJump(
                      context,
                      currentPage: page,
                      maxPage: pageCount ?? loadedPageCount,
                      totalKnown: pageCount != null,
                    );
                    if (context.mounted && target != null) onJump!(target);
                  },
            child: const Text('跳页'),
          ),
        ),
      ],
    ),
  );

  Widget _button(String label, IconData icon, VoidCallback? action) =>
      IconButton(
        tooltip: label,
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(36, 32),
          fixedSize: const Size(36, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        visualDensity: VisualDensity.standard,
        onPressed: action,
        icon: Icon(icon),
      );
}
