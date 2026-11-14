import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'lx_api.dart';

class SessionStore {
  Future<String?> readMode() => _storage.read(key: 'lx.playbackMode');
  Future<void> saveMode(String value) =>
      _storage.write(key: 'lx.playbackMode', value: value);
  Future<String?> readPlaybackHistory() =>
      _storage.read(key: 'lx.playbackHistory');
  Future<void> savePlaybackHistory(String value) =>
      _storage.write(key: 'lx.playbackHistory', value: value);
  final _storage = const FlutterSecureStorage();
  Future<String?> readQuality() => _storage.read(key: 'lx.preferredQuality');
  Future<void> saveQuality(String quality) =>
      _storage.write(key: 'lx.preferredQuality', value: quality);
  Future<Session?> read() async {
    final value = await _storage.read(key: 'lx.session');
    if (value == null) return null;
    try {
      return Session.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> save(Session s) =>
      _storage.write(key: 'lx.session', value: jsonEncode(s.toJson()));
  Future<void> clear() => _storage.delete(key: 'lx.session');
  Future<String?> server() => _storage.read(key: 'lx.server');
  Future<void> saveServer(Uri server) =>
      _storage.write(key: 'lx.server', value: server.toString());
}
