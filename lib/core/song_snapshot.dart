import 'lx_api.dart';

/// Persist public artwork URLs only; authenticated URLs may be fetched but never indexed.
String? publicArtworkUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.queryParameters.keys.any(
        (k) => RegExp(
          r'token|password|authorization|signature|auth_key|access_key',
          caseSensitive: false,
        ).hasMatch(k),
      )) {
    return null;
  }
  return value;
}

Map<String, dynamic> songSnapshotData(Song song) => {
  if (publicArtworkUrl(song.image) != null) 'img': song.image,
  for (final key in [
    'name',
    'singer',
    'source',
    'songmid',
    'songId',
    'id',
    'albumName',
    'interval',
    'hash',
    'copyrightId',
    'strMediaMid',
    'albumMid',
    'albumId',
    'hashMid',
    'mid',
    'sid',
    'mediaMid',
    'singerId',
    'artistId',
    'singermid',
  ])
    if (song.raw[key] != null) key: song.raw[key],
};
