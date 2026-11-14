import 'dart:async';
import 'dart:io';

class LocalArtwork {
  LocalArtwork(this.directory);
  final Directory directory;
  final Set<String> _files = {};
  final Map<String, Future<void>> _pending = {};
  Future<void> _tail = Future.value();
  final Set<HttpClient> _clients = {};
  bool _disposed = false;
  static final _id = RegExp(r'^[a-f0-9]{64}$');
  static const maxBytes = 2 * 1024 * 1024;
  String? path(String key) =>
      _files.contains(key) ? '${directory.path}/$key.img' : null;

  Future<void> initialize(Set<String> retained) async {
    await directory.create(recursive: true);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final key = name.split('.').first;
      if (!_id.hasMatch(key)) continue;
      if (name == '$key.img' &&
          retained.contains(key) &&
          await entity.length() > 0) {
        _files.add(key);
      } else if (name == '$key.img' || name == '$key.part') {
        await entity.delete();
      }
    }
  }

  Future<void> ensure(
    String key,
    String url,
    bool Function() needed,
    void Function() onSaved,
  ) async {
    if (_disposed ||
        !_id.hasMatch(key) ||
        _files.contains(key) ||
        url.isEmpty) {
      return;
    }
    if (_pending.containsKey(key)) return _pending[key];
    final task = _tail.then((_) => _fetch(key, url, needed, onSaved));
    _tail = task.catchError((Object _) {});
    _pending[key] = task;
    try {
      await task;
    } finally {
      _pending.remove(key);
    }
  }

  Future<void> _fetch(
    String key,
    String url,
    bool Function() needed,
    void Function() onSaved,
  ) async {
    if (_disposed || !needed()) return;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    final client = HttpClient()
      ..userAgent = 'Mozilla/5.0'
      ..connectionTimeout = const Duration(seconds: 8);
    _clients.add(client);
    final temp = File('${directory.path}/$key.part');
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      if (uri.host == 'music.126.net' || uri.host.endsWith('.music.126.net')) {
        request.headers.set('Referer', 'https://music.163.com/');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != 200 || response.contentLength > maxBytes) {
        return;
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes || _disposed || !needed()) return;
      }
      final png =
          bytes.length > 8 &&
          bytes[0] == 137 &&
          String.fromCharCodes(bytes.sublist(1, 4)) == 'PNG';
      final jpeg = bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216;
      final gif =
          bytes.length > 6 &&
          String.fromCharCodes(bytes.sublist(0, 3)) == 'GIF';
      final webp =
          bytes.length > 12 &&
          String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
      if (!(png || jpeg || gif || webp) || _disposed || !needed()) return;
      await temp.writeAsBytes(bytes, flush: true);
      if (_disposed || !needed()) return;
      await temp.rename('${directory.path}/$key.img');
      _files.add(key);
      if (!_disposed) onSaved();
    } catch (_) {
      // Artwork never blocks or fails an audio download.
    } finally {
      client.close(force: true);
      _clients.remove(client);
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }

  Future<void> remove(String key) async {
    _files.remove(key);
    final file = File('${directory.path}/$key.img');
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // An orphaned cover can be retried at startup; audio deletion still succeeds.
    }
  }

  Future<void> flush() async {
    await Future.wait(_pending.values.toList());
  }

  void dispose() {
    _disposed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
  }
}
