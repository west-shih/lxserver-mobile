import '../../core/lx_api.dart';

class SourceAvailability {
  const SourceAvailability(this.platforms, this.readyCount);
  final List<MusicSource> platforms;
  final int readyCount;
  factory SourceAvailability.parse(Object json) {
    if (json is! List) throw const ApiFailure('音源状态格式不兼容');
    final platforms = <String>{};
    var count = 0;
    for (final value in json) {
      if (value is! Map || value['enabled'] is! bool) {
        throw const ApiFailure('音源状态不完整');
      }
      if (value['enabled'] != true) continue;
      if (value['status'] is! String) throw const ApiFailure('音源运行状态未知');
      if (value['status'] != 'success') continue;
      if (value['supportedSources'] is! List) {
        throw const ApiFailure('音源平台信息不完整');
      }
      final disabled = value['disabledSources'];
      if (disabled != null && disabled is! List) {
        throw const ApiFailure('音源平台状态不兼容');
      }
      count++;
      platforms.addAll(
        (value['supportedSources'] as List).whereType<String>().where(
          (s) => disabled is! List || !disabled.contains(s),
        ),
      );
    }
    return SourceAvailability(
      MusicSource.values.where((s) => platforms.contains(s.name)).toList(),
      count,
    );
  }
}
