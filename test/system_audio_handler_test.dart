import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/core/lx_api.dart';
import 'package:lxserver_mobile/features/player/player_controller.dart';
import 'package:lxserver_mobile/features/player/system_audio_handler.dart';

class FakePlayer extends PlayerController {
  FakePlayer() : super(LxApi(), () {});
  int toggles = 0;
  int nextCalls = 0;
  @override
  Future<void> toggle() async {
    toggles++;
    playing = !playing;
    notifyListeners();
  }

  @override
  Future<void> next() async {
    nextCalls++;
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePlayer player;
  late SystemAudioHandler handler;
  setUp(() {
    player = FakePlayer();
    handler = SystemAudioHandler(player);
    player.enqueueAll(
      Session(Uri.parse('https://fixture.test'), 'fixture', 'fixture'),
      [
        Song({
          'songmid': '1',
          'name': 'Fixture song',
          'singer': 'Fixture artist',
        }, MusicSource.wy),
        Song({'songmid': '2', 'name': 'Next song'}, MusicSource.wy),
      ],
    );
    player.index = 0;
    player.notifyListeners();
  });
  tearDown(() {
    handler.dispose();
    player.dispose();
  });

  test('idle restoration does not claim the system card; playback publishes metadata', () async {
    expect(handler.mediaItem.value, isNull);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
    await handler.play();
    expect(handler.mediaItem.value?.title, 'Fixture song');
    expect(handler.mediaItem.value?.artist, 'Fixture artist');
    expect(handler.playbackState.value.playing, isTrue);
    expect(
      handler.playbackState.value.controls,
      contains(MediaControl.skipToNext),
    );
    expect(
      handler.playbackState.value.controls,
      isNot(contains(MediaControl.skipToPrevious)),
    );
  });
  test(
    'system play/pause is idempotent and seek/next use controller',
    () async {
      await handler.play();
      await handler.play();
      expect(player.toggles, 1);
      await handler.pause();
      await handler.pause();
      expect(player.toggles, 2);
      expect(handler.mediaItem.value, isNotNull);
      await handler.seek(const Duration(seconds: 12));
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 12),
      );
      await handler.skipToNext();
      expect(player.nextCalls, 1);
    },
  );
  test('late duration updates the same media item', () async {
    await handler.play();
    expect(handler.mediaItem.value?.duration, isNull);
    player.duration = const Duration(minutes: 3);
    player.notifyListeners();
    expect(handler.mediaItem.value?.duration, const Duration(minutes: 3));
  });
  test('logout clears media metadata and active playback', () async {
    await handler.play();
    await player.reset();
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.playing, isFalse);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });
}
