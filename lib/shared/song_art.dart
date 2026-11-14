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
  const SongArt({super.key, this.url = '', this.size = 52, this.localPath});
  final String? localPath;
  final String url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFDDF5E9), Color(0xFFC0E6D7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.music_note_rounded, color: lxGreen, size: size * .4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .2),
      child: localPath != null
          ? Image(
              image: FileImage(File(localPath!)),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => SongArt(url: url, size: size),
            )
          : url.isEmpty
          ? placeholder
          : Image(
              image: ArtworkImage(url, headers: artworkHeaders(url)),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
