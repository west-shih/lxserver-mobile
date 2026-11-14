import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/lx_api.dart';
import '../../core/song_snapshot.dart';
import 'quality.dart';

class PlaybackSnapshot {
  PlaybackSnapshot({
    required this.scope,
    required this.songs,
    required this.index,
    required this.position,
    required this.duration,
    this.quality,
    this.reportedQuality,
  });
  final String scope;
  final List<Song> songs;
  final int index;
  final Duration position, duration;
  final String? quality, reportedQuality;
  static String scopeFor(Session s) => sha256
      .convert(utf8.encode(jsonEncode([s.server.toString(), s.username])))
      .toString();
  Map<String, dynamic> toJson() {
    // A bounded window keeps the current song even in unusually large queues.
    final start = (index - 1000)
        .clamp(0, math.max(0, songs.length - 2000))
        .toInt();
    return {
      'version': 1,
      'scope': scope,
      'songs': songs.skip(start).take(2000).map(songSnapshotData).toList(),
      'index': index - start,
      'position': position.inMilliseconds,
      'duration': duration.inMilliseconds,
      'quality': quality,
      'reportedQuality': reportedQuality,
    };
  }

  static PlaybackSnapshot? parse(Object? data, Session s) {
    try {
      final v = data as Map;
      final queue = v['songs'] as List;
      final index = v['index'] as int;
      if (v['version'] != 1 ||
          v['scope'] != scopeFor(s) ||
          queue.isEmpty ||
          queue.length > 2000 ||
          index < 0 ||
          index >= queue.length) {
        return null;
      }
      final songs = queue
          .map((e) => Song(Map<String, dynamic>.from(e as Map), MusicSource.kw))
          .toList();
      final length = (v['duration'] as int).clamp(0, 7 * 24 * 3600 * 1000);
      final at = (v['position'] as int).clamp(
        0,
        length > 0 ? length : 7 * 24 * 3600 * 1000,
      );
      return PlaybackSnapshot(
        scope: v['scope'] as String,
        songs: songs,
        index: index,
        position: Duration(milliseconds: at),
        duration: Duration(milliseconds: length),
        quality: AudioQuality.find(v['quality'] as String?)?.id,
        reportedQuality: AudioQuality.find(v['reportedQuality'] as String?)?.id,
      );
    } catch (_) {
      return null;
    }
  }
}

class PlaybackResumeStore {
  PlaybackResumeStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  Future<void> _writes = Future.value();
  Timer? _timer;
  PlaybackSnapshot? _pending;
  String? _lastQueued;
  Future<File> _file() async =>
      File('${(await _directory()).path}/lx_playback.json');
  Future<PlaybackSnapshot?> read(Session session) async {
    try {
      await _writes;
      final file = await _file();
      if (!await file.exists() || await file.length() > 8 * 1024 * 1024) {
        return null;
      }
      return PlaybackSnapshot.parse(
        jsonDecode(await file.readAsString()),
        session,
      );
    } catch (_) {
      return null;
    }
  }

  void schedule(PlaybackSnapshot snapshot, {bool immediately = false}) {
    _pending = snapshot;
    if (immediately) {
      unawaited(flush());
    } else {
      _timer ??= Timer(const Duration(seconds: 3), () => unawaited(flush()));
    }
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final state = _pending;
    _pending = null;
    if (state == null) return _writes;
    final value = jsonEncode(state.toJson());
    if (value == _lastQueued) return _writes;
    _lastQueued = value;
    _writes = _writes
        .then((_) async {
          final file = await _file();
          await file.parent.create(recursive: true);
          final temp = File('${file.path}.tmp');
          await temp.writeAsString(value, flush: true);
          await temp.rename(file.path);
        })
        .catchError((Object _) {
          if (_lastQueued == value) {
            _lastQueued = null;
          }
        });
    return _writes;
  }

  Future<void> clear() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _lastQueued = null;
    _writes = _writes
        .then((_) async {
          final file = await _file();
          if (await file.exists()) await file.delete();
        })
        .catchError((Object _) {});
    return _writes;
  }

  void dispose() {
    unawaited(flush());
  }
}
