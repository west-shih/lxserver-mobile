import 'package:flutter/material.dart';

/// Three horizontal lines with a lower-right check, matching the playlist editor.
class PlaylistEditGlyph extends StatelessWidget {
  const PlaylistEditGlyph({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: CustomPaint(
      painter: _PlaylistEditPainter(
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

class _PlaylistEditPainter extends CustomPainter {
  const _PlaylistEditPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      Path()
        ..moveTo(3, 5)
        ..lineTo(20, 5)
        ..moveTo(3, 10.5)
        ..lineTo(20, 10.5)
        ..moveTo(3, 16)
        ..lineTo(10, 16)
        ..moveTo(13.5, 17)
        ..lineTo(16.5, 20)
        ..lineTo(22, 13.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PlaylistEditPainter oldDelegate) =>
      oldDelegate.color != color;
}
