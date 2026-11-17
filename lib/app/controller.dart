import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/lx_api.dart';
import '../core/session_store.dart';
import '../core/page_window.dart';
import '../core/browse_snapshot.dart';
import '../core/browse_cache.dart';
import '../features/player/player_controller.dart';
import '../features/player/playback_cache.dart';
import '../features/player/playback_resume.dart';
import '../features/library/library_controller.dart';
import '../features/library/server_files_controller.dart';
import '../features/local_media/local_media_controller.dart';
import '../features/discovery/discovery_controller.dart';
import '../features/search/source_availability.dart';
import '../features/search/entity_search_controller.dart';
import '../features/search/music_entity.dart';

class AppController extends ChangeNotifier {
  AppController({
    LxApi? api,
    Future<Directory> Function()? mediaDirectory,
    BrowseSnapshotStore? browseStore,
  }) : api = api ?? LxApi() {
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
    browseSnapshot =
        browseStore ?? BrowseSnapshotStore(directory: mediaDirectory);
    player.addListener(_rememberPlayback);
    serverFiles.addListener(player.refreshQualityAvailability);
    localMedia.addListener(player.refreshQualityAvailability);
    library = LibraryController(this.api, expire);
    discovery = DiscoveryController(this.api, expire);
    entitySearch = EntitySearchController(this.api, expire);
    entitySearch.addListener(notifyListeners);
    addListener(_scheduleBrowseState);
    discovery.addListener(_scheduleBrowseState);
    library.addListener(_scheduleBrowseState);
  }
  String songDraft = '', playlistDraft = '';
  int homeTab = 0;
  late final BrowseSnapshotStore browseSnapshot;
  final Map<String, Map<String, dynamic>> pageStates = {};
  List<Map<String, dynamic>> savedRoutes = [];
  bool restoringRoutes = false;
  bool _restoredBrowsing = false;
  Map<String, dynamic> pageState(String key) => pageStates[key] ?? {};
  void rememberPage(String key, Map<String, dynamic> value) {
    pageStates.remove(key);
    pageStates[key] = value;
    while (pageStates.length > 100) {
      pageStates.remove(pageStates.keys.first);
    }
    _scheduleBrowseState();
  }

  void rememberRoutes(List<Map<String, dynamic>> routes) {
    if (restoringRoutes || session == null) return;
    savedRoutes = routes.take(20).toList();
    _scheduleBrowseState();
  }

  int get browseLimitMb =>
      (api.browseCache?.maxBytes ?? 128 * 1024 * 1024) ~/ (1024 * 1024);
  Future<void> setBrowseLimit(int value) async {
    if (!BrowseCache.limitsMb.contains(value)) return;
    await store.saveBrowseLimit(value);
    await api.browseCache?.setLimitMb(value);
    notifyListeners();
  }

