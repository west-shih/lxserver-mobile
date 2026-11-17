import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'browse_cache.dart';

/// A separate client prevents the platform default User-Agent being appended.
class ArtworkImage extends ImageProvider<ArtworkImage> {
  const ArtworkImage(this.url, {this.headers, this.cache});
  final String url;
  final Map<String, String>? headers;
  final BrowseCache? cache;

  @override
  Future<ArtworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  bool operator ==(Object other) =>
      other is ArtworkImage &&
      other.url == url &&
      identical(other.cache, cache) &&
      mapEquals(other.headers, headers);

  @override
  int get hashCode =>
      Object.hash(url, headers?['User-Agent'], headers?['Referer'], cache);

  static final HttpClient _client = HttpClient()..userAgent = null;

  @override
  ImageStreamCompleter loadImage(
    ArtworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1);

  Future<ui.Codec> _load(ArtworkImage key, ImageDecoderCallback decode) async {
    try {
      final safe =
          (key.headers?.keys.every(
                (header) =>
                    ['user-agent', 'referer'].contains(header.toLowerCase()),
              ) ??
              true) &&
          !RegExp(
            r'[?&](token|access_token|password|signature|x-user-token)=',
            caseSensitive: false,
          ).hasMatch(key.url);
      final cache = key.cache ?? BrowseCache.shared;
      final generation = cache.generation;
      final cacheKey = 'public-artwork:${key.url}:${jsonEncode(key.headers)}';
      if (safe) {
        final stored = await cache.read(cacheKey);
        if (stored is Map && stored['image'] is String) {
          try {
            return await decode(
              await ui.ImmutableBuffer.fromUint8List(
                base64Decode(stored['image'] as String),
              ),
            );
          } catch (_) {
            // Corrupt images can be fetched again.
          }
        }
      }
      final uri = Uri.parse(key.url);
      final request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      key.headers?.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: uri,
        );
      }
      final bytes = await consolidateHttpClientResponseBytes(response)
          .timeout(const Duration(seconds: 20));
      final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      if (safe && bytes.length <= 2 * 1024 * 1024) {
        await cache.write(cacheKey, {
          'image': base64Encode(bytes),
        }, generation: generation);
      }
      return codec;
    } catch (_) {
      PaintingBinding.instance.imageCache.evict(key);
      rethrow;
    }
  }
}
