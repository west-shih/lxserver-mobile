import 'package:flutter/foundation.dart';

import '../../core/lx_api.dart';
import 'library_song.dart';

class LibraryEditResult {
  const LibraryEditResult(this.snapshot, this.songs, this.changed);
  final Map<String, dynamic> snapshot;
  final List<Song> songs;
  final bool changed;
}

/// Apply an edit to a freshly fetched snapshot, preserving all unrelated data.
LibraryEditResult editLibrarySnapshot(
  Object data,
  String listId, {
  Set<String> removeIds = const {},
  List<Song> addSongs = const [],
  List<String>? order,
  List<String>? expectedOrder,
}) {
  if (data is! Map<String, dynamic> ||
      data['loveList'] is! List ||
      data['defaultList'] is! List ||
      data['userList'] is! List) {
    throw const ApiFailure('歌单格式不兼容，未保存');
  }
  final snapshot = Map<String, dynamic>.from(data);
  final lists = (data['userList'] as List)
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  final systemKey = listId == 'love'
      ? 'loveList'
      : listId == 'default'
      ? 'defaultList'
      : null;
  final customIndex = lists.indexWhere((v) => '${v['id']}' == listId);
  if (systemKey == null && customIndex < 0) {
    throw const ApiFailure('歌单已不存在，请刷新');
  }
  final raw = systemKey != null
      ? snapshot[systemKey]
      : lists[customIndex]['list'];
  if (raw is! List || raw.any((v) => v is! Map<String, dynamic>)) {
    throw const ApiFailure('歌曲格式不兼容，未保存');
  }
  var rows = raw.map((v) => Map<String, dynamic>.from(v as Map)).toList();
  String identity(Map<String, dynamic> row) => Song(row, MusicSource.kw).id;
  final before = rows.map(identity).toList();
  if (order != null &&
      (expectedOrder == null || !listEquals(before, expectedOrder))) {
    throw const ApiFailure('歌单已发生变化，未覆盖排序；请重新加载后编辑');
  }
  rows.removeWhere((v) => removeIds.contains(identity(v)));
  final ids = rows.map(identity).toSet();
  for (final song in addSongs) {
    if (ids.add(song.id)) {
      rows.add(
        song.isOnline ? librarySong(song) : Map<String, dynamic>.from(song.raw),
      );
    }
  }
  if (order != null) {
    if (order.length != rows.length ||
        order.toSet().length != order.length ||
        !setEquals(order.toSet(), rows.map(identity).toSet())) {
      throw const ApiFailure('排序数据不完整，未保存');
    }
    final byId = {for (final row in rows) identity(row): row};
    rows = [for (final id in order) byId[id]!];
  }
  final songs = rows.map((v) => Song(v, MusicSource.kw)).toList();
  if (systemKey != null) {
    snapshot[systemKey] = rows;
  } else {
    lists[customIndex] = {...lists[customIndex], 'list': rows};
  }
  snapshot['userList'] = lists;
  return LibraryEditResult(
    snapshot,
    songs,
    !listEquals(before, songs.map((s) => s.id).toList()),
  );
}
