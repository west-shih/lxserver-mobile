import 'dart:async';

import 'playback_mode.dart';
import 'playback_resume.dart';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/lx_api.dart';
import 'lyrics.dart';
import 'quality.dart';
import 'playback_cache.dart';
import '../local_media/local_media_controller.dart';
import '../local_media/audio_transfer.dart';

class PlayerController extends ChangeNotifier {
  PlayerController(
    this.api,
    this.onUnauthorized, {
    this.onQualityChanged,
    this.onModeChanged,
    PlaybackCache? cache,
    this.serverQualities,
    this.localMedia,
  }) : cache = cache ?? PlaybackCache();
  final PlaybackCache cache;
  final LocalMediaController? localMedia;
  final CachedAudioProxy _cacheProxy = CachedAudioProxy();
  final LxApi api;
  final Iterable<String> Function(Song)? serverQualities;
  void refreshQualityAvailability() => notifyListeners();
  Iterable<String> get _verifiedQualities => [
    ?reportedQuality,
    if (current != null) ...?serverQualities?.call(current!),
    if (current != null) ...?localMedia?.folders(current!).keys,
  ];
  List<AudioQuality> get knownQualityOptions => current == null
      ? []
      : QualityPolicy.knownOptions(current!, verified: _verifiedQualities);
  List<AudioQuality> get unverifiedQualityOptions => current == null
      ? []
      : QualityPolicy.unverifiedOptions(current!, verified: _verifiedQualities);
  final VoidCallback onUnauthorized;
  final Future<void> Function(String)? onQualityChanged;
  String preferredQuality = 'flac';
  String _playbackPreference = 'flac';
  Future<void> setPreferredQuality(String value) async {
    if (AudioQuality.find(value) == null || value == preferredQuality) return;
    preferredQuality = value;
    cache.clear(keepConfiguration: true);
    notifyListeners();
    try {
      await onQualityChanged?.call(value);
    } catch (_) {
      throw const ApiFailure('首选音质已修改，但未能保存到本机');
    }
  }

  String? requestedQuality;
  String? reportedQuality;
  String? qualityNotice;
  bool changingQuality = false;
  String? qualityTarget;
  bool qualityFailed = false;
  PlaybackResource? _resource;
  String get qualityLabel => AudioQuality.labelOf(reportedQuality);
  List<AudioQuality> get qualityOptions =>
      current == null ? [] : QualityPolicy.selectable(current!);
  void restoreQuality(String? value) {
    preferredQuality = AudioQuality.find(value)?.id ?? 'flac';
  }

  void _applyResource(PlaybackResource resource) {
    _resource = resource;
    requestedQuality = resource.requestedQuality;
    reportedQuality = AudioQuality.find(resource.reportedQuality)?.id;
    if (resource.localFile) qualityNotice = null;
    final session = _session;
    final song = current;
    if (session != null && song != null) {
      localMedia?.confirmPlayback(session, song, resource.requestedQuality);
    }
    if (!resource.localFile && requestedQuality != _playbackPreference) {
      qualityNotice = '请求音质不可用，已使用${AudioQuality.labelOf(requestedQuality)}';
    }
    if (reportedQuality == null) {
      qualityNotice = '已请求${AudioQuality.labelOf(requestedQuality)}，服务器未确认音质';
    }
  }

  AudioPlayer? _audio;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<Song> _queue = [];
  List<Song> get queue => List.unmodifiable(_queue);
  int index = -1;
  PlaybackMode mode = PlaybackMode.order;
  final Future<void> Function(String)? onModeChanged;
  void restoreMode(String? value) {
    mode =
        PlaybackMode.values.where((m) => m.name == value).firstOrNull ??
        PlaybackMode.order;
  }

