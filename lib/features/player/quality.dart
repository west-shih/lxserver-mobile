import '../../core/lx_api.dart';
import 'playback_cache.dart';

class AudioQuality {
  const AudioQuality(this.id, this.label, this.detail);
  final String id;
  final String label;
  final String detail;
  static const values = [
    AudioQuality('128k', '标准', '128 kbps'),
    AudioQuality('192k', '较高', '192 kbps'),
    AudioQuality('320k', '高品质', '320 kbps'),
    AudioQuality('flac', '无损', 'FLAC'),
    AudioQuality('flac24bit', '24bit 无损', '24-bit FLAC'),
    AudioQuality('hires', 'Hi-Res', '高解析度'),
    AudioQuality('atmos', '空间音频', '需解析源支持'),
    AudioQuality('atmos_plus', '增强空间音频', '需解析源支持'),
    AudioQuality('master', '母带', '需解析源支持'),
    AudioQuality('wav', 'WAV', '需解析源支持'),
  ];
  static AudioQuality? find(String? id) =>
      values.where((v) => v.id == id).firstOrNull;
  static String labelOf(String? id) => find(id)?.label ?? '音质未确认';
}

class QualityPolicy {
  static List<AudioQuality> knownOptions(
    Song song, {
    Iterable<String> verified = const [],
  }) {
    final known = advertised(song)..addAll(verified);
    final explicit = song.raw['quality'] ?? song.raw['type'];
    if (explicit is String) known.add(explicit);
    return selectable(song).where((q) => known.contains(q.id)).toList();
  }

  static List<AudioQuality> unverifiedOptions(
    Song song, {
    Iterable<String> verified = const [],
  }) {
    if (hasCompleteMetadata(song)) return [];
    final known = knownOptions(
      song,
      verified: verified,
    ).map((q) => q.id).toSet();
    return selectable(song).where((q) => !known.contains(q.id)).toList();
  }

  static bool hasCompleteMetadata(Song song) {
    if (!song.freshQualityMetadata || advertised(song).isEmpty) return false;
    final meta = song.raw['meta'] is Map ? song.raw['meta'] as Map : {};
    bool synthetic(Object? value) {
      final entries = value is List
          ? value
          : value is Map
          ? value.values
          : const [];
      return entries.any((v) => v is Map && v['isPlatformQuality'] == true);
    }

    return ![
      song.raw['types'],
      song.raw['_types'],
      song.raw['qualitys'],
      song.raw['_qualitys'],
      meta['qualitys'],
      meta['_qualitys'],
      meta['types'],
      meta['_types'],
    ].any(synthetic);
  }

  /// Mirrors upstream app.js getQualityTags: only concrete song metadata.
  static String? badge(Song song, {Iterable<String> verified = const []}) {
    final ids = advertised(song)..addAll(verified);
    final explicit = song.raw['quality'] ?? song.raw['type'];
    if (explicit is String && AudioQuality.find(explicit) != null) {
      ids.add(explicit);
    }
    if (ids.contains('master')) return 'Master';
    if (ids.contains('atmos') || ids.contains('atmos_plus')) return 'Atmos';
    if (ids.contains('hires') || ids.contains('flac24bit')) return 'Hi-Res';
    if (ids.contains('flac')) return '无损';
    if (ids.contains('320k')) return '高品质';
    return null;
  }

  static List<String> attempts(
    Song song,
    String preference, {
    bool respectMetadata = true,
  }) {
    final first = _platformInitial(song, preference);
    final available = selectable(song).map((v) => v.id).toSet();
    // Spatial modes are alternatives, not a descending fidelity ladder.
    final lower = switch (first) {
      'master' ||
      'hires' ||
      'flac24bit' ||
      'atmos' ||
      'atmos_plus' ||
      'wav' => ['flac', '320k', '192k', '128k'],
      'flac' => ['320k', '192k', '128k'],
      '320k' => ['192k', '128k'],
      '192k' => ['128k'],
      _ => <String>[],
    };
    final candidates = [first, ...lower.where(available.contains)];
    final known = advertised(song);
    if (respectMetadata && hasCompleteMetadata(song)) {
      return candidates.where(known.contains).toList();
    }
    return candidates;
  }

