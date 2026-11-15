import 'package:flutter/material.dart';

import '../core/lx_api.dart';

class PlatformFilters extends StatelessWidget {
  const PlatformFilters({
    super.key,
    required this.sources,
    required this.selected,
    required this.onSelected,
    this.scrollKey,
  });
  final List<MusicSource> sources;
  final MusicSource? selected;
  final ValueChanged<MusicSource> onSelected;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) => EqualFilterRow(
    labels: sources.map((v) => v.label).toList(),
    selectedIndex: selected == null ? -1 : sources.indexOf(selected!),
    onSelected: (index) => onSelected(sources[index]),
    scrollKey: scrollKey,
  );
}

/// Equal cells fill the row; large text can scroll without squeezing labels.
class EqualFilterRow extends StatelessWidget {
  const EqualFilterRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.scrollKey,
  });
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (labels.isEmpty) return const SizedBox(height: 44);
          const gap = 6.0;
          const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
          var minWidth = 0.0;
          for (final label in labels) {
            final painter = TextPainter(
              text: TextSpan(text: label, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout();
            final width = painter.width + 24;
            if (width > minWidth) minWidth = width;
            painter.dispose();
          }
          final available = constraints.maxWidth.isFinite
              ? (constraints.maxWidth - gap * (labels.length - 1)) /
                    labels.length
              : minWidth;
          final width = available < minWidth ? minWidth : available;
          return SingleChildScrollView(
            key: scrollKey,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  SizedBox(
                    width: width,
                    child: ChoiceChip(
                      label: SizedBox(
                        width: double.infinity,
                        child: Text(
                          labels[i],
                          textAlign: TextAlign.center,
                          maxLines: 1,
                        ),
                      ),
                      labelStyle: style,
                      labelPadding: EdgeInsets.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      selected: selectedIndex == i,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: onSelected == null
                          ? null
                          : (_) => onSelected!(i),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );
}
