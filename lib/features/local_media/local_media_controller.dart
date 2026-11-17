import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/lx_api.dart';
import '../../core/song_snapshot.dart';
import '../player/quality.dart';
import 'audio_transfer.dart';
import 'local_artwork.dart';

enum DownloadState { queued, resolving, downloading, paused, failed, completed }

class LocalAudio {
  LocalAudio({
    required this.id,
    required this.scope,
    required this.song,
    required this.quality,
    required this.folder,
    required this.ext,
    required this.bytes,
    required this.used,
    this.reportedQuality,
    this.valid = true,
    String? storageId,
  }) : storageId = storageId ?? id;
  final String id, scope, quality, folder, ext;
  final String storageId;
  Song song;
  final int bytes;
  final String? reportedQuality;
  int used;
  bool valid;
  Map<String, dynamic> toJson() => {
    'id': id,
    'scope': scope,
    'song': songSnapshotData(song),
    'quality': quality,
    'reported': reportedQuality,
    'folder': folder,
    'ext': ext,
    'bytes': bytes,
    'used': used,
    'valid': valid,
    'storageId': storageId,
  };
  static LocalAudio fromJson(Map<String, dynamic> v) => LocalAudio(
    id: v['id'] as String,
    scope: v['scope'] as String,
    song: Song(Map<String, dynamic>.from(v['song'] as Map), MusicSource.kw),
    quality: v['quality'] as String,
    folder: v['folder'] as String,
    ext: v['ext'] as String,
    bytes: v['bytes'] as int,
    used: v['used'] as int,
    reportedQuality: v['reported'] as String?,
    valid: v['valid'] != false,
    storageId: v['storageId'] as String?,
  );
}

class DownloadJob {
  DownloadJob(
    this.id,
    this.scope,
    this.song,
    this.preference, {
    this.state = DownloadState.queued,
    this.replace = false,
  });
  final String id, scope, preference;
  final Song song;
  final bool replace;
  DownloadState state;
  int received = 0;
  int? total;
  String? error;
  int generation = 0;
  Completer<void> interrupted = Completer();
  String? actualQuality;
  Map<String, dynamic> toJson() => {
    'id': id,
    'scope': scope,
    'song': songSnapshotData(song),
    'preference': preference,
    'state': state.name,
    'replace': replace,
  };
}

/// App-private audio files. Downloads are protected from automatic cache eviction.
class LocalMediaController extends ChangeNotifier {
  LocalMediaController(
    this.api,
    this.onUnauthorized, {
    Future<Directory> Function()? directory,
  }) : _directory = directory ?? getApplicationSupportDirectory;
  final LxApi api;
  final VoidCallback onUnauthorized;
  final Future<Directory> Function() _directory;
  Directory? _root;
  LocalArtwork? _artwork;
  Future<void>? _ready;
  Future<void> _writes = Future.value();
  final Map<String, LocalAudio> _files = {};
  final List<DownloadJob> _jobs = [];
  final Set<String> _pinned = {};
  Session? _session;
  String _scope = '';
  static const cacheLimitsMb = [0, 256, 512, 1024, 2048, 3072, 4096, 5120];
  int cacheLimitMb = 2048;
  int _cacheEpoch = 0;
  AudioTransfer? _cacheTransfer;
  String? _cacheKey;
  bool _cacheAccepted = false;
  AudioTransfer? _jobTransfer;
  DownloadJob? _activeJob;
  bool _running = false;
  bool _disposed = false;
  String? storageError;
  final Set<String> _discardOnRelease = {};
  final List<File> _pendingDeletes = [];
  int _transferEpoch = 0;

