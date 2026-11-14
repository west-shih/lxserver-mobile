import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../core/lx_api.dart';

class TransferCancelled implements Exception {}

class CacheBypass implements Exception {}

/// One HTTP transfer feeds both the decoder and a private temporary file.
/// Only a complete, validated file is promoted; ranges read the same transfer.
class AudioTransfer {
  AudioTransfer._(
    this.part,
    this.target,
    this._client,
    this._response,
    this.mime,
    this.total,
  );
  final File part;
  File target;
  final HttpClient _client;
  final HttpClientResponse _response;
  String mime;
  final List<int> _header = [];
  final int? total;
  final Completer<void> _done = Completer();
  Completer<void> _changed = Completer();
  Future<void>? _pumpFuture;
  int received = 0;
  bool cancelled = false;
  bool complete = false;
  bool _finishing = false;
  Object? _failure;
  void Function()? onProgress;
  Future<void> get done => _done.future;

  static String extension(String mime) =>
      switch (mime.split(';').first.trim().toLowerCase()) {
        'audio/flac' || 'audio/x-flac' => '.flac',
        'audio/wav' || 'audio/x-wav' || 'audio/wave' => '.wav',
        'audio/mp4' || 'audio/x-m4a' => '.m4a',
        'audio/ogg' || 'application/ogg' => '.ogg',
        'audio/aac' || 'audio/aacp' => '.aac',
        'audio/mpeg' || 'audio/mp3' => '.mp3',
        _ => '.audio',
      };

  static Future<AudioTransfer> open(
    Uri uri,
    String basePath, {
    int? cacheBudget,
  }) async {
    if (!['http', 'https'].contains(uri.scheme) || uri.userInfo.isNotEmpty) {
      throw const ApiFailure('音频地址不可用');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = 'Mozilla/5.0';
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      // No LXServer credentials are added to third-party requests.
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw ApiFailure('音频请求失败（HTTP ${response.statusCode}）');
      }
      final mime =
          response.headers.contentType?.mimeType ?? 'application/octet-stream';
      if (mime.contains('html') ||
          mime.contains('json') ||
          mime.startsWith('text/')) {
        throw const ApiFailure('返回内容不是音频文件');
      }
      final total =
          response.compressionState !=
                  HttpClientResponseCompressionState.decompressed &&
              response.contentLength >= 0
          ? response.contentLength
          : null;
      if (cacheBudget != null &&
          (total == null || total <= 0 || total > cacheBudget)) {
        throw CacheBypass();
      }
      final transfer = AudioTransfer._(
        File('$basePath.part'),
        File('$basePath${extension(mime)}'),
        client,
        response,
        mime,
        total,
      );
      await transfer.part.parent.create(recursive: true);
      // Register an error handler even if nobody needs to wait for completion.
      unawaited(transfer.done.catchError((Object _) {}));
      transfer._pumpFuture = transfer._pump();
      return transfer;
    } catch (e) {
      client.close(force: true);
      if (e is SocketException ||
          e is HandshakeException ||
          e is TimeoutException) {
        throw const ApiFailure('无法获取音频，请检查网络后重试', kind: FailureKind.network);
      }
      rethrow;
    }
  }

  void _signal() {
    final old = _changed;
    _changed = Completer();
    if (!old.isCompleted) old.complete();
  }

  Future<void> _pump() async {
    RandomAccessFile? writer;
    try {
      writer = await part.open(mode: FileMode.write);
      await for (final bytes in _response.timeout(
        const Duration(seconds: 30),
      )) {
        if (cancelled) throw TransferCancelled();
        await writer.writeFrom(bytes);
        if (_header.length < 16) {
          _header.addAll(bytes.take(16 - _header.length));
          mime = _detectMime(_header) ?? mime;
        }
        received += bytes.length;
        _signal();
        onProgress?.call();
      }
      if (cancelled) throw TransferCancelled();
      if (received == 0 || (total != null && total != received)) {
        throw const ApiFailure('音频文件不完整，请重试');
      }
      await writer.flush();
      await writer.close();
      writer = null;
      final header = await part.open();
      final bytes = await header.read(16);
      await header.close();
      if (!_looksLikeAudio(bytes)) throw const ApiFailure('下载内容未通过音频文件检查');
      _finishing = true;
      mime = _detectMime(bytes) ?? mime;
      target = File(
        '${part.path.substring(0, part.path.length - 5)}${extension(mime)}',
      );
      await part.rename(target.path);
      complete = true;
      _done.complete();
      _signal();
      onProgress?.call();
    } catch (e) {
      _failure = e is FileSystemException
          ? const ApiFailure('本机空间不足或音频写入失败', kind: FailureKind.storage)
          : e is TransferCancelled || e is ApiFailure
          ? e
          : const ApiFailure('音频传输中断，请重试', kind: FailureKind.network);
      if (writer != null) {
        try {
          await writer.close();
        } catch (_) {}
      }
      if (!_done.isCompleted) _done.completeError(_failure!);
      _signal();
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {
        /* Startup cleans abandoned app-owned parts. */
      }
    } finally {
      _client.close(force: true);
    }
  }

  static bool _looksLikeAudio(List<int> b) {
    return _detectMime(b) != null;
  }

  static String? _detectMime(List<int> b) {
    if (b.length < 4) return null;
    final s = String.fromCharCodes(b);
    if (s.startsWith('fLaC')) return 'audio/flac';
    if (s.startsWith('ID3')) return 'audio/mpeg';
    if (s.startsWith('OggS')) return 'audio/ogg';
    if (s.startsWith('RIFF') && s.contains('WAVE')) return 'audio/wav';
    if (s.contains('ftyp')) return 'audio/mp4';
    if (b[0] == 0xff && (b[1] & 0xe0) == 0xe0) {
      return (b[1] & 0xf6) == 0xf0 ? 'audio/aac' : 'audio/mpeg';
    }
    return null;
  }

  Future<String> contentType() async {
    while (received < 16 && !complete && _failure == null && !cancelled) {
      await _changed.future;
    }
    if (_failure != null) throw _failure!;
    if (cancelled) throw TransferCancelled();
    return mime;
  }

  Future<void> cancel({bool removeComplete = false}) async {
    cancelled = true;
    _client.close(force: true);
    _signal();
    await _pumpFuture;
    if (removeComplete && await target.exists()) await target.delete();
  }

  Stream<List<int>> read(int start, int end) async* {
    var position = start;
    while (position < end) {
      if (cancelled) throw TransferCancelled();
      if (_failure != null) throw _failure!;
      if (position >= received) {
        if (complete) break;
        await _changed.future;
        continue;
      }
      final count = math.min(64 * 1024, math.min(received, end) - position);
      RandomAccessFile? reader;
      List<int> bytes;
      try {
        reader = await (complete ? target : part).open();
        await reader.setPosition(position);
        bytes = await reader.read(count);
      } on FileSystemException {
        if (!_finishing) rethrow;
        await done;
        continue;
      } finally {
        await reader?.close();
      }
      if (bytes.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }
      position += bytes.length;
      yield bytes;
    }
  }
}

