import 'package:flutter/material.dart';

import 'dart:io';

import '../app/theme.dart';
import '../core/artwork_image.dart';

Map<String, String> artworkHeaders(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host == 'music.126.net' || host.endsWith('.music.126.net')) {
    return const {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://music.163.com/',
    };
  }
  return const {};
}

class SongArt extends StatelessWidget {
  const SongArt({
    super.key,
    this.url = '',
    this.size = 52,
    this.localPath,
    this.borderRadius,
    this.placeholderIcon = Icons.music_note_rounded,
    this.placeholderColor,
    this.placeholderBackground,
  });
  final double? borderRadius;
  final IconData placeholderIcon;
  final Color? placeholderColor, placeholderBackground;
  final String? localPath;
  final String url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: placeholderBackground,
        gradient: placeholderBackground != null
            ? null
            : const LinearGradient(
                colors: [Color(0xFFDDF5E9), Color(0xFFC0E6D7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
      ),
      child: Icon(
        placeholderIcon,
        color: placeholderColor ?? lxGreen,
        size: size * .4,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius ?? size * .2),
      child: localPath != null
          ? Image(
              image: ResizeImage(
                FileImage(File(localPath!)),
                width: pixels,
                height: pixels,
                policy: ResizeImagePolicy.fit,
              ),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => SongArt(
                url: url,
                size: size,
                borderRadius: borderRadius,
                placeholderIcon: placeholderIcon,
                placeholderColor: placeholderColor,
                placeholderBackground: placeholderBackground,
              ),
            )
          : url.isEmpty
          ? placeholder
          : Image(
              image: ResizeImage(
                ArtworkImage(url, headers: artworkHeaders(url)),
                width: pixels,
                height: pixels,
                policy: ResizeImagePolicy.fit,
              ),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
