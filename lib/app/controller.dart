import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/lx_api.dart';
import '../core/session_store.dart';
import '../features/player/player_controller.dart';
import '../features/player/playback_cache.dart';
import '../features/player/playback_resume.dart';
import '../features/library/library_controller.dart';
import '../features/library/server_files_controller.dart';
import '../features/local_media/local_media_controller.dart';
import '../features/discovery/discovery_controller.dart';
import '../features/search/source_availability.dart';

class AppController extends ChangeNotifier {
  AppController({LxApi? api, Future<Directory> Function()? mediaDirectory})
    : api = api ?? LxApi() {
    serverFiles = ServerFilesController(this.api, expire);
    localMedia = LocalMediaController(
      this.api,
      expire,
      directory: mediaDirectory,
    );
    player = PlayerController(
      this.api,
      expire,
      onQualityChanged: store.saveQuality,
      onModeChanged: store.saveMode,
      cache: PlaybackCache(saveHistory: store.savePlaybackHistory),
      serverQualities: (song) => serverFiles.folders(song).keys,
      localMedia: localMedia,
    );
    playbackResume = PlaybackResumeStore(directory: mediaDirectory);
    player.addListener(_rememberPlayback);
    serverFiles.addListener(player.refreshQualityAvailability);
    localMedia.addListener(player.refreshQualityAvailability);
    library = LibraryController(this.api, expire);
    discovery = DiscoveryController(this.api, expire);
  }
  final LxApi api;
  final store = SessionStore();
  bool pagedCollections = false;
  static const collectionPageSizes = [10, 20, 30, 50, 100];
  int collectionPageSize = 20;
  Future<void> setCollectionPageSize(int value) async {
    if (!collectionPageSizes.contains(value)) return;
    await store.saveCollectionPageSize(value);
    collectionPageSize = value;
    notifyListeners();
  }

  Future<void> setPagedCollections(bool value) async {
    await store.saveListMode(value);
    pagedCollections = value;
    notifyListeners();
  }

  late final PlayerController player;
  late final PlaybackResumeStore playbackResume;
  String? _lastResumeSong;
  int _lastResumeQueueLength = -1;
  void _rememberPlayback() {
    final active = session;
    if (restoring ||
        active == null ||
        player.resolving ||
        player.changingQuality ||
        player.error != null) {
      return;
    }
    final state = player.snapshot(active);
    if (state != null) {
      final changed =
          _lastResumeSong != player.current!.id ||
          _lastResumeQueueLength != state.songs.length;
      _lastResumeSong = player.current!.id;
      _lastResumeQueueLength = state.songs.length;
      playbackResume.schedule(state, immediately: changed || !player.playing);
    } else if (player.queue.isEmpty) {
      _lastResumeSong = null;
      _lastResumeQueueLength = -1;
      unawaited(playbackResume.clear());
    }
  }

  Future<void> flushPlayback() {
    _rememberPlayback();
    return playbackResume.flush();
  }

  late final ServerFilesController serverFiles;
  late final LocalMediaController localMedia;
  bool offlineMode = false;
  Future<void> refreshServerFiles({bool force = false}) async {
    final active = session;
    if (active != null) await serverFiles.ensure(active, force: force);
  }

  Future<void> refreshLibrary() async {
    final active = session;
    if (active != null && offlineMode) {
      try {
        if (!await api.verify(active)) {
          expire();
          return;
        }
        offlineMode = false;
      } on ApiFailure catch (e) {
        if (e.unauthorized) expire();
        return;
      }
    }
    if (active != null) {
      await Future.wait([
        library.load(active),
        refreshServerFiles(force: true),
      ]);
      if (session == active) {
        localMedia.updateArtwork(library.collections.expand((c) => c.songs));
      }
    }
  }

