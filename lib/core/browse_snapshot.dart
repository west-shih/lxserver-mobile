import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// View state is independent of evictable HTTP/image cache and playback URLs.
Object? safeBrowseValue(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        if (!RegExp(
          r'^(token|password|cookie|authorization|typeUrl|url|playUrl|lrc)$',
          caseSensitive: false,
        ).hasMatch('${entry.key}'))
          '${entry.key}': safeBrowseValue(entry.value),
    };
  }
  if (value is List) return value.take(10000).map(safeBrowseValue).toList();
  if (value is String &&
      RegExp(
        r'[?&](token|access_token|password|signature|auth_key)=',
        caseSensitive: false,
      ).hasMatch(value)) {
    return '';
  }
  return value;
}

class BrowseSnapshotStore {
  BrowseSnapshotStore({Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() directory;
  Future<void> _writes = Future.value();
  int _generation = 0;
  Future<File> _file() async {
    final root = await directory();
    await root.create(recursive: true);
    return File('${root.path}/browse-session-v2.json');
  }

  Future<Map<String, dynamic>> read() async {
    await _writes;
    try {
      final file = await _file();
      if (!await file.exists() || await file.length() > 24 * 1024 * 1024) {
        return {};
      }
      final data = jsonDecode(await file.readAsString());
      return data is Map<String, dynamic> && data['version'] == 2 ? data : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> write(Map<String, dynamic> value) {
    final generation = _generation;
    final encoded = jsonEncode(safeBrowseValue({'version': 2, ...value}));
    return _writes = _writes
        .then((_) async {
          if (generation != _generation ||
              utf8.encode(encoded).length > 24 * 1024 * 1024) {
            return;
          }
          final file = await _file();
          final temporary = File('${file.path}.tmp');
          await temporary.writeAsString(encoded, flush: true);
          await temporary.rename(file.path);
        })
        .catchError((Object _) {});
  }

  Future<void> clear() {
    _generation++;
    return _writes = _writes
        .then((_) async {
          final file = await _file();
          if (await file.exists()) await file.delete();
          final temporary = File('${file.path}.tmp');
          if (await temporary.exists()) await temporary.delete();
        })
        .catchError((Object _) {});
  }
}
