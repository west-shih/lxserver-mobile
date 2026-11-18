import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'page_window.dart';
import 'browse_cache.dart';

enum MusicSource {
  kw('酷我'),
  kg('酷狗'),
  tx('QQ'),
  wy('网易'),
  mg('咪咕');

  const MusicSource(this.label);
  final String label;
}

const musicSourceOrder = [
  MusicSource.wy,
  MusicSource.tx,
  MusicSource.kg,
  MusicSource.kw,
  MusicSource.mg,
];

enum FailureKind {
  unknown,
  network,
  permission,
  sourceUnavailable,
  storage,
  server,
  rateLimited,
}

class ApiFailure implements Exception {
  const ApiFailure(
    this.message, {
    this.unauthorized = false,
    this.kind = FailureKind.unknown,
    this.connectionFailed = false,
  });
  final String message;
  final bool unauthorized;
  final FailureKind kind;
  final bool connectionFailed;
  @override
  String toString() => message;
}

Uri parseServer(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const ApiFailure('请输入完整服务器地址，例如 https://music.example.com');
  }
  return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''));
}

class Session {
  const Session(this.server, this.username, this.token);
  final Uri server;
  final String username;
  final String token;
  Map<String, dynamic> toJson() => {
    'server': server.toString(),
    'username': username,
    'token': token,
  };
  factory Session.fromJson(Map<String, dynamic> json) => Session(
    parseServer(json['server'] as String),
    json['username'] as String,
    json['token'] as String,
  );
}

String firstImage(Iterable<Object?> values) =>
    values
        .whereType<String>()
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .firstOrNull ??
    '';

String songImage(Map<String, dynamic> data) {
  final meta = data['meta'] is Map ? data['meta'] as Map : {};
  final album = data['album'] is Map ? data['album'] as Map : {};
  final other = data['otherSource'] is Map ? data['otherSource'] as Map : {};
  final otherMeta = other['meta'] is Map ? other['meta'] as Map : {};
  return firstImage([
    data['img'],
    data['pic'],
    data['picUrl'],
    meta['picUrl'],
    meta['pic'],
    meta['albumPic'],
    meta['cover'],
    album['picUrl'],
    album['pic'],
    album['img'],
    otherMeta['picUrl'],
  ]);
}

class Song {
  Song(
    Map<String, dynamic> data,
    MusicSource fallback, {
    this.freshQualityMetadata = false,
  }) : raw = Map.unmodifiable(_normalize(data, fallback));
  final bool freshQualityMetadata;
  static Map<String, dynamic> _normalize(
    Map<String, dynamic> data,
    MusicSource fallback,
  ) {
    final meta = data['meta'] is Map
        ? Map<String, dynamic>.from(data['meta'] as Map)
        : <String, dynamic>{};
    final value = <String, dynamic>{...data};
    value['source'] ??= meta['source'] ?? fallback.name;
    for (final key in [
      'albumName',
      'albumId',
      'hash',
      'strMediaMid',
      'albumMid',
      'copyrightId',
      'lrcUrl',
      'mrcUrl',
      'trcUrl',
    ]) {
      value[key] ??= meta[key];
    }
    value['img'] = songImage(data);
    value['songmid'] ??= meta['songId'];
    value['types'] ??= meta['qualitys'];
    value['_types'] ??= meta['_qualitys'];
    if (value['songmid'] == null && value['id'] != null) {
      final id = '${value['id']}';
      final prefix = '${value['source']}_';
      value['songmid'] = id.startsWith(prefix)
          ? id.substring(prefix.length)
          : value['id'];
    }
    return value;
  }

  final Map<String, dynamic> raw;
  String get id =>
      '${raw['source']}:${raw['songmid'] ?? raw['id'] ?? raw['hash'] ?? raw['copyrightId'] ?? '${raw['name']}:${raw['singer']}'}';
  String get name => '${raw['name'] ?? '未命名歌曲'}';
  String get singer => '${raw['singer'] ?? '未知歌手'}';
  String get album => '${raw['albumName'] ?? ''}';
  String get image => '${raw['img'] ?? ''}';
  String get interval => '${raw['interval'] ?? ''}';
  bool get isOnline => MusicSource.values.any((s) => s.name == raw['source']);
  String get sourceLabel => isOnline
      ? source.label
      : raw['source'] == 'local'
      ? '本地'
      : '其他';
  MusicSource get source => MusicSource.values.firstWhere(
    (s) => s.name == raw['source'],
    orElse: () => MusicSource.kw,
  );
}

class SearchPage {
  const SearchPage(this.songs, this.hasMore, {this.total, this.pageSize = 20});
  final List<Song> songs;
  final bool hasMore;
  final int? total;
  final int pageSize;
}