  Map<String, dynamic> _songSearchSnapshot() => {
    'source': source.name,
    'aggregate': aggregate,
    'keyword': keyword,
    'songs': songs.map((e) => e.raw).toList(),
    'page': page,
    'more': hasMore,
    'revision': searchRevision,
    'window': _searchWindow.snapshot((s) => s.raw),
    'buckets': {
      for (final e in _buckets.entries)
        e.key.name: e.value.map((s) => s.raw).toList(),
    },
    'pages': {for (final e in _pages.entries) e.key.name: e.value},
    'remaining': _more.map((e) => e.name).toList(),
  };
  bool _checkingSearchExpiry = false;
  Future<void> revalidateSearch() async {
    final active = session;
    if (_checkingSearchExpiry ||
        searching ||
        offlineMode ||
        active == null ||
        keyword.isEmpty ||
        page == 0) {
      return;
    }
    _checkingSearchExpiry = true;
    final version = _searchVersion;
    final query = keyword, selected = source, combined = aggregate;
    bool current() =>
        session == active &&
        version == _searchVersion &&
        keyword == query &&
        source == selected &&
        aggregate == combined;
    final targets = combined ? List.of(availableSources) : [selected];
    final results = <MusicSource, SearchPage>{};
    try {
      final changed = await api.revalidateBrowse(() async {
        for (final platform in targets) {
          results[platform] = await api.search(active, query, platform, 1);
        }
      }, current: current);
      if (!changed || !current()) return;
      final buckets = {for (final e in results.entries) e.key: e.value.songs};
      final window = PageWindow<Song>((s) => s.id);
      if (!combined) {
        final result = results[selected]!;
        window.add(
          1,
          result.songs,
          total: result.total,
          size: result.pageSize,
          hasMore: result.hasMore,
        );
      }
      final length = buckets.values.fold<int>(
        0,
        (n, v) => v.length > n ? v.length : n,
      );
      final items = [
        for (var i = 0; i < length; i++)
          for (final platform in targets)
            if (i < buckets[platform]!.length) buckets[platform]![i],
      ];
      _restoreSongSearch({
        'source': selected.name,
        'aggregate': combined,
        'keyword': query,
        'songs': items.map((s) => s.raw).toList(),
        'page': 1,
        'more': results.values.any((r) => r.hasMore),
        'revision': searchRevision + 1,
        'window': window.snapshot((s) => s.raw),
        'buckets': {
          for (final e in buckets.entries)
            e.key.name: e.value.map((s) => s.raw).toList(),
        },
        'pages': {for (final platform in targets) platform.name: 1},
        'remaining': [
          for (final e in results.entries)
            if (e.value.hasMore) e.key.name,
        ],
      });
      searchError = null;
      sourceFailures.clear();
      localMedia.updateArtwork(songs);
      notifyListeners();
    } on ApiFailure catch (e) {
      if (e.unauthorized && current()) expire();
    } finally {
      _checkingSearchExpiry = false;
    }
  }

  void _restoreSongSearch(Map value) {
    MusicSource platform(Object? id) =>
        MusicSource.values.where((e) => e.name == id).firstOrNull ??
        MusicSource.wy;
    source = platform(value['source']);
    aggregate = value['aggregate'] == true;
    keyword = '${value['keyword'] ?? ''}';
    songs = parseSongs(value['songs'] ?? [], fallback: source);
    page = resultTotal(value['page']) ?? 0;
    hasMore = value['more'] == true;
    searchRevision = resultTotal(value['revision']) ?? 0;
    if (value['window'] is Map) {
      _searchWindow.restoreSnapshot(
        value['window'],
        (data) => Song(data, source),
      );
    }
    _buckets.clear();
    _pages.clear();
    _more.clear();
    if (value['buckets'] is Map) {
      for (final e in (value['buckets'] as Map).entries) {
        _buckets[platform(e.key)] = parseSongs(
          e.value,
          fallback: platform(e.key),
        );
      }
    }
    if (value['pages'] is Map) {
      for (final e in (value['pages'] as Map).entries) {
        _pages[platform(e.key)] = resultTotal(e.value) ?? 0;
      }
    }
    for (final e in value['remaining'] as List? ?? []) {
      _more.add(platform(e));
    }
  }

  Timer? _browseTimer;
  Future<void> _browseWrites = Future.value();
  bool _resumingBrowse = false;
  bool get resumingBrowse => _resumingBrowse;
  void _scheduleBrowseState() {
    if (restoring || _resumingBrowse || session == null) return;
    _browseTimer?.cancel();
    _browseTimer = Timer(const Duration(milliseconds: 250), flushBrowseState);
  }

  void updateBrowseDrafts(String song, String playlist) {
    songDraft = song;
    playlistDraft = playlist;
    _scheduleBrowseState();
  }

