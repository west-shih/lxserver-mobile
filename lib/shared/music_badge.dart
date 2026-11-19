import 'package:flutter/material.dart';

import '../core/lx_api.dart';

enum BadgeTone { blue, yellow, green, red, pink, purple, cyan, gray }

/// LXServer v2.2.0 theme_variables.css .t-badge-* light-theme palette.
class MusicBadge extends StatelessWidget {
  const MusicBadge(this.label, {super.key, required this.tone});
  final String label;
  final BadgeTone tone;
  static final _cjk = RegExp(r'[\u3400-\u9fff]');
  static BadgeTone source(MusicSource source) => switch (source) {
    MusicSource.kw => BadgeTone.yellow,
    MusicSource.kg => BadgeTone.blue,
    MusicSource.tx => BadgeTone.green,
    MusicSource.wy => BadgeTone.red,
    MusicSource.mg => BadgeTone.pink,
  };
  static BadgeTone quality(String label) => switch (label) {
    'Master' || '母带' => BadgeTone.purple,
    'Atmos' || '空间音频' || '增强空间音频' => BadgeTone.cyan,
    'Hi-Res' || '24bit 无损' => BadgeTone.yellow,
    '无损' => BadgeTone.green,
    '高品质' => BadgeTone.blue,
    _ => BadgeTone.gray,
  };
  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (tone) {
      BadgeTone.blue => (0xFFDBEAFE, 0xFF1D4ED8, 0xFFBFDBFE),
      BadgeTone.yellow => (0xFFFEF3C7, 0xFFB45309, 0xFFFDE68A),
      BadgeTone.green => (0xFFD1FAE5, 0xFF047857, 0xFFA7F3D0),
      BadgeTone.red => (0xFFFFE4E6, 0xFFBE123C, 0xFFFECDD3),
      BadgeTone.pink => (0xFFFCE7F3, 0xFFBE185D, 0xFFFBCFE8),
      BadgeTone.purple => (0xFFEDE9FE, 0xFF6D28D9, 0xFFDDD6FE),
      BadgeTone.cyan => (0xFFCFFAFE, 0xFF0E7490, 0xFFA5F3FC),
      BadgeTone.gray => (0xFFF3F4F6, 0xFF4B5563, 0xFFE5E7EB),
    };
    final hasChinese = _cjk.hasMatch(label);
    final text = Text(
      label,
      style: TextStyle(
        fontSize: 10,
        height: 1.3,
        leadingDistribution: hasChinese ? null : TextLeadingDistribution.even,
        fontWeight: FontWeight.w600,
        color: Color(foreground),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Color(background),
        border: Border.all(color: Color(border)),
        borderRadius: BorderRadius.circular(4),
      ),
      // CJK glyphs need a small optical correction within their natural line box.
      child: hasChinese
          ? Transform.translate(
              offset: Offset(0, -MediaQuery.textScalerOf(context).scale(0.5)),
              child: text,
            )
          : text,
    );
  }
}