  static String scopeFor(Session s) => sha256
      .convert(utf8.encode(jsonEncode([s.server.toString(), s.username])))
      .toString();
  static String fileKey(Session s, Song song, String quality) => sha256
      .convert(utf8.encode(jsonEncode([scopeFor(s), song.id, quality])))
      .toString();
  static String artworkKey(String scope, Song song) =>
      sha256.convert(utf8.encode(jsonEncode([scope, song.id]))).toString();
  String? artworkPath(Song song) => _artwork?.path(artworkKey(_scope, song));
  bool _needsArtwork(String scope, Song song) =>
      !_disposed &&
      _files.values.any(
        (f) =>
            f.scope == scope && f.song.id == song.id && f.folder == 'downloads',
      );
  Future<void> _ensureArtwork(String scope, Song song) async {
    if (_artwork == null || !_needsArtwork(scope, song)) return;
    await _artwork!.ensure(
      artworkKey(scope, song),
      song.image,
      () => _needsArtwork(scope, song),
      _notify,
    );
  }

  Future<void> flushArtwork() async {
    await _artwork?.flush();
  }

  void updateArtwork(Iterable<Song> songs) {
    var changed = false;
    final images = {
      for (final song in songs.where((s) => s.image.isNotEmpty))
        song.id: song.image,
    };
    for (final f in _files.values.where((f) => f.scope == _scope)) {
      final url = images[f.song.id];
      if (url != null && url != f.song.image) {
        f.song = Song({...f.song.raw, 'img': url}, f.song.source);
        changed = true;
      }
      if (f.folder == 'downloads') unawaited(_ensureArtwork(f.scope, f.song));
    }
    if (changed) {
      _save();
      _notify();
    }
  }

  int get cacheBytes => _files.values
      .where((f) => f.folder == 'cache')
      .fold(0, (n, f) => n + f.bytes);
  int get cacheInProgressBytes =>
      _cacheTransfer?.complete == false ? _cacheTransfer!.received : 0;
  List<LocalAudio> get downloads =>
      _files.values
          .where((f) => f.scope == _scope && f.folder == 'downloads')
          .toList()
        ..sort((a, b) => b.used.compareTo(a.used));
  List<DownloadJob> get jobs => _jobs
      .where((j) => j.scope == _scope && j.state != DownloadState.completed)
      .toList();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _safe(LocalAudio f) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(f.id) &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(f.storageId) &&
      ['cache', 'downloads'].contains(f.folder) &&
      RegExp(r'^\.(mp3|flac|wav|m4a|ogg|aac|audio)$').hasMatch(f.ext);
  File _file(LocalAudio f) {
    if (!_safe(f) || _root == null) throw const ApiFailure('本机文件记录不可用');
    return File('${_root!.path}/${f.folder}/${f.storageId}${f.ext}');
  }

  Future<void> initialize() => _ready ??= _initialize();
  Future<void> _initialize() async {
    try {
      _root = Directory('${(await _directory()).path}/lx_audio');
      await Directory('${_root!.path}/cache').create(recursive: true);
      await Directory('${_root!.path}/downloads').create(recursive: true);
      final index = File('${_root!.path}/index.json');
      if (await index.exists()) {
        final value = jsonDecode(await index.readAsString()) as Map;
        final limit = value['cacheLimitMb'];
        if (limit is int && cacheLimitsMb.contains(limit)) {
          cacheLimitMb = limit;
        }
        for (final row in value['files'] as List? ?? []) {
          try {
            final f = LocalAudio.fromJson(
              Map<String, dynamic>.from(row as Map),
            );
            if (_safe(f) &&
                await _file(f).exists() &&
                await _file(f).length() == f.bytes) {
              _files[f.id] = f;
            }
          } catch (_) {
            /* A damaged record must never select an arbitrary path. */
          }
        }
        for (final row in value['jobs'] as List? ?? []) {
          try {
            final v = row as Map;
            final j = DownloadJob(
              v['id'] as String,
              v['scope'] as String,
              Song(Map<String, dynamic>.from(v['song'] as Map), MusicSource.kw),
              v['preference'] as String,
              state: DownloadState.paused,
              replace: v['replace'] == true,
            );
            j.error = '上次任务已暂停，继续将重新下载本首';
            _jobs.add(j);
          } catch (_) {}
        }
      }
      // Only app-generated temporary audio paths are removed after a process restart.
      for (final folder in ['cache', 'downloads']) {
        await for (final entity in Directory(
          '${_root!.path}/$folder',
        ).list(followLinks: false)) {
          if (entity is File &&
              RegExp(r'[\/][a-f0-9]{64}\.part$').hasMatch(entity.path)) {
            await entity.delete();
          }
        }
      }
      _artwork = LocalArtwork(Directory('${_root!.path}/artwork'));
      await _artwork!.initialize({
        for (final f in _files.values.where((f) => f.folder == 'downloads'))
          artworkKey(f.scope, f.song),
      });
      await _trim();
    } catch (_) {
      storageError = '本机存储暂不可用，在线播放仍可使用';
    }
  }