  Future<void> flushBrowseState() {
    _browseTimer?.cancel();
    final active = session;
    if (active == null || restoring || _resumingBrowse) return _browseWrites;
    final value = <String, dynamic>{
      'server': active.server.toString(),
      'username': active.username,
      'songDraft': songDraft,
      'playlistDraft': playlistDraft,
      'tab': homeTab,
      'keyword': keyword,
      'kind': entitySearch.kind.name,
      'entityKeyword': entitySearch.keyword,
      'entitySource': entitySearch.source.name,
      'playlistKeyword': discovery.keyword,
      'tag': discovery.tag,
      'tagName': discovery.tagName,
      'sort': discovery.sort,
    };
    final snapshot = {
      ...value,
      'pages': pageStates,
      'routes': savedRoutes,
      'search': _songSearchSnapshot(),
      'entitySearch': entitySearch.snapshot(),
      'discovery': discovery.snapshot(),
      'library': library.snapshot(),
      if (availability != null)
        'availability': {
          'platforms': availability!.platforms.map((e) => e.name).toList(),
          'ready': availability!.readyCount,
        },
    };
    final diskWrite = browseSnapshot.write(snapshot);
    return _browseWrites = _browseWrites
        .then((_) async {
          await store.saveBrowseState(value);
          await diskWrite;
        })
        .catchError((Object _) {});
  }

