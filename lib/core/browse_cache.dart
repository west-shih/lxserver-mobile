import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Rebuildable metadata, separate from audio/downloads and credentials.
/// Entries remain usable until explicit refresh or capacity eviction.
class BrowseCache {
  static final shared = BrowseCache();
  BrowseCache({
    Future<Directory> Function()? directory,
    this.maxBytes = 128 * 1024 * 1024,
  }) : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;
  int maxBytes;
  static const limitsMb = [32, 64, 128, 256, 512, 1024];
  Future<void> setLimitMb(int value) async {
    if (!limitsMb.contains(value)) return;
    maxBytes = value * 1024 * 1024;
    await _enqueue(() async => _prune(await _root()));
  }

  Future<void> _writes = Future.value();
  int _generation = 0;

  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/browse-cache-v1',
  );

  static String digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  Future<Directory> _root() async {
    final root = await _directory();
    await root.create(recursive: true);
    return root;
  }

  Future<Object?> read(String key) async {
    await _writes;
    try {
      final file = File('${(await _root()).path}/${digest(key)}.json');
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map || value['version'] != 1) return null;
      final data = value['data'];
      if (data is! Map<String, dynamic> && data is! List) return null;
      await file.setLastModified(DateTime.now());
      // Return a fresh decoded object; callers cannot mutate another read.
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String key,
    Object data, {
    required int generation,
    String? family,
  }) {
    return _enqueue(() async {
      if (generation != _generation) return;
      final encoded = jsonEncode({
        'version': 1,
        'family': family,
        'data': data,
      });
      // Do not persist oversized responses or credential-bearing metadata.
      if (utf8.encode(encoded).length > 4 * 1024 * 1024 ||
          RegExp(
            r'"(?:token|password|cookie|authorization)"\s*:',
            caseSensitive: false,
          ).hasMatch(encoded) ||
          RegExp(
            r'[?&](?:token|access_token|password|signature|x-user-token)=',
            caseSensitive: false,
          ).hasMatch(encoded)) {
        return;
      }
      final root = await _root();
      final file = File('${root.path}/${digest(key)}.json');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
      await _prune(root);
    });
  }

  int get generation => _generation;

  Future<void> invalidateFamily(String family) => _enqueue(() async {
    await for (final item in (await _root()).list()) {
      if (item is! File || !item.path.endsWith('.json')) continue;
      try {
        final value = jsonDecode(await item.readAsString());
        if (value is Map && value['family'] == family) await item.delete();
      } catch (_) {
        // A corrupt entry will be treated as a miss.
      }
    }
  });

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _writes.then((_) => action()).catchError((Object _) {
      // Cache I/O must never turn a successful API response into a failure.
    });
    _writes = next;
    return next;
  }

  Future<void> _prune(Directory root) async {
    final entries = <(File, FileStat)>[];
    var total = 0;
    await for (final item in root.list()) {
      if (item is! File) continue;
      if (item.path.endsWith('.tmp')) {
        await item.delete();
      } else if (item.path.endsWith('.json')) {
        final stat = await item.stat();
        entries.add((item, stat));
        total += stat.size;
      }
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final entry in entries) {
      if (total <= maxBytes) break;
      await entry.$1.delete();
      total -= entry.$2.size;
    }
  }

  Future<void> clear() {
    _generation++;
    return _enqueue(() async {
      final root = await _root();
      await for (final item in root.list()) {
        if (item is File &&
            (item.path.endsWith('.json') || item.path.endsWith('.tmp'))) {
          await item.delete();
        }
      }
    });
  }

  Future<int> bytes() async {
    await _writes;
    try {
      var total = 0;
      await for (final item in (await _root()).list()) {
        if (item is File && item.path.endsWith('.json')) {
          total += await item.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