  late final LibraryController library;
  late final DiscoveryController discovery;
  Session? session;
  String server = '';
  String? authError;
  bool restoring = true;
  bool loggingIn = false;
  bool searching = false;
  String? searchError;
  String keyword = '';
  MusicSource source = MusicSource.kw;
  bool aggregate = true;
  SourceAvailability? availability;
  bool checkingSources = false;
  String? sourceError;
  List<MusicSource> get availableSources =>
      availability?.platforms ?? MusicSource.values;
  final Map<MusicSource, List<Song>> _buckets = {};
  final Map<MusicSource, int> _pages = {};
  final Set<MusicSource> _more = {};
  final Map<MusicSource, String> sourceFailures = {};
  int _capabilityVersion = 0;
  List<Song> songs = [];
  int page = 0;
  bool hasMore = false;
  int _searchVersion = 0;
  Future<void> restore() async {
    Session? saved;
    try {
      pagedCollections = await store.readListMode() == 'true';
      final savedPageSize = int.tryParse(
        await store.readCollectionPageSize() ?? '',
      );
      collectionPageSize = collectionPageSizes.contains(savedPageSize)
          ? savedPageSize!
          : 20;
      server = await store.server() ?? '';
      player.restoreQuality(await store.readQuality());
      player.restoreMode(await store.readMode());
      player.cache.restore(await store.readPlaybackHistory());
      saved = await store.read();
      if (saved != null) {
        if (await api.verify(saved)) {
          session = saved;
        } else {
          await store.clear();
          await playbackResume.clear();
          authError = '登录已失效，请重新登录';
        }
      }
    } on ApiFailure catch (e) {
      if (saved != null && e.kind == FailureKind.network) {
        session = saved;
        offlineMode = true;
        authError = null;
      } else {
        authError = e.message;
        if (e.unauthorized) {
          await store.clear();
          await playbackResume.clear();
        }
      }
    } catch (_) {
      authError = '无法恢复登录，请重新登录';
    }
    if (session != null) {
      await localMedia.activate(session!);
      final state = await playbackResume.read(session!);
      if (state != null) player.restorePlayback(session!, state);
    }
    restoring = false;
    notifyListeners();
    if (session != null && !offlineMode) {
      unawaited(refreshSources());
      unawaited(refreshServerFiles());
    }
  }

  Future<bool> login(String address, String username, String password) async {
    if (loggingIn) return false;
    loggingIn = true;
    authError = null;
    notifyListeners();
    try {
      final uri = parseServer(address);
      final result = await api.login(uri, username.trim(), password);
      try {
        await store.save(result);
        await store.saveServer(uri);
      } catch (_) {
        throw const ApiFailure('无法安全保存登录信息，请检查设备存储后重试');
      }
      server = uri.toString();
      offlineMode = false;
      await localMedia.activate(result);
      session = result;
      unawaited(refreshSources());
      unawaited(refreshServerFiles());
      return true;
    } on ApiFailure catch (e) {
      authError = e.message;
      return false;
    } catch (_) {
      authError = '登录失败，请稍后重试';
      return false;
    } finally {
      loggingIn = false;
      notifyListeners();
    }
  }

  void expire() {
    _endSession(expired: true);
  }

  Future<void> logout() => _endSession();

  Future<void> _endSession({bool expired = false}) async {
    final old = session;
    session = null;
    offlineMode = false;
    loggingIn = true;
    authError = expired ? '登录已失效，请重新登录' : null;
    _clearSearch();
    ++_capabilityVersion;
    checkingSources = false;
    availability = null;
    sourceError = null;
    aggregate = true;
    library.reset();
    serverFiles.reset();
    discovery.reset();
    notifyListeners();
    try {
      await player.reset();
      await playbackResume.clear();
      await localMedia.deactivate();
      await store.clear();
    } catch (_) {
      authError = '本地登录信息清理失败，请重新启动应用后检查';
    } finally {
      loggingIn = false;
      notifyListeners();
    }
    if (!expired && old != null) {
      try {
        await api.logout(old);
      } catch (_) {
        /* Local sign-out still succeeds. */
      }
    }
  }

  void _clearSearch() {
    ++_searchVersion;
    songs = [];
    keyword = '';
    page = 0;
    hasMore = false;
    searching = false;
    searchError = null;
    _buckets.clear();
    _pages.clear();
    _more.clear();
    sourceFailures.clear();
  }

