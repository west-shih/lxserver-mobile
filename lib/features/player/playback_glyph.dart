import 'package:flutter/material.dart';

enum PlaybackGlyphType { play, pause, previous, next, comment }

/// Rounded geometry shared by the full player and mini player.
class PlaybackGlyph extends StatelessWidget {
  const PlaybackGlyph(this.type, {super.key, this.size = 26});
  final PlaybackGlyphType type;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GlyphPainter(
          type,
          IconTheme.of(context).color ?? Colors.black,
        ),
      ),
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.type, this.color);
  final PlaybackGlyphType type;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (type == PlaybackGlyphType.comment) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(8, 4)
          ..lineTo(16, 4)
          ..cubicTo(20, 4, 22, 6, 22, 10)
          ..cubicTo(22, 15, 20, 18, 15, 18)
          ..lineTo(9, 18)
          ..quadraticBezierTo(7, 20, 4, 21)
          ..quadraticBezierTo(5, 18, 4, 16)
          ..cubicTo(2, 14, 2, 12, 2, 10)
          ..cubicTo(2, 6, 4, 4, 8, 4)
          ..close(),
        paint,
      );
      paint.style = PaintingStyle.fill;
      for (final x in [8.0, 12.0, 16.0]) {
        canvas.drawCircle(Offset(x, 11), .8, paint);
      }
    } else if (type == PlaybackGlyphType.pause) {
      for (final x in [7.0, 14.0]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 5, 3.5, 14),
            const Radius.circular(1.75),
          ),
          paint,
        );
      }
    } else {
      final skip =
          type == PlaybackGlyphType.previous || type == PlaybackGlyphType.next;
      if (type == PlaybackGlyphType.previous) {
        canvas.translate(24, 0);
        canvas.scale(-1, 1);
      }
      if (skip) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(19, 5, 3, 14),
            const Radius.circular(1.5),
          ),
          paint,
        );
        canvas.translate(-2, 0);
      }
      canvas.drawPath(
        Path()
          ..moveTo(9.5, 5.5)
          ..quadraticBezierTo(7, 4, 7, 7)
          ..lineTo(7, 17)
          ..quadraticBezierTo(7, 20, 9.5, 18.5)
          ..lineTo(18.5, 13.5)
          ..quadraticBezierTo(21, 12, 18.5, 10.5)
          ..close(),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.type != type || old.color != color;
}
