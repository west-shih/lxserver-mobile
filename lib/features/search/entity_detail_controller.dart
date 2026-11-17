import 'package:flutter/foundation.dart';

import '../../core/lx_api.dart';
import '../library/library_controller.dart';
import 'music_entity.dart';

class EntityDetailController extends ChangeNotifier {
  EntityDetailController(
    this.api,
    this.session,
    this.entity,
    this.onUnauthorized,
  );
  Future<Object> _read(
    Session session,
    String path, {
    Map<String, String>? query,
  }) {
    final version = _version;
    final albumVersion = _albumVersion;
    return api.browseQuery(
      () =>
          !_disposed &&
          (path.endsWith('artistAlbums')
              ? albumVersion == _albumVersion
              : version == _version),
      () => api.read(session, path, query: query),
    );
  }

  final LxApi api;
  bool _checkingExpiry = false;
  Future<bool> revalidate() async {
    if (_checkingExpiry || loading || _disposed) return false;
    if (!restoredSnapshot && error != null) return false;
    _checkingExpiry = true;
    final version = _version, albumVersion = _albumVersion;
    final staged = EntityDetailController(api, session, entity, () {
      if (!_disposed && version == _version) onUnauthorized();
    })..restoreSnapshot(snapshot());
    try {
      final changed = await api.revalidateBrowse(
        () async {
          await staged.load();
          if (_page > 0) await staged.loadAlbums();
          if (staged.error != null ||
              staged.infoError != null ||
              staged.albumError != null) {
            throw StateError('Incomplete detail refresh');
          }
        },
        current: () =>
            !_disposed && version == _version && albumVersion == _albumVersion,
      );
      if (changed &&
          !_disposed &&
          version == _version &&
          albumVersion == _albumVersion &&
          staged.error == null &&
          staged.infoError == null &&
          staged.albumError == null) {
        restoreSnapshot(staged.snapshot());
        notifyListeners();
        return true;
      }
      return false;
    } finally {
      staged.dispose();
      _checkingExpiry = false;
    }
  }

  final Session session;
  final VoidCallback onUnauthorized;
  MusicEntity entity;
  List<Song> songs = [];
  List<MusicEntity> albums = [];
  bool loading = false, loadingAlbums = false, moreAlbums = false;
  String order = 'hot';
  String? error, infoError, albumError;
  int _version = 0, _albumVersion = 0, _page = 0;
  bool _disposed = false;
  bool restoredSnapshot = false;
  Map<String, dynamic> snapshot() => {
    'entity': entity.raw,
    'songs': songs.map((e) => e.raw).toList(),
    'albums': albums.map((e) => e.raw).toList(),
    'order': order,
    'albumPage': _page,
    'moreAlbums': moreAlbums,
  };
  void restoreSnapshot(Map value) {
    if (value['entity'] is Map<String, dynamic>) {
      entity = entity.merge(value['entity']);
    }
    songs = parseSongs(value['songs'] ?? [], fallback: entity.source);
    albums = (value['albums'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((e) => MusicEntity(e, entity.source, false))
        .toList();
    order = value['order'] == 'time' ? 'time' : 'hot';
    _page = int.tryParse('${value['albumPage']}') ?? 0;
    moreAlbums = value['moreAlbums'] == true;
    restoredSnapshot = true;
  }

  Map<String, String> get query => {
    'id': entity.id,
    'source': entity.source.name,
  };
  Future<void> load({String? sort}) async {
    if (sort != null) order = sort;
    final version = ++_version;
    final retained = api.refreshingBrowse ? List.of(songs) : null;
    songs = [];
    loading = true;
    error = null;
    infoError = null;
    notifyListeners();
    if (!supportsEntities(entity.source)) {
      loading = false;
      error = '该平台暂不支持歌手或专辑详情';
      notifyListeners();
      return;
    }
    Future<void> info() async {
      try {
        final data = await _read(
          session,
          '/api/music/artistDetail',
          query: query,
        );
        if (version != _version) return;
        if (data is! Map<String, dynamic>) throw const ApiFailure('歌手详情格式不兼容');
        entity = entity.merge(data);
      } on ApiFailure catch (e) {
        if (version != _version) return;
        infoError = e.message;
        if (e.unauthorized) onUnauthorized();
      } catch (_) {
        if (version == _version) infoError = '歌手信息加载失败';
      }
    }

    Future<void> tracks() async {
      try {
        final data = await _read(
          session,
          entity.artist ? '/api/music/artistSongs' : '/api/music/albumSongs',
          query: {...query, if (entity.artist) 'order': order},
        );
        if (version != _version) return;
        songs = parseSongs(
          data is Map ? data['list'] : data,
          fallback: entity.source,
        );
        final ids = <String>{};
        songs = songs.where((s) => ids.add(s.id)).toList();
        if (!entity.artist && data is Map<String, dynamic>) {
          entity = entity.merge(data);
        }
      } on ApiFailure catch (e) {
        if (version != _version) return;
        error = e.message;
        if (e.unauthorized) onUnauthorized();
      } catch (_) {
        if (version == _version) error = '歌曲加载失败，请重试';
      }
    }

    await Future.wait([if (entity.artist) info(), tracks()]);
    if (version == _version) {
      if (error != null && retained != null) songs = retained;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadAlbums({bool more = false}) async {
    if (loadingAlbums ||
        (more && !moreAlbums) ||
        !supportsEntities(entity.source)) {
      return;
    }
    final version = ++_albumVersion;
    if (!more) {
      _page = 0;
      albums = [];
    }
    loadingAlbums = true;
    albumError = null;
    notifyListeners();
    try {
      final data = await _read(
        session,
        '/api/music/artistAlbums',
        query: {...query, 'page': '${_page + 1}'},
      );
      if (version != _albumVersion) return;
      if (data is! Map<String, dynamic>) throw const ApiFailure('专辑列表格式不兼容');
      final result = parseEntities(data['list'], entity.source, false);
      final ids = albums.map((a) => a.key).toSet();
      final fresh = result.where((a) => ids.add(a.key)).toList();
      albums = [...albums, ...fresh];
      _page++;
      final total = int.tryParse('${data['total']}');
      moreAlbums =
          fresh.isNotEmpty &&
          (total != null ? albums.length < total : result.length >= 50);
    } on ApiFailure catch (e) {
      if (version != _albumVersion) return;
      albumError = e.message;
      if (e.unauthorized) onUnauthorized();
    } catch (_) {
      if (version == _albumVersion) albumError = '专辑列表加载失败';
    } finally {
      if (version == _albumVersion) {
        loadingAlbums = false;
        notifyListeners();
      }
    }
  }

  void invalidate() {
    ++_version;
    ++_albumVersion;
    songs = [];
    albums = [];
    loading = false;
    loadingAlbums = false;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    invalidate();
    _disposed = true;
    super.dispose();
  }
}