  Future<void> activate(Session s) async {
    await initialize();
    _session = s;
    _scope = scopeFor(s);
    for (final f in downloads) {
      unawaited(_ensureArtwork(f.scope, f.song));
    }
    _notify();
  }

  Future<void> deactivate() async {
    for (final j in _jobs.where(
      (j) =>
          j.state == DownloadState.queued ||
          j.state == DownloadState.resolving ||
          j.state == DownloadState.downloading,
    )) {
      j.generation++;
      if (!j.interrupted.isCompleted) j.interrupted.complete();
      j.state = _committed(j) ? DownloadState.completed : DownloadState.paused;
    }
    _session = null;
    _scope = '';
    await _cancelJobTransfer();
    _jobTransfer = null;
    await releasePlayback();
    _save();
    _notify();
  }

  Map<String, String> folders(Song song) => {
    for (final f in _files.values)
      if (f.scope == _scope && f.song.id == song.id && f.valid)
        f.quality: f.folder,
  };
  LocalAudio? fileFor(Song song, String quality) => _files.values
      .where(
        (f) =>
            f.scope == _scope &&
            f.song.id == song.id &&
            f.quality == quality &&
            f.valid,
      )
      .firstOrNull;

  /// Only successfully adopted playback refreshes LRU; file probes do not.
  void confirmPlayback(Session s, Song song, String quality) {
    if (_scope != scopeFor(s) || _session?.token != s.token) return;
    final f = fileFor(song, quality);
    if (f != null) f.used = DateTime.now().millisecondsSinceEpoch;
    _save();
  }

  bool pendingRemoval(Song song, String quality) =>
      _discardOnRelease.contains(fileFor(song, quality)?.id);

  Future<bool> clearSongCache(Song song, {String? quality}) async {
    await initialize();
    var deferred = false;
    for (final f
        in _files.values
            .where(
              (f) =>
                  f.scope == _scope &&
                  f.song.id == song.id &&
                  f.folder == 'cache' &&
                  (quality == null || f.quality == quality),
            )
            .toList()) {
      if (_pinned.contains(f.id)) {
        _discardOnRelease.add(f.id);
        deferred = true;
        continue;
      }
      if (await _file(f).exists()) await _file(f).delete();
      _files.remove(f.id);
    }
    _save();
    _notify();
    return deferred;
  }

  String? badge(Song song) {
    final values = folders(song).values;
    return values.contains('downloads')
        ? '已下载'
        : values.contains('cache')
        ? '已缓存'
        : null;
  }

  Future<PlaybackResource?> localResource(
    Session s,
    Song song,
    String quality,
  ) async {
    await initialize();
    final id = fileKey(s, song, quality);
    final f = _files[id];
    if (f == null || !f.valid) return null;
    if (!await _file(f).exists() || await _file(f).length() != f.bytes) {
      _files.remove(id);
      _save();
      _notify();
      return null;
    }
    return PlaybackResource(
      _file(f).uri,
      quality,
      f.reportedQuality,
      localFile: true,
    );
  }