  bool _advancing = false;
  bool _needsResume = false;
  PlaybackSnapshot? snapshot(Session session) => current == null
      ? null
      : PlaybackSnapshot(
          scope: PlaybackSnapshot.scopeFor(session),
          songs: queue,
          index: index,
          position: position,
          duration: duration,
          quality: requestedQuality,
          reportedQuality: reportedQuality,
        );
  void restorePlayback(Session session, PlaybackSnapshot state) {
    if (state.scope != PlaybackSnapshot.scopeFor(session)) return;
    _session = session;
    _queue
      ..clear()
      ..addAll(state.songs);
    index = state.index;
    position = state.position;
    duration = state.duration;
    requestedQuality = state.quality;
    reportedQuality = state.reportedQuality;
    _playbackPreference = state.quality ?? preferredQuality;
    playing = false;
    _needsResume = true;
    notifyListeners();
  }

  void setMode(PlaybackMode value) {
    mode = value;
    unawaited(
      onModeChanged?.call(value.name).catchError((Object _) {}) ??
          Future.value(),
    );
    notifyListeners();
  }

  bool get canNext => nextQueueIndex(mode, index, _queue.length) != null;
  bool get canPrevious =>
      index > 0 || (mode != PlaybackMode.order && _queue.isNotEmpty);
  Song? get current =>
      index >= 0 && index < _queue.length ? _queue[index] : null;
  Session? _session;
  bool resolving = false;
  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  String? error;
  int _generation = 0;
  int _lyricVersion = 0;
  Lyrics lyrics = const Lyrics([], '');
  bool loadingLyrics = false;
  String? lyricError;

  Future<void> loadLyrics() async {
    final session = _session;
    final song = current;
    if (session == null || song == null) return;
    final version = ++_lyricVersion;
    loadingLyrics = true;
    lyricError = null;
    lyrics = const Lyrics([], '');
    notifyListeners();
    try {
      final data = await api.lyrics(session, song);
      if (version != _lyricVersion) return;
      lyrics = Lyrics.parse(data);
    } on ApiFailure catch (e) {
      if (version != _lyricVersion) return;
      lyricError = e.message;
      if (e.unauthorized) onUnauthorized();
    } catch (_) {
      if (version == _lyricVersion) lyricError = '歌词暂时无法加载';
    } finally {
      if (version == _lyricVersion) {
        loadingLyrics = false;
        notifyListeners();
      }
    }
  }

