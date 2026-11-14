import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/lx_api.dart';

/// Server-side files only; never claims a phone has an offline audio file.
class ServerFilesController extends ChangeNotifier {
  ServerFilesController(
    this.api,
    this.onUnauthorized, {
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final LxApi api;
  final VoidCallback onUnauthorized;
  final DateTime Function() now;
  final Map<String, Map<String, String>> _files = {};
  String _scope = '';
  DateTime? _loadedAt;
  Future<void>? _pending;
  int _version = 0;
  bool available = false;

  static String songKey(Map data) {
    final id =
        ['songmid', 'songId', 'id']
            .map((key) => data[key])
            .where((value) => value != null && '$value'.isNotEmpty)
            .map((value) => '$value')
            .firstOrNull ??
        '';
    final source = data['source'];
    return id.isNotEmpty &&
            !id.contains('_') &&
            source != null &&
            source != 'unknown' &&
            source != ''
        ? '${source}_$id'
        : id;
  }

  Map<String, String> folders(Song song) =>
      available ? Map.unmodifiable(_files[songKey(song.raw)] ?? {}) : const {};
  String? badge(Song song) {
    final values = folders(song).values;
    if (values.contains('music')) return '已下载';
    return values.contains('cache') ? '已缓存' : null;
  }

  Future<void> ensure(Session s, {bool force = false}) {
    final scope = jsonEncode([s.server.toString(), s.username, s.token]);
    if (scope != _scope) {
      reset(notify: false);
      _scope = scope;
    }
    if (_pending != null) return _pending!;
    if (!force &&
        _loadedAt != null &&
        now().difference(_loadedAt!) < const Duration(minutes: 1)) {
      return Future.value();
    }
    final version = ++_version;
    return _pending = _load(s, version).whenComplete(() {
      if (version == _version) _pending = null;
    });
  }

  Future<void> _load(Session s, int version) async {
    try {
      final value = await api.read(
        s,
        '/api/music/cache/list',
        timeout: const Duration(seconds: 5),
      );
      if (version != _version) return;
      if (value is! Map || value['success'] != true || value['data'] is! List) {
        throw const ApiFailure('服务器文件列表格式不兼容');
      }
      final next = <String, Map<String, String>>{};
      for (final row in value['data'] as List) {
        if (row is! Map || !['cache', 'music'].contains(row['folder'])) {
          continue;
        }
        final id = row['id'] is String && (row['id'] as String).isNotEmpty
            ? row['id'] as String
            : songKey(row['songInfo'] is Map ? row['songInfo'] as Map : row);
        final quality = row['quality'];
        if (id.isEmpty || quality is! String) continue;
        final folders = next.putIfAbsent(id, () => {});
        if (folders[quality] != 'music') {
          folders[quality] = row['folder'] as String;
        }
      }
      _files
        ..clear()
        ..addAll(next);
      available = true;
    } on ApiFailure catch (e) {
      if (version != _version) return;
      _files.clear();
      available = false;
      if (e.unauthorized) onUnauthorized();
    } catch (_) {
      if (version != _version) return;
      _files.clear();
      available = false;
    } finally {
      if (version == _version) {
        _loadedAt = now();
        notifyListeners();
      }
    }
  }

  void reset({bool notify = true}) {
    ++_version;
    _files.clear();
    _scope = '';
    _loadedAt = null;
    _pending = null;
    available = false;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    ++_version;
    super.dispose();
  }
}