class PlaybackResource {
  const PlaybackResource(
    this.url,
    this.requestedQuality,
    this.reportedQuality, {
    this.sourceId,
    this.sourceName,
    this.hasMoreSources = false,
    this.serverCached = false,
    this.localFile = false,
    this.downloadedFile = false,
  });
  final Uri url;
  final String requestedQuality;
  // Provider-reported type, not independent verification of the encoded audio.
  final String? reportedQuality;
  final String? sourceId;
  final String? sourceName;
  final bool hasMoreSources;
  final bool serverCached;
  final bool localFile, downloadedFile;
}

class _BrowseRevalidation {
  bool updated = false;
  bool failed = false;
  final List<Future<void> Function()> writes = [];
}

class LxApi {
  LxApi({http.Client? client, BrowseCache? browseCache})
    : _client = client ?? http.Client(),
      browseCache = browseCache ?? (client == null ? BrowseCache.shared : null);
  final BrowseCache? browseCache;
  static final Object _refreshKey = Object();
  static final Object _currentKey = Object();
  static final Object _cacheOnlyKey = Object();
  static final Object _revalidationKey = Object();

  /// Run a detached page model on entry. Commit only a complete successful update.
  /// Ordinary reads (including pagination) deliberately ignore soft expiry.
  Future<bool> revalidateBrowse(
    Future<void> Function() action, {
    bool Function()? current,
  }) async {
    if (browseCache == null || readingCachedBrowseOnly) return false;
    final state = _BrowseRevalidation();
    final generation = browseCache!.generation;
    try {
      await runZoned(
        () => browseQuery(current ?? () => true, action),
        zoneValues: {_revalidationKey: state},
      );
      if (!state.updated ||
          state.failed ||
          generation != browseCache!.generation ||
          !(current?.call() ?? true)) {
        return false;
      }
      for (final write in state.writes) {
        await write();
      }
      return generation == browseCache!.generation && (current?.call() ?? true);
    } on ApiFailure catch (e) {
      if (e.unauthorized) rethrow;
      return false;
    } catch (_) {
      return false;
    }
  }

  final Map<String, Future<Object>> _pendingBrowse = {};
  final Map<String, List<bool Function()>> _interested = {};
  final Map<String, Future<void>> _platformQueues = {};
  final Map<String, int> _platformFailures = {};