/// A loopback-only proxy with explicit range and cancellation handling.
/// This avoids the experimental player's proxy closing partial responses uncaught.
class CachedAudioProxy {
  HttpServer? _server;
  Future<HttpServer>? _binding;
  final Map<String, AudioTransfer> _sources = {};
  Future<Uri> add(AudioTransfer transfer) async {
    _server ??= await (_binding ??= HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    ));
    if (!_listening) {
      _listening = true;
      _server!.listen((r) {
        unawaited(_handle(r));
      });
    }
    final random = math.Random.secure();
    final key = base64Url
        .encode(List.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    _sources[key] = transfer;
    return Uri.parse('http://127.0.0.1:${_server!.port}/audio/$key');
  }

  bool _listening = false;
  void clear() => _sources.clear();
  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final transfer = segments.length == 2 && segments.first == 'audio'
          ? _sources[segments.last]
          : null;
      if (transfer == null) {
        response.statusCode = 404;
        await response.close();
        return;
      }
      if (!['GET', 'HEAD'].contains(request.method)) {
        response.statusCode = 405;
        await response.close();
        return;
      }
      final total = transfer.total!;
      var start = 0;
      var end = total;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
          response.statusCode = 416;
          await response.close();
          return;
        }
        if (match[1]!.isEmpty) {
          start = math.max(0, total - int.parse(match[2]!));
        } else {
          start = int.parse(match[1]!);
          if (match[2]!.isNotEmpty) {
            end = math.min(total, int.parse(match[2]!) + 1);
          }
        }
        if (start >= total || end <= start) {
          response.statusCode = 416;
          response.headers.set('Content-Range', 'bytes */$total');
          await response.close();
          return;
        }
        response.statusCode = 206;
        response.headers.set('Content-Range', 'bytes $start-${end - 1}/$total');
      }
      response.headers.set('Accept-Ranges', 'bytes');
      response.headers.set('Cache-Control', 'no-store');
      response.headers.contentType = ContentType.parse(
        await transfer.contentType(),
      );
      response.contentLength = end - start;
      if (request.method != 'HEAD') {
        await response.addStream(transfer.read(start, end));
      }
      await response.close();
    } catch (_) {
      // Closing a player request mid-track is routine; never leak its URI or an
      // unawaited Content-Length exception into Flutter's global error handler.
      try {
        final socket = await response.detachSocket(writeHeaders: false);
        socket.destroy();
      } catch (_) {
        try {
          await response.close();
        } catch (_) {}
      }
    }
  }

  Future<void> close() async {
    _sources.clear();
    await _server?.close(force: true);
  }
}