  Future<void> pin(Session s, Song song, String quality) async {
    _pinned.add(fileKey(s, song, quality));
  }

  Future<void> invalidate(Session s, Song song, String quality) async {
    final id = fileKey(s, song, quality);
    final f = _files[id];
    if (f == null) return;
    if (f.folder == 'cache') {
      _files.remove(id);
      if (!_pinned.contains(id) && await _file(f).exists()) {
        await _file(f).delete();
      }
    } else {
      f.valid = false;
    }
    _save();
    _notify();
  }

  Future<AudioTransfer?> prepareCache(
    Session s,
    Song song,
    PlaybackResource r,
  ) async {
    await initialize();
    if (_root == null ||
        cacheLimitMb == 0 ||
        _session?.token != s.token ||
        _scope != scopeFor(s)) {
      return null;
    }
    final key = fileKey(s, song, r.requestedQuality);
    final epoch = _cacheEpoch;
    AudioTransfer transfer;
    try {
      transfer = await AudioTransfer.open(
        r.url,
        '${_root!.path}/cache/$key',
        cacheBudget: cacheLimitMb * 1024 * 1024,
      );
    } on CacheBypass {
      return null;
    } on FileSystemException {
      storageError = '缓存写入失败，已改用在线播放';
      return null;
    }
    if (_session?.token != s.token || _scope != scopeFor(s)) {
      await transfer.cancel(removeComplete: true);
      throw TransferCancelled();
    }
    await _trim(required: transfer.total!);
    if (cacheBytes + transfer.total! > cacheLimitMb * 1024 * 1024) {
      await transfer.cancel(removeComplete: true);
      return null;
    }
    _cacheTransfer = transfer;
    _cacheKey = key;
    _cacheAccepted = false;
    _transferEpoch = epoch;
    _pinned.add(key);
    unawaited(
      transfer.done
          .then((_) async {
            if (_cacheTransfer != transfer || !_cacheAccepted) return;
            await _registerCache(s, song, r, transfer, key, epoch);
          })
          .catchError((Object _) {}),
    );
    return transfer;
  }

  Future<void> acceptCache(
    Session s,
    Song song,
    PlaybackResource r,
    AudioTransfer t,
  ) async {
    if (_cacheTransfer != t) return;
    _cacheAccepted = true;
    if (t.complete) {
      await _registerCache(s, song, r, t, _cacheKey!, _transferEpoch);
    }
  }

  Future<void> _registerCache(
    Session s,
    Song song,
    PlaybackResource r,
    AudioTransfer t,
    String key,
    int epoch,
  ) async {
    if (_files.containsKey(key)) return;
    if (epoch != _cacheEpoch ||
        cacheLimitMb == 0 ||
        t.received > cacheLimitMb * 1024 * 1024) {
      _discardOnRelease.add(key);
      return;
    }
    final ext = t.target.path.substring(t.target.path.lastIndexOf('.'));
    _files[key] = LocalAudio(
      id: key,
      scope: scopeFor(s),
      song: song,
      quality: r.requestedQuality,
      reportedQuality: r.reportedQuality,
      folder: 'cache',
      ext: ext,
      bytes: t.received,
      used: DateTime.now().millisecondsSinceEpoch,
    );
    await _trim();
    _save();
    _notify();
  }

  Future<void> releasePlayback({AudioTransfer? only}) async {
    if (only != null && _cacheTransfer != only) return;
    final transfer = _cacheTransfer;
    final key = _cacheKey;
    _cacheTransfer = null;
    _cacheKey = null;
    _cacheAccepted = false;
    if (transfer != null) {
      await transfer.cancel(
        removeComplete:
            _files[key]?.folder != 'cache' || _discardOnRelease.contains(key),
      );
    }
    _pinned.clear();
    for (final key in _discardOnRelease) {
      final f = _files[key];
      if (f?.folder == 'cache') {
        if (await _file(f!).exists()) await _file(f).delete();
        _files.remove(key);
      }
    }
    for (final f in _pendingDeletes) {
      if (await f.exists()) await f.delete();
    }
    _pendingDeletes.clear();
    _discardOnRelease.clear();
    await _trim();
    _save();
    _notify();
  }