  Future<void> refreshSources() async {
    final active = session;
    if (active == null) return;
    final version = ++_capabilityVersion;
    checkingSources = true;
    sourceError = null;
    notifyListeners();
    try {
      final data = await api.read(
        active,
        '/api/custom-source/list',
        query: {'username': active.username},
      );
      if (version != _capabilityVersion) return;
      availability = SourceAvailability.parse(data);
      player.cache.configure(data);
      if (availableSources.isEmpty) {
        discovery.reset();
      } else if (!availableSources.contains(discovery.source)) {
        final wasLoaded =
            discovery.sorts.isNotEmpty ||
            discovery.playlists.isNotEmpty ||
            discovery.loading;
        discovery.reset();
        discovery.source = availableSources.first;
        if (wasLoaded) unawaited(discovery.load(active, categories: true));
      }
      if (availableSources.isNotEmpty && !availableSources.contains(source)) {
        source = availableSources.first;
      }
    } on ApiFailure catch (e) {
      if (version != _capabilityVersion) return;
      // An unavailable capability endpoint is not proof that a platform is disabled.
      player.cache.configure(const {});
      availability = null;
      sourceError = '平台状态暂不可用，暂保留全部平台';
      if (e.unauthorized) expire();
    } catch (_) {
      if (version == _capabilityVersion) {
        availability = null;
        sourceError = '平台状态未知，暂保留全部平台';
        player.cache.configure(const {});
      }
    } finally {
      if (version == _capabilityVersion) {
        checkingSources = false;
        notifyListeners();
        if (keyword.isNotEmpty) unawaited(search(keyword));
      }
    }
  }

  Future<void> changeSource(MusicSource value) async {
    if (source == value && !aggregate) return;
    aggregate = false;
    source = value;
    if (keyword.isNotEmpty) {
      await search(keyword);
    } else {
      notifyListeners();
    }
  }

  Future<void> selectAggregate() async {
    if (aggregate) return;
    aggregate = true;
    if (keyword.isNotEmpty) {
      await search(keyword);
    } else {
      notifyListeners();
    }
  }

  Future<void> search(String value, {bool more = false}) async {
    final active = session;
    if (active == null || value.trim().isEmpty || (more && searching)) return;
    final version = ++_searchVersion;
    keyword = value.trim();
    if (!more) {
      songs = [];
      page = 0;
      hasMore = false;
      _buckets.clear();
      _pages.clear();
      _more.clear();
      sourceFailures.clear();
    }
    final targets = aggregate
        ? availableSources
        : availableSources.where((s) => s == source).toList();
    if (targets.isEmpty) {
      ++_searchVersion;
      searching = false;
      songs = [];
      hasMore = false;
      searchError = '没有可用平台，请先在网页端配置音源，再刷新平台状态';
      notifyListeners();
      return;
    }
    if (!more) _more.addAll(targets);
    unawaited(refreshServerFiles());
    searching = true;
    searchError = null;
    notifyListeners();
    await Future.wait(
      targets.where(_more.contains).map((platform) async {
        try {
          final nextPage = (_pages[platform] ?? 0) + 1;
          final result = await api.search(active, keyword, platform, nextPage);
          if (version != _searchVersion) return;
          offlineMode = false;
          final bucket = _buckets.putIfAbsent(platform, () => []);
          final ids = bucket.map((s) => s.id).toSet();
          final fresh = result.songs.where((s) => ids.add(s.id)).toList();
          bucket.addAll(fresh);
          _pages[platform] = nextPage;
          if (!result.hasMore || fresh.isEmpty) _more.remove(platform);
          sourceFailures.remove(platform);
        } on ApiFailure catch (e) {
          if (version != _searchVersion) return;
          sourceFailures[platform] = e.message;
          if (e.unauthorized) expire();
        } catch (_) {
          if (version == _searchVersion) sourceFailures[platform] = '搜索失败';
        }
        if (version == _searchVersion) {
          songs = [];
          final length = _buckets.values.fold(
            0,
            (max, list) => list.length > max ? list.length : max,
          );
          for (var i = 0; i < length; i++) {
            for (final platform in targets) {
              final bucket = _buckets[platform] ?? [];
              if (i < bucket.length) songs.add(bucket[i]);
            }
          }
          hasMore = _more.isNotEmpty;
          searchError = sourceFailures.isEmpty
              ? null
              : '暂时无法搜索：${sourceFailures.keys.map((s) => s.label).join('、')}。可重试其他结果不受影响。';
          localMedia.updateArtwork(songs);
          notifyListeners();
        }
      }),
    );
    if (version == _searchVersion) {
      searching = false;
      page++;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    ++_capabilityVersion;
    ++_searchVersion;
    _rememberPlayback();
    player.removeListener(_rememberPlayback);
    playbackResume.dispose();
    player.dispose();
    localMedia.dispose();
    serverFiles.dispose();
    library.dispose();
    discovery.dispose();
    api.close();
    super.dispose();
  }
}