  Future<void> _restoreBrowseState() async {
    final active = session;
    if (active == null) return;
    final snapshot = await browseSnapshot.read();
    final stored = await store.readBrowseState();
    final value =
        snapshot['server'] == active.server.toString() &&
            snapshot['username'] == active.username
        ? snapshot
        : stored;
    if (session != active ||
        value['server'] != active.server.toString() ||
        value['username'] != active.username) {
      return;
    }
    String text(String key) => value[key] is String ? value[key] as String : '';
    songDraft = text('songDraft');
    playlistDraft = text('playlistDraft');
    homeTab = value['tab'] is int ? (value['tab'] as int).clamp(0, 2) : 0;
    keyword = text('keyword');
    entitySearch.kind =
        SearchKind.values.where((k) => k.name == value['kind']).firstOrNull ??
        SearchKind.song;
    entitySearch.keyword = text('entityKeyword');
    entitySearch.source =
        entitySources
            .where((s) => s.name == value['entitySource'])
            .firstOrNull ??
        entitySources.firstOrNull ??
        MusicSource.wy;
    discovery.keyword = text('playlistKeyword');
    discovery.tag = text('tag');
    discovery.tagName = text('tagName').isEmpty ? '全部分类' : text('tagName');
    discovery.sort = text('sort');
    if (snapshot['server'] == active.server.toString() &&
        snapshot['username'] == active.username) {
      try {
        if (snapshot['search'] is Map) _restoreSongSearch(snapshot['search']);
        if (snapshot['entitySearch'] is Map) {
          entitySearch.restoreSnapshot(snapshot['entitySearch']);
        }
        if (snapshot['discovery'] is Map) {
          discovery.restoreSnapshot(snapshot['discovery']);
        }
        if (snapshot['library'] is Map) {
          library.restoreSnapshot(snapshot['library']);
        }
        if (snapshot['pages'] is Map) {
          pageStates.addAll(
            Map<String, Map<String, dynamic>>.from(snapshot['pages']),
          );
        }
        savedRoutes = (snapshot['routes'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .take(20)
            .toList();
        if (snapshot['availability'] is Map) {
          final state = snapshot['availability'] as Map;
          availability = SourceAvailability(
            MusicSource.values
                .where(
                  (e) => (state['platforms'] as List? ?? []).contains(e.name),
                )
                .toList(),
            resultTotal(state['ready']) ?? 0,
          );
        }
        _restoredBrowsing = true;
      } catch (_) {
        pageStates.clear();
        savedRoutes = [];
      }
    }
  }

  Future<void> _resumeBrowseResults() async {
    _resumingBrowse = true;
    final active = session;
    try {
      if (_restoredBrowsing) return;
      if (!offlineMode) await refreshSources(reloadResults: false);
      if (active == null || session != active) return;
      if (entitySearch.kind == SearchKind.song && keyword.isNotEmpty) {
        await search(keyword);
      } else if (entitySearch.kind != SearchKind.song &&
          entitySearch.keyword.isNotEmpty &&
          entitySources.isNotEmpty) {
        await entitySearch.search(active, entitySearch.keyword);
      }
      if (session == active &&
          (homeTab == 1 ||
              discovery.keyword.isNotEmpty ||
              discovery.tag.isNotEmpty)) {
        discovery.sources = List.of(availableSources);
        await discovery.load(active, categories: !discovery.aggregate);
      }
    } finally {
      _resumingBrowse = false;
      _scheduleBrowseState();
    }
  }

  Future<String> artistPortrait(MusicEntity entity) async => entity.image;

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
  late final EntitySearchController entitySearch;
  List<MusicSource> get entitySources =>
      availableSources.where(supportsEntities).toList();
  Future<void> selectSearchKind(SearchKind kind, String query) async {
    final active = session;
    if (active == null) return;
    final candidate = entitySearch.kind == SearchKind.song
        ? source
        : entitySearch.source;
    final platform = entitySources.contains(candidate)
        ? candidate
        : (entitySources.firstOrNull ?? MusicSource.wy);
    if (kind == SearchKind.song) {
      await entitySearch.select(active, kind, platform, query);
      if (query.trim().isNotEmpty) await search(query);
    } else if (entitySources.isNotEmpty) {
      await entitySearch.select(active, kind, platform, query);
    } else {
      entitySearch.clear();
      entitySearch.kind = kind;
      entitySearch.keyword = query.trim();
      notifyListeners();
    }
  }

  Session? session;
  String server = '';
  String? authError;
  bool restoring = true;
  bool loggingIn = false;
  bool searching = false;
  String? searchError;
  String keyword = '';
  MusicSource source = MusicSource.wy;
  bool aggregate = false;
  Future<void> _platformWrites = Future.value();
  Future<void> _savePlatforms() {
    final value = {
      'search': aggregate ? 'all' : source.name,
      'discovery': discovery.aggregate ? 'all' : discovery.source.name,
    };
    return _platformWrites = _platformWrites
        .then((_) => store.savePlatformSelection(value))
        .catchError((Object _) {});
  }

  Future<void> selectDiscoverySource(MusicSource value) async {
    final active = session;
    if (active == null || !availableSources.contains(value)) return;
    discovery.sources = List.of(availableSources);
    final loading = !discovery.aggregate && discovery.source == value
        ? discovery.selectAggregate(active)
        : discovery.changeSource(active, value);
    await Future.wait([loading, _savePlatforms()]);
  }

  SourceAvailability? availability;
  bool checkingSources = false;
  String? sourceError;
  List<MusicSource> get availableSources => musicSourceOrder
      .where((v) => availability == null || availability!.platforms.contains(v))
      .toList();
  final Map<MusicSource, List<Song>> _buckets = {};
  final Map<MusicSource, int> _pages = {};
  final Set<MusicSource> _more = {};
  final Map<MusicSource, String> sourceFailures = {};
  int _capabilityVersion = 0;
  List<Song> songs = [];
  int page = 0;
  bool hasMore = false;
  int _searchVersion = 0;
  int searchRevision = 0;
  final _searchWindow = PageWindow<Song>((song) => song.id);
  int? get searchTotal => aggregate ? null : _searchWindow.total;
  bool get hasSearchWindow =>
      !aggregate && _searchWindow.ready && searchTotal != null;
  List<Song> searchPageItems(int displayPage, int size) => hasSearchWindow
      ? _searchWindow.items(displayPage, size)
      : songs.skip(displayPage * size).take(size).toList();

  Future<void> ensureSearchPage(int displayPage, int size) async {
    final active = session;
    if (active == null || !hasSearchWindow) return;
    final version = ++_searchVersion;
    final platform = source;
    final query = keyword;
    searching = true;
    searchError = null;
    notifyListeners();
    try {
      for (final page in _searchWindow.missing(displayPage, size)) {
        final result = await api.search(active, query, platform, page);
        if (version != _searchVersion) return;
        if (result.songs.isEmpty) break;
        final known = _searchWindow.all.map((song) => song.id).toSet();
        if (result.songs.every((song) => known.contains(song.id))) {
          throw const ApiFailure('该页返回重复结果，请尝试前面的页码');
        }
        _searchWindow.add(
          page,
          result.songs,
          total: result.total,
          size: result.pageSize,
          hasMore: result.hasMore,
        );
        songs = _searchWindow.all;
        _buckets[platform] = List.of(songs);
        _pages[platform] = _searchWindow.contiguousPages;
        hasMore = _searchWindow.hasMore;
        if (hasMore) {
          _more.add(platform);
        } else {
          _more.remove(platform);
        }
        localMedia.updateArtwork(songs);
        notifyListeners();
      }
      if (version == _searchVersion &&
          _searchWindow.items(displayPage, size).isEmpty) {
        throw const ApiFailure('该页暂无结果，请尝试前面的页码');
      }
    } on ApiFailure catch (e) {
      if (version != _searchVersion) return;
      searchError = e.message;
      if (e.unauthorized) expire();
      rethrow;
    } finally {
      if (version == _searchVersion) {
        searching = false;
        notifyListeners();
      }
    }
  }

  Future<void> restore() async {
    Session? saved;
    try {
      final limit = int.tryParse(await store.readBrowseLimit() ?? '') ?? 128;
      await api.browseCache?.setLimitMb(limit);
      final selection = await store.readPlatformSelection();
      final savedSource = MusicSource.values
          .where((v) => v.name == selection['search'])
          .firstOrNull;
      aggregate = selection['search'] == 'all';
      source = savedSource ?? MusicSource.wy;
      final savedDiscovery = MusicSource.values
          .where((v) => v.name == selection['discovery'])
          .firstOrNull;
      discovery.aggregate = selection['discovery'] == 'all';
      discovery.source = savedDiscovery ?? MusicSource.wy;
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
      await _restoreBrowseState();
      await localMedia.activate(session!);
      final state = await playbackResume.read(session!);
      if (state != null) player.restorePlayback(session!, state);
    }
    restoring = false;
    notifyListeners();
    if (session != null) {
      unawaited(
        offlineMode
            ? api.cachedBrowseOnly(_resumeBrowseResults)
            : _resumeBrowseResults(),
      );
      if (!offlineMode) unawaited(refreshServerFiles());
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
    _browseTimer?.cancel();
    songDraft = playlistDraft = '';
    homeTab = 0;
    pageStates.clear();
    savedRoutes = [];
    _restoredBrowsing = false;
    final old = session;
    session = null;
    await browseSnapshot.clear();
    offlineMode = false;
    loggingIn = true;
    authError = expired ? '登录已失效，请重新登录' : null;
    _clearSearch();
    ++_capabilityVersion;
    checkingSources = false;
    availability = null;
    sourceError = null;
    library.reset();
    serverFiles.reset();
    discovery.reset();
    entitySearch.reset();
    notifyListeners();
    try {
      await player.reset();
      await playbackResume.clear();
      await localMedia.deactivate();
      await store.clear();
      await _browseWrites;
      await store.clearBrowseState();
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
    _searchWindow.clear();
    searchRevision++;
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

  Future<void> refreshSources({bool reloadResults = true}) async {
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
      final discoveryChanged = !listEquals(discovery.sources, availableSources);
      final discoveryLoaded =
          discovery.page > 0 ||
          discovery.playlists.isNotEmpty ||
          discovery.loading;
      discovery.sources = List.of(availableSources);
      if (availableSources.isEmpty) {
        discovery.reset();
      } else if (!discovery.aggregate &&
          !availableSources.contains(discovery.source)) {
        discovery.reset();
        discovery.aggregate = true;
        if (discoveryLoaded && reloadResults) unawaited(discovery.load(active));
      } else if (discovery.aggregate &&
          discoveryChanged &&
          discoveryLoaded &&
          reloadResults) {
        unawaited(discovery.load(active));
      }
      if (!availableSources.contains(source)) {
        aggregate = true;
        if (availableSources.isNotEmpty) source = availableSources.first;
      }
      unawaited(_savePlatforms());
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
        if (entitySearch.kind != SearchKind.song) {
          if (entitySources.isEmpty) {
            entitySearch.clear();
          } else if (!entitySources.contains(entitySearch.source)) {
            unawaited(
              entitySearch.select(
                active,
                entitySearch.kind,
                entitySources.first,
                entitySearch.keyword,
              ),
            );
          } else if (reloadResults && entitySearch.keyword.isNotEmpty) {
            unawaited(entitySearch.search(active, entitySearch.keyword));
          }
        }
        notifyListeners();
        if (reloadResults &&
            entitySearch.kind == SearchKind.song &&
            keyword.isNotEmpty) {
          unawaited(search(keyword));
        }
      }
    }
  }

  Future<void> changeSource(MusicSource value) async {
    if (source == value && !aggregate) return;
    aggregate = false;
    source = value;
    final saved = _savePlatforms();
    if (keyword.isNotEmpty) {
      await search(keyword);
    } else {
      notifyListeners();
    }
    await saved;
  }

  Future<void> selectAggregate() async {
    if (aggregate) return;
    aggregate = true;
    final saved = _savePlatforms();
    if (keyword.isNotEmpty) {
      await search(keyword);
    } else {
      notifyListeners();
    }
    await saved;
  }

  Future<void> search(String value, {bool more = false}) async {
    final active = session;
    if (active == null || value.trim().isEmpty || (more && searching)) return;
    final retained = !more && api.refreshingBrowse ? List.of(songs) : null;
    final oldWindow = _searchWindow.copy();
    final oldBuckets = Map.of(_buckets), oldPages = Map.of(_pages);
    final oldMore = Set.of(_more);
    final oldPage = page, oldHasMore = hasMore;
    final version = ++_searchVersion;
    keyword = value.trim();
    if (!more) {
      searchRevision++;
      _searchWindow.clear();
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
          final result = await api.browseQuery(
            () => version == _searchVersion && session == active,
            () => api.search(active, keyword, platform, nextPage),
          );
          if (version != _searchVersion) return;
          if (!aggregate) {
            _searchWindow.add(
              nextPage,
              result.songs,
              total: result.total,
              size: result.pageSize,
              hasMore: result.hasMore,
            );
          }
          if (!api.readingCachedBrowseOnly) offlineMode = false;
          final bucket = _buckets.putIfAbsent(platform, () => []);
          final ids = bucket.map((s) => s.id).toSet();
          final fresh = result.songs.where((s) => ids.add(s.id)).toList();
          bucket.addAll(fresh);
          if (!aggregate) _buckets[platform] = _searchWindow.all;
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
      if (retained != null && songs.isEmpty && sourceFailures.isNotEmpty) {
        songs = retained;
        _searchWindow.restore(oldWindow);
        _buckets
          ..clear()
          ..addAll(oldBuckets);
        _pages
          ..clear()
          ..addAll(oldPages);
        _more
          ..clear()
          ..addAll(oldMore);
        page = oldPage - 1;
        hasMore = oldHasMore;
      }
      searching = false;
      page++;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _browseTimer?.cancel();
    removeListener(_scheduleBrowseState);
    discovery.removeListener(_scheduleBrowseState);
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
    entitySearch.removeListener(notifyListeners);
    entitySearch.dispose();
    api.close();
    super.dispose();
  }
}