  Future<void> setCacheLimit(int mb) async {
    if (!cacheLimitsMb.contains(mb)) return;
    await initialize();
    cacheLimitMb = mb;
    _cacheEpoch++;
    await _trim();
    _save();
    _notify();
  }

  Future<void> clearCache() async {
    await initialize();
    _cacheEpoch++;
    for (final f in _files.values.where((f) => f.folder == 'cache').toList()) {
      if (_pinned.contains(f.id)) {
        _discardOnRelease.add(f.id);
        continue;
      }
      if (await _file(f).exists()) await _file(f).delete();
      _files.remove(f.id);
    }
    _save();
    _notify();
  }

  Future<void> _trim({int required = 0}) async {
    final entries =
        _files.values
            .where((f) => f.folder == 'cache' && !_pinned.contains(f.id))
            .toList()
          ..sort((a, b) => a.used.compareTo(b.used));
    for (final f in entries) {
      if (cacheBytes + required <= cacheLimitMb * 1024 * 1024) break;
      if (await _file(f).exists()) await _file(f).delete();
      _files.remove(f.id);
    }
  }

  Future<void> enqueue(
    Session s,
    Song song,
    String preference, {
    bool replace = false,
  }) async {
    await activate(s);
    if (_root == null) throw const ApiFailure('本机存储不可用');
    final id = fileKey(s, song, preference);
    if (replace && _pinned.contains(id)) {
      throw const ApiFailure('请先切换歌曲，再重新下载正在播放的文件');
    }
    if (_jobs.any((j) => j.id == id && j.state != DownloadState.completed)) {
      return;
    }
    _jobs.add(DownloadJob(id, _scope, song, preference, replace: replace));
    _save();
    _notify();
    unawaited(_drain());
  }

  Future<void> pause(DownloadJob j) async {
    if (j.state == DownloadState.completed) return;
    j.generation++;
    if (!j.interrupted.isCompleted) j.interrupted.complete();
    j.state = _committed(j) ? DownloadState.completed : DownloadState.paused;
    j.error = '继续将重新下载本首';
    if (_activeJob == j) await _cancelJobTransfer();
    _save();
    _notify();
  }

  void resume(DownloadJob j) {
    j.interrupted = Completer();
    j.error = null;
    j.received = 0;
    j.total = null;
    j.state = DownloadState.queued;
    _save();
    _notify();
    unawaited(_drain());
  }

  Future<void> cancel(DownloadJob j) async {
    await pause(j);
    _jobs.remove(j);
    _save();
    _notify();
  }

  bool _committed(DownloadJob j) {
    final id = sha256
        .convert(
          utf8.encode(
            jsonEncode([j.scope, j.song.id, j.actualQuality ?? j.preference]),
          ),
        )
        .toString();
    final f = _files[id];
    if (f == null || f.folder != 'downloads' || !f.valid) return false;
    if (_activeJob == j && _jobTransfer != null) {
      return _jobTransfer!.complete &&
          _file(f).path == _jobTransfer!.target.path;
    }
    return !j.replace;
  }

  Future<void> _cancelJobTransfer() async {
    final transfer = _jobTransfer;
    if (transfer == null) return;
    final saved = _files.values.any(
      (f) => f.folder == 'downloads' && _file(f).path == transfer.target.path,
    );
    await transfer.cancel(removeComplete: !saved);
  }

