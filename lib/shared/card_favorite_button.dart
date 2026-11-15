import 'package:flutter/material.dart';

/// Shared small, masked favorite control for artist and album cards.
class CardFavoriteButton extends StatelessWidget {
  const CardFavoriteButton({
    super.key,
    required this.saved,
    required this.tooltip,
    this.onPressed,
  });
  final bool saved;
  final String tooltip;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    isSelected: saved,
    onPressed: onPressed,
    alignment: Alignment.topRight,
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(
      fixedSize: const Size(40, 40),
      minimumSize: const Size(40, 40),
    ),
    icon: Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0x66172922),
      ),
      child: Transform.translate(
        offset: const Offset(0, 1),
        child: Icon(
          saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 15,
          color: saved ? const Color(0xffef4444) : Colors.white,
        ),
      ),
    ),
  );
}