  AudioPlayer get audio {
    if (_audio != null) return _audio!;
    final player = _audio = AudioPlayer();
    _subscriptions.add(
      player.playerStateStream.listen((state) {
        playing = state.playing;
        if (state.processingState == ProcessingState.completed && !_advancing) {
          unawaited(_completed());
        }
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.positionStream.listen((value) {
        if (_needsResume) return;
        position = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.durationStream.listen((value) {
        duration = value ?? Duration.zero;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.errorStream.listen((_) {
        // setUrl failures are handled by the fallback loop. Don't flash an error mid-retry.
        if (resolving || changingQuality || current == null) return;
        final song = current;
        final session = _session;
        if (song != null && session != null && requestedQuality != null) {
          cache.invalidateUrl(cache.scope(session), song, requestedQuality!);
        }
        error = '音频加载失败，请重试或切换平台';
        playing = false;
        notifyListeners();
      }),
    );
    return player;
  }

  Future<void> play(
    Session session,
    Song song, {
    List<Song>? songs,
    String? quality,
    Duration? resumePosition,
  }) async {
    if (resolving) return;
    final previousDuration = duration;
    _needsResume = false;
    _session = session;
    _playbackPreference = quality ?? preferredQuality;
    if (songs != null) {
      _queue
        ..clear()
        ..addAll(songs);
    }
    index = _queue.indexWhere((s) => s.id == song.id);
    if (index < 0) {
      _queue.add(song);
      index = _queue.length - 1;
    }
    final generation = ++_generation;
    final cacheScope = cache.scope(session);
    changingQuality = false;
    qualityTarget = null;
    qualityFailed = false;
    requestedQuality = QualityPolicy.initial(song, preferredQuality);
    reportedQuality = null;
    _resource = null;
    qualityNotice = requestedQuality == preferredQuality
        ? null
        : '当前平台使用${AudioQuality.labelOf(requestedQuality)}，首选${AudioQuality.labelOf(preferredQuality)}';
    unawaited(loadLyrics());
    resolving = true;
    error = null;
    position = resumePosition ?? Duration.zero;
    duration = resumePosition == null ? Duration.zero : previousDuration;
    notifyListeners();
    try {
      await audio.stop();
      await localMedia?.releasePlayback();
      final resource = await loadWithQualityFallback(
        localFile: (q) =>
            localMedia?.localResource(session, song, q) ?? Future.value(),
        serverCache: (quality) => api.cachedPlayback(session, song, quality),
        resolveFromSources: (quality, excluded) => api.resolvePlayback(
          session,
          song,
          quality: quality,
          excludeApiSources: excluded,
        ),
        cache: cache,
        scope: cacheScope,
        song: song,
        preference: quality ?? preferredQuality,
        respectMetadata: quality == null,
        resolve: (quality) =>
            api.resolvePlayback(session, song, quality: quality),
        load: (resource) async {
          // Never send LX credentials to a third-party audio CDN.
          await _loadResource(
            session,
            song,
            resource,
            initialPosition: resumePosition,
          );
        },
        isCurrent: () =>
            generation == _generation && cache.scope(session) == cacheScope,
        onAttempt: (quality) {
          qualityTarget = quality;
          requestedQuality = quality;
          qualityNotice = '正在尝试${AudioQuality.labelOf(quality)}';
          notifyListeners();
        },
      );
      if (resource == null || generation != _generation) {
        if (generation == _generation) {
          qualityNotice = null;
          error = '音源配置已更新，请重新播放';
        }
        return;
      }
      qualityNotice = null;
      error = null;
      _applyResource(resource);
      unawaited(
        audio.play().catchError((Object _) {
          if (generation == _generation) {
            error = '播放失败，请重试';
            notifyListeners();
          }
        }),
      );
    } on ApiFailure catch (e) {
      if (generation != _generation) return;
      error = e.message;
      if (e.unauthorized) onUnauthorized();
    } catch (_) {
      if (generation == _generation) error = '无法播放这首歌，请重试或切换平台';
    } finally {
      if (generation == _generation) {
        resolving = false;
        if (error != null && resumePosition != null) {
          position = resumePosition;
          duration = previousDuration;
          _needsResume = true;
        }
        notifyListeners();
      }
    }
  }

  Future<void> retryPreferredQuality() async {
    await changeQuality(preferredQuality, retry: true, remember: true);
  }

  Future<void> changeQuality(
    String value, {
    bool retry = true,
    bool remember = false,
  }) async {
    final session = _session;
    final song = current;
    if (session == null ||
        song == null ||
        resolving ||
        changingQuality ||
        (!qualityOptions.any((v) => v.id == value) &&
            value != preferredQuality)) {
      return;
    }
    final generation = ++_generation;
    final cacheScope = cache.scope(session);
    if (retry && remember) cache.forget(cacheScope, song);
    final previousPreference = _playbackPreference;
    _playbackPreference = value;
    changingQuality = true;
    qualityTarget = value;
    qualityFailed = false;
    error = null;
    qualityNotice = null;
    notifyListeners();
    final previousResource = _resource;
    var replacedAudio = false;
    var resume = false;
    var savedPosition = position;
    try {
      if (generation != _generation) return;
      final resource = await loadWithQualityFallback(
        localFile: (q) =>
            localMedia?.localResource(session, song, q) ?? Future.value(),
        localFirst: false,
        serverCache: (quality) => api.cachedPlayback(session, song, quality),
        resolveFromSources: (quality, excluded) => api.resolvePlayback(
          session,
          song,
          quality: quality,
          excludeApiSources: excluded,
        ),
        cache: remember ? cache : null,
        scope: cacheScope,
        respectMetadata: false,
        song: song,
        preference: value,
        resolve: (quality) =>
            api.resolvePlayback(session, song, quality: quality),
        load: (resource) async {
          if (!replacedAudio) {
            savedPosition = position;
            resume = playing;
          }
          resolving = true;
          replacedAudio = true;
          notifyListeners();
          await _loadResource(
            session,
            song,
            resource,
            initialPosition: savedPosition,
          );
        },
        isCurrent: () =>
            generation == _generation && cache.scope(session) == cacheScope,
        onAttempt: (quality) {
          qualityTarget = quality;
          qualityNotice = '正在尝试${AudioQuality.labelOf(quality)}';
          notifyListeners();
        },
      );
      if (resource == null || generation != _generation) {
        if (generation == _generation) qualityNotice = '音源配置已更新，请重新尝试';
        return;
      }
      qualityNotice = null;
      _applyResource(resource);
      _needsResume = false;
      error = null;
      if (resume) {
        unawaited(
          audio.play().catchError((Object _) {
            if (generation == _generation) {
              error = '播放失败，请重试';
              notifyListeners();
            }
          }),
        );
      } else {
        await audio.pause();
      }
      if (reportedQuality != null && qualityNotice == null) {
        qualityNotice = '已切换为$qualityLabel';
      }
    } catch (e) {
      if (generation != _generation) return;
      _playbackPreference = previousPreference;
      if (e is ApiFailure && e.unauthorized) {
        onUnauthorized();
        return;
      }
      qualityFailed = true;
      qualityNotice = e is ApiFailure
          ? '${e.message}${previousResource == null ? '' : '，保持原音质'}'
          : '音频加载失败';
      if (replacedAudio) {
        try {
          if (previousResource == null) throw StateError('No previous audio');
          await _loadResource(
            session,
            song,
            previousResource,
            initialPosition: savedPosition,
          );
          if (generation != _generation) return;
          _applyResource(previousResource);
          if (remember &&
              cache.scope(session) == cacheScope &&
              QualityPolicy.attempts(
                song,
                preferredQuality,
                respectMetadata: false,
              ).contains(previousResource.requestedQuality)) {
            cache.success(
              cacheScope,
              song,
              previousResource,
              preference: preferredQuality,
            );
          }
          error = null;
          qualityNotice = '切换音质失败，已恢复原音频';
          if (resume) {
            unawaited(
              audio.play().catchError((Object _) {
                if (generation == _generation) {
                  error = '恢复播放失败，请重试';
                  notifyListeners();
                }
              }),
            );
          } else {
            await audio.pause();
          }
        } catch (_) {
          if (generation == _generation) {
            error = '切换失败，请重新播放';
            qualityNotice = null;
          }
        }
      }
    } finally {
      if (generation == _generation) {
        changingQuality = false;
        resolving = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadResource(
    Session session,
    Song song,
    PlaybackResource r, {
    Duration? initialPosition,
  }) async {
    final generation = _generation;
    await audio.stop();
    _cacheProxy.clear();
    await localMedia?.releasePlayback();
    if (generation != _generation) throw TransferCancelled();
    if (r.localFile) {
      try {
        await localMedia?.pin(session, song, r.requestedQuality);
        await audio.setAudioSource(
          AudioSource.uri(r.url),
          initialPosition: initialPosition,
        );
      } catch (_) {
        if (generation == _generation) {
          await localMedia?.invalidate(session, song, r.requestedQuality);
        }
        rethrow;
      }
      return;
    }
    AudioTransfer? transfer;
    try {
      transfer = await localMedia?.prepareCache(session, song, r);
      if (generation != _generation) throw TransferCancelled();
      if (transfer == null) {
        await audio.setUrl(r.url.toString(), initialPosition: initialPosition);
        return;
      }
      await audio.setAudioSource(
        AudioSource.uri(await _cacheProxy.add(transfer)),
        initialPosition: initialPosition,
      );
      await localMedia?.acceptCache(session, song, r, transfer);
    } catch (e) {
      if (generation == _generation) {
        await localMedia?.releasePlayback();
      } else if (transfer != null) {
        await localMedia?.releasePlayback(only: transfer);
      }
      if (e is ApiFailure && e.kind == FailureKind.storage) {
        await audio.setUrl(r.url.toString(), initialPosition: initialPosition);
      } else {
        rethrow;
      }
    }
  }

  Future<void> toggle() async {
    if (resolving || current == null) return;
    if (_needsResume && _session != null) {
      await play(
        _session!,
        current!,
        quality: requestedQuality,
        resumePosition: position,
      );
      return;
    }
    if (error != null && _session != null) {
      await play(_session!, current!);
      return;
    }
    try {
      if (playing) {
        await audio.pause();
      } else {
        unawaited(
          audio.play().catchError((Object _) {
            error = '播放失败，请重试';
            notifyListeners();
          }),
        );
      }
    } catch (_) {
      error = '播放操作失败，请重试';
      notifyListeners();
    }
  }

  Future<void> next() async {
    final target = nextQueueIndex(mode, index, _queue.length);
    if (_session != null && target != null) {
      await play(_session!, _queue[target]);
    }
  }

  Future<void> previous() async {
    if (_session == null || !canPrevious) return;
    final target = mode == PlaybackMode.random
        ? nextQueueIndex(mode, index, _queue.length)!
        : index > 0
        ? index - 1
        : _queue.length - 1;
    await play(_session!, _queue[target]);
  }

  Future<void> _completed() async {
    _advancing = true;
    try {
      final target = nextQueueIndex(
        mode,
        index,
        _queue.length,
        completed: true,
      );
      if (target != null && _session != null) {
        await play(_session!, _queue[target]);
      } else {
        await audio.pause();
        await audio.seek(Duration.zero);
      }
    } finally {
      _advancing = false;
    }
  }

  Future<void> select(int value) async {
    if (_session != null) await play(_session!, _queue[value]);
  }

  void enqueue(Session session, Song song) {
    _session = session;
    if (!_queue.any((s) => s.id == song.id)) _queue.add(song);
    notifyListeners();
  }

  Future<void> remove(int value) async {
    if (resolving || value < 0 || value >= _queue.length) return;
    final wasCurrent = value == index;
    _queue.removeAt(value);
    if (wasCurrent) {
      if (_queue.isEmpty) {
        await reset();
      } else if (_session != null) {
        await play(_session!, _queue[value.clamp(0, _queue.length - 1)]);
      }
    } else {
      if (value < index) index--;
      notifyListeners();
    }
  }

  Future<void> seek(Duration value) async {
    if (_needsResume) {
      position = Duration(
        milliseconds: value.inMilliseconds.clamp(
          0,
          duration.inMilliseconds > 0
              ? duration.inMilliseconds
              : value.inMilliseconds,
        ),
      );
      notifyListeners();
      return;
    }
    try {
      await _audio?.seek(value);
    } catch (_) {
      error = '暂时无法调整进度';
      notifyListeners();
    }
  }

  Future<void> reset() async {
    _needsResume = false;
    ++_generation;
    cache.clear();
    ++_lyricVersion;
    lyrics = const Lyrics([], '');
    loadingLyrics = false;
    lyricError = null;
    resolving = false;
    _session = null;
    _queue.clear();
    index = -1;
    error = null;
    requestedQuality = null;
    qualityTarget = null;
    qualityFailed = false;
    reportedQuality = null;
    qualityNotice = null;
    changingQuality = false;
    _resource = null;
    playing = false;
    position = Duration.zero;
    duration = Duration.zero;
    await _audio?.stop();
    _cacheProxy.clear();
    await localMedia?.releasePlayback();
    notifyListeners();
  }

  @override
  void dispose() {
    ++_generation;
    ++_lyricVersion;
    for (final s in _subscriptions) {
      s.cancel();
    }
    _audio?.dispose();
    unawaited(_cacheProxy.close());
    super.dispose();
  }
}