  /// Explicit refresh bypasses metadata reads, never adds a retry.
  Future<T> refreshBrowse<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_refreshKey: true});
  bool get refreshingBrowse => Zone.current[_refreshKey] == true;
  bool get readingCachedBrowseOnly => Zone.current[_cacheOnlyKey] == true;
  Future<T> cachedBrowseOnly<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_cacheOnlyKey: true});
  Future<T> browseQuery<T>(
    bool Function() current,
    Future<T> Function() action,
  ) {
    final parent = Zone.current[_currentKey] as bool Function()?;
    return runZoned(
      action,
      zoneValues: {_currentKey: () => current() && (parent?.call() ?? true)},
    );
  }

  static const _browsePaths = {
    '/api/music/search',
    '/api/music/songList/tags',
    '/api/music/songList/list',
    '/api/music/songList/search',
    '/api/music/songList/detail',
    '/api/music/artistDetail',
    '/api/music/artistSongs',
    '/api/music/artistAlbums',
    '/api/music/albumSongs',
    '/api/music/comment',
    '/api/music/lyric',
  };
  final http.Client _client;
  final _playbackCacheMisses = <(Session, String, String), DateTime>{};
  Future<Object> _requestJson(
    Uri server,
    String path, {
    String method = 'GET',
    Session? session,
    Map<String, String>? query,
    Object? body,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final readOnly =
        method == 'GET' || (method == 'POST' && path == '/api/music/comment');
    if (!readOnly || session == null || !_browsePaths.contains(path)) {
      return _sendJson(
        server,
        path,
        method: method,
        session: session,
        query: query,
        body: body,
        timeout: timeout,
      );
    }
    final sorted = Map.fromEntries(
      (query?.entries.toList() ?? <MapEntry<String, String>>[])
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
    final key = jsonEncode([
      server.toString(),
      session.username,
      path,
      method,
      sorted,
      body,
    ]);
    final family = BrowseCache.digest(
      jsonEncode([
        server.toString(),
        session.username,
        path,
        Map.of(sorted)..remove('page'),
        if (body is Map) Map.of(body)..remove('page'),
      ]),
    );
    final force = refreshingBrowse;
    final persist = path != '/api/music/lyric';
    final revalidation = Zone.current[_revalidationKey] as _BrowseRevalidation?;
    final pendingKey = BrowseCache.digest(
      '$key:${session.token}:$force:$readingCachedBrowseOnly:${identityHashCode(revalidation)}',
    );
    final current = Zone.current[_currentKey] as bool Function()?;
    if (_pendingBrowse[pendingKey] case final pending?) {
      _interested[pendingKey]!.add(current ?? () => true);
      return pending;
    }
    final interested = <bool Function()>[current ?? () => true];
    _interested[pendingKey] = interested;
    final generation = browseCache?.generation;
    final work = () async {
      if (persist && !force) {
        final cached = await browseCache?.read(key);
        if (cached != null &&
            (revalidation == null ||
                await browseCache!.isFresh(key, BrowseCache.lifetime(path)))) {
          return cached;
        }
      }
      if (Zone.current[_cacheOnlyKey] == true) {
        throw const ApiFailure('离线时没有这部分浏览缓存', kind: FailureKind.network);
      }
      final song = body is Map ? body['songInfo'] : null;
      final platform =
          '${server.toString()}:${query?['source'] ?? (song is Map ? song['source'] : null) ?? 'other'}';
      final failureKey = '$platform:$path';
      final failureVersion = _platformFailures[failureKey] ?? 0;
      final previous = _platformQueues[platform] ?? Future<void>.value();
      final result = previous.then((_) {
        if (!interested.any((check) => check())) {
          throw const ApiFailure('查询已取消');
        }
        if ((_platformFailures[failureKey] ?? 0) != failureVersion) {
          throw const ApiFailure('该平台刚刚请求失败，已停止排队查询，请稍后手动刷新');
        }
        return _sendJson(
          server,
          path,
          method: method,
          session: session,
          query: query,
          body: body,
          timeout: timeout,
        );
      });
      final tail = result.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      _platformQueues[platform] = tail;
      try {
        final data = await result;
        Future<void> save() async {
          if (persist &&
              generation != null &&
              generation == browseCache!.generation) {
            final requestedPage =
                query?['page'] ??
                (body is Map ? body['page']?.toString() : null);
            if ((force || revalidation != null) &&
                (requestedPage == null || requestedPage == '1')) {
              await browseCache!.invalidateFamily(family);
            }
            await browseCache!.write(
              key,
              data,
              generation: generation,
              family: family,
            );
          }
        }

        if (revalidation == null) {
          await save();
        } else {
          revalidation.writes.add(save);
        }
        revalidation?.updated = true;
        return data;
      } on ApiFailure {
        revalidation?.failed = true;
        if ((_platformFailures[failureKey] ?? 0) == failureVersion &&
            interested.any((check) => check())) {
          _platformFailures[failureKey] = failureVersion + 1;
        }
        rethrow;
      } finally {
        if (identical(_platformQueues[platform], tail)) {
          _platformQueues.remove(platform);
        }
      }
    }();
    _pendingBrowse[pendingKey] = work;
    try {
      return await work;
    } finally {
      if (identical(_pendingBrowse[pendingKey], work)) {
        _pendingBrowse.remove(pendingKey);
        _interested.remove(pendingKey);
      }
    }
  }

  Future<Object> _sendJson(
    Uri server,
    String path, {
    String method = 'GET',
    Session? session,
    Map<String, String>? query,
    Object? body,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final uri = server.replace(
      path: '${server.path}$path',
      queryParameters: query,
    );
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (session != null) {
      request.headers.addAll({
        'x-user-token': session.token,
        'x-user-name': session.username,
      });
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(timeout);
      if (response.statusCode == 401) {
        throw ApiFailure(
          session == null ? '账号或密码不正确' : '登录已失效，请重新登录',
          unauthorized: session != null,
        );
      }
      if (response.statusCode == 403) {
        throw const ApiFailure(
          '账号已禁用或没有访问权限，请联系管理员',
          kind: FailureKind.permission,
        );
      }
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const ApiFailure('服务器发生重定向，请填写最终服务器地址');
      }
      Object? data;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic> || decoded is List) data = decoded;
      } on FormatException {
        /* Do not expose raw HTML or server diagnostics. */
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = data is Map<String, dynamic> ? data['errorCode'] : null;
        if (code == 'NO_AVAILABLE_SOURCE' ||
            code == 'PLATFORM_SOURCE_UNAVAILABLE') {
          throw const ApiFailure(
            '服务器未配置此平台的可用音源，请在网页端配置',
            kind: FailureKind.sourceUnavailable,
          );
        }
        throw ApiFailure(
          '请求失败（HTTP ${response.statusCode}），请检查服务器或稍后重试',
          kind: response.statusCode == 429
              ? FailureKind.rateLimited
              : response.statusCode >= 500
              ? FailureKind.server
              : FailureKind.unknown,
        );
      }
      if (data == null) throw const ApiFailure('服务器返回格式不兼容，请检查地址和 LXServer 版本');
      return data;
    } on TimeoutException {
      throw const ApiFailure('请求超时，请检查网络或稍后重试', kind: FailureKind.network);
    } on http.ClientException {
      throw const ApiFailure(
        '无法连接服务器，请检查地址、网络和证书',
        kind: FailureKind.network,
        connectionFailed: true,
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    Uri server,
    String path, {
    String method = 'GET',
    Session? session,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final data = await _requestJson(
      server,
      path,
      method: method,
      session: session,
      query: query,
      body: body,
    );
    if (data is! Map<String, dynamic>) throw const ApiFailure('服务器响应格式不兼容');
    return data;
  }

  Future<Object> writeList(Session s, Map<String, dynamic> data) =>
      _requestJson(
        s.server,
        '/api/user/list',
        session: s,
        method: 'POST',
        body: data,
      );

  Future<Object> writeUserSettings(Session s, Map<String, dynamic> data) =>
      _requestJson(
        s.server,
        '/api/user/settings',
        session: s,
        method: 'POST',
        body: data,
      );

  Future<Object> writeEntities(
    Session session,
    bool artist,
    List<Map<String, dynamic>> entities,
  ) => _requestJson(
    session.server,
    artist ? '/api/user/library/artists' : '/api/user/library/albums',
    session: session,
    method: 'POST',
    body: entities,
  );

  Future<Object> read(
    Session s,
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 40),
  }) =>
      _requestJson(s.server, path, session: s, query: query, timeout: timeout);

  Future<Map<String, dynamic>> lyrics(Session s, Song song) {
    final mid = '${song.raw['songmid'] ?? ''}';
    // GET query values are strings. QQ needs a numeric songID upstream;
    // resolving a real MID lets the server obtain it with the correct type.
    final resolveQqId =
        song.raw['source'] == 'tx' &&
        mid.isNotEmpty &&
        int.tryParse(mid) == null;
    return _request(
      s.server,
      '/api/music/lyric',
      session: s,
      query: {
        'source': '${song.raw['source']}',
        'songmid': '${song.raw['songmid'] ?? song.raw['songId'] ?? ''}',
        'name': song.name,
        'singer': song.singer,
        for (final key in [
          'songId',
          'hash',
          'interval',
          'copyrightId',
          'albumId',
          'lrcUrl',
          'mrcUrl',
          'trcUrl',
        ])
          if (song.raw[key] != null && !(resolveQqId && key == 'songId'))
            key: '${song.raw[key]}',
      },
    );
  }

  Future<Map<String, dynamic>> comments(
    Session s,
    Song song, {
    String type = 'hot',
    int page = 1,
    int limit = 20,
  }) {
    final info = Map<String, dynamic>.from(song.raw);
    if (song.source == MusicSource.tx) {
      // QQ comment SDK expects a numeric songId; a MID belongs in songmid.
      final meta = info['meta'] is Map ? info['meta'] as Map : const {};
      final numericId = [
        meta['songId'],
        info['songId'],
        info['songmid'],
      ].map((v) => '$v').where((v) => RegExp(r'^\d+$').hasMatch(v)).firstOrNull;
      if (numericId != null) {
        info['songId'] = numericId;
      } else {
        info.remove('songId');
      }
    }
    return _request(
      s.server,
      '/api/music/comment',
      session: s,
      method: 'POST',
      body: {'songInfo': info, 'type': type, 'page': page, 'limit': limit},
    );
  }

  Future<Session> login(Uri server, String username, String password) async {
    final data = await _request(
      server,
      '/api/user/login',
      method: 'POST',
      body: {'username': username, 'password': password},
    );
    if (data['success'] != true ||
        data['token'] is! String ||
        (data['token'] as String).isEmpty) {
      throw const ApiFailure('登录失败，请检查账号和服务端版本');
    }
    final returnedName = data['username'];
    return Session(
      server,
      returnedName is String && returnedName.trim().isNotEmpty
          ? returnedName
          : username,
      data['token'] as String,
    );
  }

  Future<bool> verify(Session s) async {
    final data = await _requestJson(
      s.server,
      '/api/user/auth/verify',
      session: s,
      timeout: const Duration(seconds: 6),
    );
    return data is Map && data['valid'] == true;
  }

  Future<void> logout(Session s) async {
    await _request(s.server, '/api/user/logout', method: 'POST', session: s);
  }

  Future<SearchPage> search(
    Session s,
    String keyword,
    MusicSource source,
    int page,
  ) async {
    final data = await _request(
      s.server,
      '/api/music/search',
      session: s,
      query: {
        'name': keyword,
        'source': source.name,
        'type': 'song',
        'page': '$page',
        'limit': '20',
      },
    );
    if (data['list'] is! List) throw const ApiFailure('搜索响应格式不兼容');
    final songs = (data['list'] as List)
        .whereType<Map<String, dynamic>>()
        .map((json) => Song(json, source, freshQualityMetadata: true))
        .toList();
    return SearchPage(
      songs,
      data['hasMore'] == true ||
          (data['hasMore'] == null && songs.length == 20),
      total: resultTotal(data['total']),
      pageSize: (resultTotal(data['pageSize']) ?? 20).clamp(1, 100000),
    );
  }

  Future<PlaybackResource> resolvePlayback(
    Session s,
    Song song, {
    required String quality,
    List<String> excludeApiSources = const [],
  }) async {
    if (!song.isOnline) throw const ApiFailure('这类服务器本地歌曲暂不支持，请在网页端播放');
    final data = await _requestJson(
      s.server,
      '/api/music/url',
      session: s,
      method: 'POST',
      timeout: const Duration(seconds: 10),
      body: {
        'songInfo': song.raw,
        'quality': quality,
        'enableAutoSwitchApiSource': true,
        'excludeApiSources': excludeApiSources,
      },
    ) as Map<String, dynamic>;
    final value = data['url'];
    if (value is! String || value.isEmpty) {
      throw const ApiFailure('服务器没有返回播放地址');
    }
    final uri = s.server.replace(path: '${s.server.path}/').resolve(value);
    if (!['http', 'https'].contains(uri.scheme)) {
      throw const ApiFailure('播放地址格式不兼容');
    }
    return PlaybackResource(
      uri,
      quality,
      data['type'] is String ? data['type'] as String : null,
      sourceId: data['sourceId'] is String ? data['sourceId'] as String : null,
      sourceName: data['sourceName'] is String
          ? data['sourceName'] as String
          : null,
      hasMoreSources: data['hasMoreSources'] == true,
    );
  }

  Future<PlaybackResource?> cachedPlayback(
    Session s,
    Song song,
    String quality,
  ) async {
    if (!song.isOnline || song.name.isEmpty || song.singer.isEmpty) return null;
    final key = (s, song.id, quality);
    final missedAt = _playbackCacheMisses[key];
    if (missedAt != null &&
        DateTime.now().difference(missedAt) < const Duration(seconds: 30)) {
      return null;
    }
    _playbackCacheMisses.remove(key);
    try {
      final value = await _requestJson(
        s.server,
        '/api/music/cache/check',
        session: s,
        timeout: const Duration(seconds: 2),
        query: {
          'name': song.name,
          'singer': song.singer,
          'source': song.source.name,
          'songmid': '${song.raw['songmid'] ?? ''}',
          'songId': '${song.raw['id'] ?? song.raw['songmid'] ?? ''}',
          'quality': quality,
          'exactQuality': '1',
        },
      );
      if (value is Map &&
          value['exists'] == false &&
          value['isCollision'] != true) {
        _playbackCacheMisses[key] = DateTime.now();
        if (_playbackCacheMisses.length > 100) {
          _playbackCacheMisses.remove(_playbackCacheMisses.keys.first);
        }
        return null;
      }
      if (value is! Map ||
          value['exists'] != true ||
          value['isCollision'] == true ||
          value['quality'] != quality ||
          value['url'] is! String) {
        return null;
      }
      var path = value['url'] as String;
      if (path.startsWith('/api/music/cache/file/') &&
          s.server.path.isNotEmpty) {
        path = '${s.server.path}$path';
      }
      final uri = s.server.replace(path: '${s.server.path}/').resolve(path);
      final prefix = '${s.server.path}/api/music/cache/file/';
      // Cache URLs may contain the user token: never send them to another origin.
      if (!['http', 'https'].contains(uri.scheme) ||
          uri.origin != s.server.origin ||
          !uri.path.startsWith(prefix) ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment) {
        return null;
      }
      return PlaybackResource(uri, quality, quality, serverCached: true);
    } on ApiFailure catch (e) {
      if (e.unauthorized || e.kind == FailureKind.permission) rethrow;
      return null; // Old servers, cache misses and unavailable cache storage don't prevent streaming.
    } on FormatException {
      return null;
    }
  }

  void close() => _client.close();
}
