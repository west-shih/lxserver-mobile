import '../../core/lx_api.dart';

enum SearchKind {
  song('歌曲', 'song'),
  artist('歌手', 'singer'),
  album('专辑', 'album');

  const SearchKind(this.label, this.apiType);
  final String label;
  final String apiType;
}

bool supportsEntities(MusicSource source) =>
    source == MusicSource.wy || source == MusicSource.tx;

bool isArtistDetailId(MusicSource source, String id) => switch (source) {
  MusicSource.wy => RegExp(r'^[1-9]\d*$').hasMatch(id),
  MusicSource.tx =>
    RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id) && !RegExp(r'^\d+$').hasMatch(id),
  _ => false,
};

class MusicEntity {
  const MusicEntity(this.raw, this.source, this.artist);
  final Map<String, dynamic> raw;
  final MusicSource source;
  final bool artist;
  String get id => '${raw['id'] ?? ''}';
  String get key => '${source.name}:$id';
  String get name => '${raw['name'] ?? (artist ? '未知歌手' : '未知专辑')}';
  String get image => firstImage([raw['avatar'], raw['picUrl'], raw['img']]);
  String get singer => '${raw['artistName'] ?? raw['singer'] ?? ''}';
  String get artistId => '${raw['artistId'] ?? ''}';
  bool get canOpenArtist =>
      artistId.isNotEmpty &&
      (source != MusicSource.tx || !RegExp(r'^\d+$').hasMatch(artistId));
  String get description =>
      '${raw['desc'] ?? ''}'.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  String get alias => raw['alias'] is List
      ? (raw['alias'] as List)
            .whereType<String>()
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty && v != name)
            .toSet()
            .join(' / ')
      : '';
  int? number(String field) => int.tryParse('${raw[field]}');
  String get date {
    final value = raw['publishTime'];
    if (value == null || '$value'.isEmpty) return '';
    if (value is num) {
      if (value <= 0) return '';
      return DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
        isUtc: true,
      ).toIso8601String().split('T').first;
    }
    return '$value';
  }

  MusicEntity merge(Map<String, dynamic> value) => MusicEntity(
    {
      ...raw,
      for (final entry in value.entries)
        if (entry.value != null && entry.value != '') entry.key: entry.value,
      'id': id,
      'source': source.name,
    },
    source,
    artist,
  );
  Map<String, dynamic> get favorite => {
    'id': raw['id'],
    'source': source.name,
    'name': name,
    'picUrl': image,
    if (artist && alias.isNotEmpty) 'alias': raw['alias'],
    if (!artist) ...{
      'artistName': singer,
      if (date.isNotEmpty) 'publishTime': raw['publishTime'],
      'interval': '00:00',
      'meta': {'albumId': raw['id'], 'picUrl': image, 'albumName': name},
    },
  };
}

List<MusicEntity> parseEntities(
  Object? value,
  MusicSource source,
  bool artist,
) {
  if (value is! List) throw const ApiFailure('歌手或专辑列表格式不兼容');
  return value
      .whereType<Map<String, dynamic>>()
      .where((v) => v['id'] != null && '${v['id']}'.isNotEmpty)
      .map((v) => MusicEntity(v, source, artist))
      .toList();
}