  Future<void> _drain() async {
    if (_running || _session == null || _disposed) return;
    _running = true;
    try {
      while (!_disposed && _session != null) {
        final job = _jobs
            .where((j) => j.scope == _scope && j.state == DownloadState.queued)
            .firstOrNull;
        if (job == null) break;
        await _run(job, _session!);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(DownloadJob job, Session s) async {
    final version = job.generation;
    final interrupted = job.interrupted.future;
    _activeJob = job;
    job.state = DownloadState.resolving;
    _notify();
    bool current() =>
        !_disposed &&
        job.generation == version &&
        _scope == job.scope &&
        _session != null;
    try {
      final result = await loadWithQualityFallback(
        song: job.song,
        preference: job.preference,
        localFirst: false,
        respectMetadata: !job.replace,
        localFile: (q) =>
            job.replace ? Future.value(null) : localResource(s, job.song, q),
        serverCache: (q) => api.cachedPlayback(s, job.song, q),
        resolve: (q) => api.resolvePlayback(s, job.song, quality: q),
        resolveFromSources: (q, excluded) => api.resolvePlayback(
          s,
          job.song,
          quality: q,
          excludeApiSources: excluded,
        ),
        load: (r) async {
          final key = fileKey(s, job.song, r.requestedQuality);
          final playing = _cacheKey == key && _cacheAccepted
              ? _cacheTransfer
              : null;
          if (playing != null && !job.replace) {
            job.state = DownloadState.downloading;
            job.received = playing.received;
            job.total = playing.total;
            _notify();
            final previous = playing.onProgress;
            void progress() {
              previous?.call();
              if (current()) {
                job.received = playing.received;
                job.total = playing.total;
                _notify();
              }
            }

            playing.onProgress = progress;
            try {
              await Future.any([
                playing.done,
                interrupted.then((_) => throw TransferCancelled()),
              ]);
            } catch (_) {
              if (!current()) throw TransferCancelled();
            } finally {
              if (playing.onProgress == progress) playing.onProgress = previous;
            }
            if (!current()) throw TransferCancelled();
            if (playing.complete && _files[key] == null) {
              final ext = playing.target.path.substring(
                playing.target.path.lastIndexOf('.'),
              );
              _files[key] = LocalAudio(
                id: key,
                scope: job.scope,
                song: job.song,
                quality: r.requestedQuality,
                reportedQuality: r.reportedQuality,
                folder: 'cache',
                ext: ext,
                bytes: playing.received,
                used: DateTime.now().millisecondsSinceEpoch,
              );
            }
          }
          final existing = _files[key];
          if (!job.replace &&
              existing != null &&
              existing.valid &&
              await _file(existing).exists()) {
            if (existing.folder == 'downloads') return;
            final to = File('${_root!.path}/downloads/$key${existing.ext}');
            await _file(existing).copy(to.path);
            if (!current()) {
              if (await to.exists()) await to.delete();
              throw TransferCancelled();
            }
            _files[key] = LocalAudio(
              id: key,
              scope: job.scope,
              song: job.song,
              quality: r.requestedQuality,
              reportedQuality: existing.reportedQuality,
              folder: 'downloads',
              ext: existing.ext,
              bytes: existing.bytes,
              used: DateTime.now().millisecondsSinceEpoch,
            );
            if (_pinned.contains(key)) _pendingDeletes.add(_file(existing));
            if (!_pinned.contains(key) && await _file(existing).exists()) {
              await _file(existing).delete();
            }
            return;
          }
          job.state = DownloadState.downloading;
          job.received = 0;
          job.total = null;
          _notify();
          final transfer = await AudioTransfer.open(
            r.url,
            '${_root!.path}/downloads/${sha256.convert(utf8.encode('$key:${DateTime.now().microsecondsSinceEpoch}:${job.generation}'))}',
          );
          _jobTransfer = transfer;
          if (!current()) {
            await transfer.cancel(removeComplete: true);
            throw TransferCancelled();
          }
          var tick = DateTime.fromMillisecondsSinceEpoch(0);
          transfer.onProgress = () {
            if (!current()) return;
            job.received = transfer.received;
            job.total = transfer.total;
            if (DateTime.now().difference(tick) >
                const Duration(milliseconds: 200)) {
              tick = DateTime.now();
              _notify();
            }
          };
          await transfer.done;
          if (!current()) {
            await transfer.cancel(removeComplete: true);
            throw TransferCancelled();
          }
          final ext = transfer.target.path.substring(
            transfer.target.path.lastIndexOf('.'),
          );
          _files[key] = LocalAudio(
            id: key,
            scope: job.scope,
            song: job.song,
            quality: r.requestedQuality,
            reportedQuality: r.reportedQuality,
            folder: 'downloads',
            ext: ext,
            bytes: transfer.received,
            used: DateTime.now().millisecondsSinceEpoch,
            storageId: transfer.target.uri.pathSegments.last.split('.').first,
          );
          if (existing != null &&
              _file(existing).path != transfer.target.path) {
            if (_pinned.contains(key)) {
              _pendingDeletes.add(_file(existing));
            } else if (await _file(existing).exists()) {
              await _file(existing).delete();
            }
          }
        },
        isCurrent: current,
        onAttempt: (quality) {
          job.actualQuality = quality;
          if (current()) _notify();
        },
      );
      if (!current()) return;
      if (result != null) {
        job.state = DownloadState.completed;
        job.error = null;
        unawaited(_ensureArtwork(job.scope, job.song));
      }
    } catch (e) {
      if (current()) {
        job.state = DownloadState.failed;
        job.error = e is ApiFailure ? e.message : '下载失败，请重试';
        if (e is ApiFailure &&
            (e.kind == FailureKind.server ||
                e.kind == FailureKind.rateLimited)) {
          for (final pending in _jobs.where(
            (j) =>
                j.scope == job.scope &&
                j.song.source == job.song.source &&
                j.state == DownloadState.queued,
          )) {
            pending.state = DownloadState.paused;
            pending.error = '该平台请求失败，已暂停后续下载，请稍后手动继续';
          }
        }
        if (e is ApiFailure && e.unauthorized) onUnauthorized();
      }
    } finally {
      _jobTransfer = null;
      _activeJob = null;
      _save();
      _notify();
    }
  }

  Future<void> deleteDownload(LocalAudio f) async {
    if (f.scope != _scope || f.folder != 'downloads') return;
    if (_pinned.contains(f.id)) throw const ApiFailure('请先切换歌曲，再删除正在播放的文件');
    if (await _file(f).exists()) await _file(f).delete();
    _files.remove(f.id);
    if (!_needsArtwork(f.scope, f.song)) {
      await _artwork?.remove(artworkKey(f.scope, f.song));
    }
    _jobs.removeWhere(
      (j) =>
          j.scope == f.scope &&
          j.song.id == f.song.id &&
          j.state == DownloadState.completed,
    );
    _save();
    _notify();
  }

  void _save() {
    if (_root == null || _disposed) return;
    final snapshot = jsonEncode({
      'cacheLimitMb': cacheLimitMb,
      'files': _files.values.map((f) => f.toJson()).toList(),
      'jobs': _jobs
          .where((j) => j.state != DownloadState.completed)
          .map((j) => j.toJson())
          .toList(),
    });
    final root = _root!;
    _writes = _writes
        .then((_) async {
          final temp = File('${root.path}/index.json.tmp');
          await temp.writeAsString(snapshot, flush: true);
          await temp.rename('${root.path}/index.json');
        })
        .catchError((Object _) {
          storageError = '本机文件记录保存失败';
        });
  }

  Future<void> flush() => _writes;
  @override
  void dispose() {
    _disposed = true;
    _artwork?.dispose();
    for (final j in _jobs) {
      j.generation++;
      if (!j.interrupted.isCompleted) j.interrupted.complete();
    }
    unawaited(_jobTransfer?.cancel() ?? Future.value());
    unawaited(releasePlayback());
    super.dispose();
  }
}
