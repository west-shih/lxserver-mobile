import '../../core/lx_api.dart';

/// Align saved identities/meta with the v2.2.0 web formatSongToLxMusicStandard.
/// Preserve extra fields so parsing-specific information is not discarded.
Map<String, dynamic> librarySong(Song song) {
  final raw = song.raw;
  final meta = raw['meta'] is Map
      ? Map<String, dynamic>.from(raw['meta'] as Map)
      : <String, dynamic>{};
  final source = song.source.name;
  final mid = '${raw['songmid'] ?? raw['id'] ?? ''}';
  if ('${meta['songId'] ?? ''}'.isNotEmpty &&
      raw['id'] != null &&
      ('${raw['id']}'.contains('_') || source == 'mg')) {
    return {
      ...raw,
      'meta': {...meta, if (song.image.isNotEmpty) 'picUrl': song.image},
    };
  }
  meta.addAll({
    'songId': mid,
    'songmid': mid,
    'albumName': song.album,
    'picUrl': song.image,
    'qualitys': raw['qualitys'] ?? raw['types'] ?? meta['qualitys'] ?? [],
    '_qualitys': raw['_qualitys'] ?? raw['_types'] ?? meta['_qualitys'] ?? {},
  });
  for (final key in [
    'albumId',
    'strMediaMid',
    'albumMid',
    'copyrightId',
    'lrcUrl',
    'mrcUrl',
    'trcUrl',
  ]) {
    if (raw[key] != null) meta[key] = raw[key];
  }
  var id = '${source}_$mid';
  if (source == 'tx' && raw['songId'] != null) {
    meta['songId'] = '${raw['songId']}';
  }
  if (source == 'mg') id = mid;
  if (source == 'kg') {
    final parts = mid.split('_');
    final hash =
        '${raw['hash'] ?? (parts.length > 1
                ? parts[1]
                : mid.length == 32
                ? mid
                : '')}';
    var songId = '${raw['songId'] ?? (parts.length > 1 ? parts[0] : mid)}';
    if (songId == hash) songId = '';
    meta['songId'] = songId;
    meta['hash'] = hash;
    id = songId.isNotEmpty && hash.isNotEmpty
        ? '${songId}_$hash'
        : hash.isNotEmpty
        ? hash
        : 'kg_$songId';
  }
  return {...raw, 'id': id, 'meta': meta};
}
