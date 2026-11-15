/// Optional platform metadata. Dates retain the upstream `time` semantics.
class CollectionMetadata {
  const CollectionMetadata({
    this.author = '',
    this.description = '',
    this.playCount = '',
    this.date = '',
  });
  final String author;
  final String description;
  final String playCount;
  final String date;
  factory CollectionMetadata.fromJson(Map data) {
    String text(String key) =>
        data[key] is String || data[key] is num ? '${data[key]}'.trim() : '';
    return CollectionMetadata(
      author: text('author'),
      description: text('desc')
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim(),
      playCount: text('play_count'),
      date: text('time'),
    );
  }
  CollectionMetadata merge(CollectionMetadata other) => CollectionMetadata(
    author: other.author.isEmpty ? author : other.author,
    description: other.description.isEmpty ? description : other.description,
    playCount: other.playCount.isEmpty ? playCount : other.playCount,
    date: other.date.isEmpty ? date : other.date,
  );
}