  static const priority = [
    'master',
    'atmos_plus',
    'atmos',
    'hires',
    'flac24bit',
    'flac',
    '320k',
    '192k',
    '128k',
  ];
  // Based on upstream public/music/js/player/quality.js, not a guarantee of track availability.
  static const _platforms = {
    MusicSource.tx: [
      '128k',
      '320k',
      'flac',
      'flac24bit',
      'hires',
      'atmos',
      'atmos_plus',
      'master',
    ],
    MusicSource.wy: [
      '128k',
      '320k',
      'flac',
      'flac24bit',
      'hires',
      'atmos',
      'master',
    ],
    MusicSource.kw: ['128k', '320k', 'flac', 'flac24bit', 'hires'],
    MusicSource.kg: ['128k', '320k', 'flac', 'flac24bit', 'hires'],
    MusicSource.mg: ['128k', '320k', 'flac'],
  };
  static Set<String> advertised(Song song) {
    final found = <String>{};
    final meta = song.raw['meta'] is Map ? song.raw['meta'] as Map : {};
    for (final data in [
      song.raw['types'],
      song.raw['_types'],
      song.raw['qualitys'],
      song.raw['_qualitys'],
      meta['qualitys'],
      meta['_qualitys'],
      meta['types'],
      meta['_types'],
    ]) {
      if (data is List) {
        for (final entry in data) {
          if (entry is Map && entry['isPlatformQuality'] == true) continue;
          final id = entry is String
              ? entry
              : entry is Map
              ? entry['type']
              : null;
          if (id is String && AudioQuality.find(id) != null) found.add(id);
        }
      } else if (data is Map) {
        for (final entry in data.entries) {
          if (entry.value == null ||
              entry.value == false ||
              (entry.value is Map &&
                  entry.value['isPlatformQuality'] == true)) {
            continue;
          }
          if (entry.key is String && AudioQuality.find(entry.key) != null) {
            found.add(entry.key as String);
          }
        }
      }
    }
    return found;
  }

  static List<AudioQuality> selectable(Song song) {
    final ids = {...?_platforms[song.source], ...advertised(song)};
    return AudioQuality.values.where((v) => ids.contains(v.id)).toList();
  }

  static String initial(Song song, String preference) =>
      attempts(song, preference).firstOrNull ??
      _platformInitial(song, preference);

  static String _platformInitial(Song song, String preference) {
    final choices = selectable(song).map((v) => v.id).toSet();
    if (choices.contains(preference)) return preference;
    // Old synchronized lists often advertise only 128k. That is not a source capability ceiling.
    return choices.contains('flac') ? 'flac' : '320k';
  }
}

