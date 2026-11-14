class LyricLine {
  const LyricLine(this.time, this.text, this.translation);
  final Duration time;
  final String text;
  final String translation;
}

class Lyrics {
  const Lyrics(this.lines, this.plain);
  final List<LyricLine> lines;
  final String plain;
  factory Lyrics.parse(Map<String, dynamic> data) {
    final original = '${data['lyric'] ?? ''}';
    final translations = _timed('${data['tlyric'] ?? ''}');
    final lines =
        _timed(original).entries
            .map(
              (v) => LyricLine(
                Duration(milliseconds: v.key),
                v.value,
                translations[v.key] ?? '',
              ),
            )
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));
    final plain = original
        .split('\n')
        .where(
          (line) =>
              !RegExp(r'^\s*\[[a-z]+:', caseSensitive: false).hasMatch(line),
        )
        .join('\n')
        .trim();
    return Lyrics(lines, lines.isEmpty ? plain : '');
  }
  static Map<int, String> _timed(String input) {
    final result = <int, String>{};
    final pattern = RegExp(r'\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    for (final line in input.split('\n')) {
      final matches = pattern.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final text = line.substring(matches.last.end).trim();
      if (text.isEmpty) continue;
      for (final match in matches) {
        final time =
            int.parse(match[1]!) * 60000 +
            int.parse(match[2]!) * 1000 +
            int.parse((match[3] ?? '0').padRight(3, '0'));
        result.update(time, (old) => '$old\n$text', ifAbsent: () => text);
      }
    }
    return result;
  }

  int indexAt(Duration position) {
    var low = 0;
    var high = lines.length - 1;
    var found = -1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].time <= position) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return found;
  }
}
