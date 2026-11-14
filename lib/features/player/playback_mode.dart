import 'dart:math';

enum PlaybackMode {
  order('顺序播放'),
  list('列表循环'),
  single('单曲循环'),
  random('随机播放');

  const PlaybackMode(this.label);
  final String label;
}

int? nextQueueIndex(
  PlaybackMode mode,
  int index,
  int length, {
  bool completed = false,
  Random? random,
}) {
  if (length == 0 || index < 0) return null;
  if (mode == PlaybackMode.single && completed) return index;
  if (mode == PlaybackMode.random) {
    if (length == 1) return 0;
    final value = (random ?? Random()).nextInt(length - 1);
    return value >= index ? value + 1 : value;
  }
  if (index + 1 < length) return index + 1;
  return mode == PlaybackMode.order ? null : 0;
}