/// Resolves and loads one track without changing its platform or saved preference.
Future<PlaybackResource?> loadWithQualityFallback({
  required Song song,
  required String preference,
  required Future<PlaybackResource> Function(String) resolve,
  required Future<void> Function(PlaybackResource) load,
  required bool Function() isCurrent,
  required void Function(String) onAttempt,
  PlaybackCache? cache,
  String scope = '',
  bool respectMetadata = true,
  Future<PlaybackResource?> Function(String)? serverCache,
  Future<PlaybackResource?> Function(String)? localFile,
  bool localFirst = false,
  bool recoverPlaybackConnection = false,
  Future<PlaybackResource> Function(String, List<String>)? resolveFromSources,
  Duration recoveryBudget = const Duration(seconds: 30),
  int maxResolutions = 4,
}) async {
  Object? failure;
  final watch = Stopwatch()..start();
  var resolutions = 0;
  var onlineUnavailable = false;
  var retriedConnection = false;
  bool fatal(Object e) =>
      e is ApiFailure &&
      (e.unauthorized ||
          e.kind == FailureKind.network ||
          e.kind == FailureKind.permission ||
          e.kind == FailureKind.server ||
          e.kind == FailureKind.rateLimited ||
          e.kind == FailureKind.storage);
  void validate(PlaybackResource resource) {
    if (AudioQuality.find(resource.reportedQuality) != null &&
        resource.reportedQuality != resource.requestedQuality) {
      throw const ApiFailure('音源返回音质与请求不符');
    }
  }

  final remembered = cache?.successful(scope, song, preference: preference);
  final supported = QualityPolicy.selectable(song).map((q) => q.id).toSet();
  final working = remembered != null && supported.contains(remembered)
      ? remembered
      : null;
  final planned = QualityPolicy.attempts(
    song,
    working ?? preference,
    respectMetadata: working == null && respectMetadata,
  );
  final candidates = [?working, ...planned.where((q) => q != working)];
  final checkedLocal = <String>{};
  Future<PlaybackResource?> tryLocal(
    String quality, {
    bool remember = true,
  }) async {
    if (!checkedLocal.add(quality)) return null;
    final local = await localFile?.call(quality);
    if (!isCurrent() || local == null) return null;
    try {
      onAttempt(quality);
      await load(local);
      if (!isCurrent()) return null;
      if (remember) cache?.success(scope, song, local, preference: preference);
      return local;
    } catch (e) {
      if (fatal(e)) rethrow;
      return null;
    }
  }

  Future<PlaybackResource?> recoverFromLocal() async {
    for (final quality in {...candidates, ...supported}) {
      if (!isCurrent()) return null;
      final local = await tryLocal(quality, remember: false);
      if (local != null) return local;
    }
    return null;
  }

  if (localFirst && localFile != null) {
    for (final quality in candidates) {
      if (!isCurrent()) return null;
      final local = await tryLocal(quality);
      if (local != null) return local;
    }
  }
  // A successful track keeps its working quality until it fails or the user retries.
  for (final quality in candidates) {
    if (!isCurrent()) return null;
    onAttempt(quality);
    if (watch.elapsed >= recoveryBudget) {
      throw const ApiFailure('播放准备超时，请重试', kind: FailureKind.network);
    }
    try {
      if (!localFirst && localFile != null) {
        final local = await tryLocal(quality);
        if (local != null) return local;
      }
      var resource = cache?.resource(scope, song, quality);
      if (resource?.localFile == true) {
        // The local file lookup above is authoritative after cache clearing/deletion.
        cache?.invalidateUrl(scope, song, quality);
        resource = null;
      }
      if (resource != null) {
        try {
          await load(resource);
          if (!isCurrent()) return null;
          cache?.success(
            scope,
            song,
            resource,
            reusedUrl: true,
            preference: preference,
          );
          return resource;
        } catch (e) {
          if (!isCurrent()) return null;
          cache?.invalidateUrl(scope, song, quality);
          if (fatal(e)) rethrow;
          // An expired signed URL does not prove this quality is unavailable.
        }
      }
      if (serverCache != null) {
        final local = await serverCache(quality);
        if (!isCurrent()) return null;
        if (local != null && local.url != resource?.url) {
          try {
            validate(local);
            await load(local);
            if (!isCurrent()) return null;
            cache?.success(scope, song, local, preference: preference);
            return local;
          } catch (e) {
            if (!isCurrent()) return null;
            if (fatal(e)) rethrow;
            // Stale/broken server cache must not prevent online resolution.
            cache?.invalidateUrl(scope, song, quality);
          }
        }
      }
      if (cache?.failed(scope, song, quality) == true && !onlineUnavailable) {
        continue;
      }
      if (onlineUnavailable) continue;
      final excluded = <String>{};
      while (resolutions < maxResolutions) {
        final remaining = recoveryBudget - watch.elapsed;
        if (remaining <= Duration.zero) {
          throw const ApiFailure('播放准备超时，请重试', kind: FailureKind.network);
        }
        resolutions++;
        try {
          resource =
              await (resolveFromSources == null
                      ? resolve(quality)
                      : resolveFromSources(quality, excluded.toList()))
                  .timeout(
                    remaining,
                    onTimeout: () => throw const ApiFailure(
                      '播放准备超时，请重试',
                      kind: FailureKind.network,
                    ),
                  );
        } on ApiFailure catch (e) {
          if (!isCurrent()) return null;
          const retryDelay = Duration(milliseconds: 350);
          if (!recoverPlaybackConnection ||
              !e.connectionFailed ||
              retriedConnection ||
              resolutions >= maxResolutions) {
            rethrow;
          }
          final local = await recoverFromLocal();
          if (local != null || !isCurrent()) return local;
          if (recoveryBudget - watch.elapsed <= retryDelay) rethrow;
          retriedConnection = true;
          await Future<void>.delayed(retryDelay);
          if (!isCurrent()) return null;
          continue;
        }
        if (!isCurrent()) return null;
        try {
          if (excluded.contains(resource.sourceId ?? resource.sourceName)) {
            throw const ApiFailure('解析源重复返回已失败的来源');
          }
          validate(resource);
          await load(resource);
          if (!isCurrent()) return null;
          cache?.success(scope, song, resource, preference: preference);
          return resource;
        } catch (e) {
          if (!isCurrent()) return null;
          if (fatal(e)) rethrow;
          cache?.invalidateUrl(scope, song, quality);
          final source = resource.sourceId ?? resource.sourceName;
          if (resolveFromSources == null ||
              !resource.hasMoreSources ||
              source == null ||
              source.isEmpty ||
              !excluded.add(source)) {
            rethrow;
          }
          failure = e;
        }
      }
      throw const ApiFailure('已达到本次播放重试次数，请重试');
    } catch (e) {
      if (!isCurrent()) return null;
      if (recoverPlaybackConnection &&
          e is ApiFailure &&
          e.kind == FailureKind.network) {
        final local = await recoverFromLocal();
        if (local != null || !isCurrent()) return local;
      }
      if (fatal(e)) rethrow;
      if (e is ApiFailure && e.kind == FailureKind.sourceUnavailable) {
        onlineUnavailable = true;
        failure = e;
        continue; // Existing server files may still be playable at lower qualities.
      }
      cache?.failure(scope, song, quality);
      failure = e;
    }
    if (resolutions >= maxResolutions) break;
  }
  if (failure is ApiFailure) throw failure;
  throw const ApiFailure('暂无可播放音质，可重新尝试首选音质');
}
