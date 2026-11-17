import 'dart:async';
import 'dart:convert';

import '../../core/lx_api.dart';

/// Results survive restart; signed media URLs only live briefly in memory.
class PlaybackCache {
  PlaybackCache({DateTime Function()? now, this.saveHistory})
    : now = now ?? DateTime.now;
  final DateTime Function() now;
  final Future<void> Function(String)? saveHistory;
  static const failureTtl = Duration(seconds: 30);
  static const urlTtl = Duration(minutes: 5);
  final Map<String, Map<String, dynamic>> _history = {};
  final Map<String, Map<String, DateTime>> _failures = {};
  final Map<String, ({PlaybackResource resource, DateTime expires})> _urls = {};
  String _configuration = '';
  Future<void> _writes = Future.value();

  String scope(Session s) =>
      jsonEncode([s.server.toString(), s.username, _configuration]);
  String _key(String scope, Song song) => jsonEncode([scope, song.id]);
  String _urlKey(String scope, Song song, String quality) =>
      jsonEncode([scope, song.id, quality]);
  void configure(Object data) {
    // Keep server order, IDs and capability changes; never retain source scripts.
    final signature = jsonEncode(
      data is List
          ? data
                .map(
                  (v) => v is Map
                      ? {
                          for (final k in [
                            'id',
                            'name',
                            'enabled',
                            'status',
                            'supportedSources',
                            'disabledSources',
                            'version',
                            'updateTime',
                          ])
                            k: v[k],
                        }
                      : null,
                )
                .toList()
          : null,
    );
    if (signature == _configuration) return;
    _configuration = signature;
    clear(keepConfiguration: true);
  }

  Map<String, dynamic> _record(String scope, Song song) =>
      _history.putIfAbsent(_key(scope, song), () => {});
  bool failed(String scope, Song song, String quality) {
    final time = _failures[_key(scope, song)]?[quality];
    return time != null && now().difference(time) < failureTtl;
  }

  String? successful(String scope, Song song, {String? preference}) {
    final r = _history[_key(scope, song)];
    // Legacy records without a preference binding were not confirmed track choices.
    if (preference != null && r?['preference'] == null) return null;
    return r?['quality'] as String?;
  }

  PlaybackResource? resource(String scope, Song song, String quality) {
    final key = _urlKey(scope, song, quality);
    final item = _urls[key];
    if (item == null) return null;
    if (!now().isBefore(item.expires)) {
      _urls.remove(key);
      return null;
    }
    return item.resource;
  }

  void invalidateUrl(String scope, Song song, String quality) =>
      _urls.remove(_urlKey(scope, song, quality));
  void success(
    String scope,
    Song song,
    PlaybackResource resource, {
    bool reusedUrl = false,
    String? preference,
  }) {
    final r = _record(scope, song);
    r['at'] = now().millisecondsSinceEpoch;
    r['quality'] = resource.requestedQuality;
    r['preference'] = preference;
    r['sourceId'] = resource.sourceId;
    // Retain the most recently played records when reaching the storage bound.
    _history.remove(_key(scope, song));
    _history[_key(scope, song)] = r;
    _failures[_key(scope, song)]?.remove(resource.requestedQuality);
    if (!reusedUrl) {
      _urls[_urlKey(scope, song, resource.requestedQuality)] = (
        resource: resource,
        expires: now().add(urlTtl),
      );
    }
    _persist();
  }

  void failure(String scope, Song song, String quality) {
    invalidateUrl(scope, song, quality);
    _failures.putIfAbsent(_key(scope, song), () => {})[quality] = now();
    while (_failures.length > 200) {
      _failures.remove(_failures.keys.first);
    }
  }

  void forget(String scope, Song song) {
    _history.remove(_key(scope, song));
    _failures.remove(_key(scope, song));
    for (final q in [
      '128k',
      '192k',
      '320k',
      'flac',
      'flac24bit',
      'hires',
      'atmos',
      'atmos_plus',
      'master',
      'wav',
    ]) {
      invalidateUrl(scope, song, q);
    }
    _persist();
  }

  void clear({bool keepConfiguration = false}) {
    _history.clear();
    _failures.clear();
    _urls.clear();
    if (!keepConfiguration) _configuration = '';
    _persist();
  }

  void restore(String? value) {
    _failures.clear();
    if (value == null) return;
    try {
      final data = jsonDecode(value) as Map;
      _configuration = data['configuration'] as String;
      final history = data['history'] as Map;
      for (final e in history.entries) {
        final r = Map<String, dynamic>.from(e.value as Map);
        if (r['failed'] != null && r['failed'] is! Map) {
          throw const FormatException('Invalid playback history');
        }
        r.remove(
          'failed',
        ); // Migrate old persisted negative results: never restore them.
        if (r['preference'] != null && r['preference'] is! String) {
          throw const FormatException('Invalid playback preference');
        }
        if (e.key is String &&
            (r['quality'] == null || r['quality'] is String)) {
          _history[e.key as String] = r;
        }
      }
    } catch (_) {
      _history.clear();
      _failures.clear();
      _configuration = '';
    }
  }

  void _persist() {
    while (_urls.length > 100) {
      _urls.remove(_urls.keys.first);
    }
    final snapshot = _snapshot();
    _writes = _writes
        .then((_) async {
          await saveHistory?.call(snapshot);
        })
        .catchError((Object _) {});
  }

  String _snapshot() =>
      jsonEncode({'configuration': _configuration, 'history': _history});

  /// Serialized preference data, excluding platform secure-storage overhead.
  int get storageBytes => utf8.encode(_snapshot()).length;

  Future<void> flush() => _writes;

  bool _belongsTo(String key, Session session) {
    try {
      final identity = jsonDecode(key) as List;
      final scope = jsonDecode(identity.first as String) as List;
      return scope[0] == session.server.toString() &&
          scope[1] == session.username;
    } catch (_) {
      return false;
    }
  }

  int trackCount(Session session) =>
      _history.keys.where((key) => _belongsTo(key, session)).length;

  Future<void> resetTrackChoices(Session session) async {
    _history.removeWhere((key, _) => _belongsTo(key, session));
    _failures.removeWhere((key, _) => _belongsTo(key, session));
    _urls.removeWhere((key, _) => _belongsTo(key, session));
    _persist();
    await flush();
  }
}
