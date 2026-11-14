import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A separate client prevents the platform default User-Agent being appended.
class ArtworkImage extends ImageProvider<ArtworkImage> {
  const ArtworkImage(this.url, {this.headers});
  final String url;
  final Map<String, String>? headers;

  @override
  Future<ArtworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  bool operator ==(Object other) =>
      other is ArtworkImage &&
      other.url == url &&
      mapEquals(other.headers, headers);

  @override
  int get hashCode =>
      Object.hash(url, headers?['User-Agent'], headers?['Referer']);

  static final HttpClient _client = HttpClient()..userAgent = null;

  @override
  ImageStreamCompleter loadImage(
    ArtworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1);

  Future<ui.Codec> _load(ArtworkImage key, ImageDecoderCallback decode) async {
    try {
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
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      PaintingBinding.instance.imageCache.evict(key);
      rethrow;
    }
  }
}
