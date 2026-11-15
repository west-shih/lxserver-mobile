import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'player_controller.dart';

Future<void> initializeSystemAudio(PlayerController player) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await AudioService.init(
    builder: () => SystemAudioHandler(player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.lxserver.mobile.playback',
      androidNotificationChannelName: '音乐播放',
      androidNotificationIcon: 'drawable/ic_stat_music',
      androidStopForegroundOnPause: false,
    ),
  );
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
}

/// Publishes the existing controller's state; never owns a second player/queue.
class SystemAudioHandler extends BaseAudioHandler {
  SystemAudioHandler(this.player) {
    player.addListener(_publish);
    _publish();
  }

  final PlayerController player;
  bool _stopped = false;
  bool _active = false;

  void _publish() {
    final song = player.current;
    // Restoring the UI alone must not claim an active system media session.
    if (song == null) {
      _active = false;
      _stopped = false;
    } else if (player.playing) {
      _active = true;
      _stopped = false;
    }
    final visible = song != null && _active && !_stopped;
    MediaItem? item;
    if (visible) {
      final path = player.localMedia?.artworkPath(song);
      final remote = Uri.tryParse(song.image);
      item = MediaItem(
        id: song.id,
        title: song.name,
        artist: song.singer,
        album: song.album,
        duration: player.duration > Duration.zero ? player.duration : null,
        artUri: path != null
            ? Uri.file(path)
            : remote != null && ['http', 'https'].contains(remote.scheme)
            ? remote
            : null,
        artHeaders: const {'User-Agent': 'LXServer-Mobile'},
      );
    }
    // MediaItem equality only compares IDs, not late duration/artwork updates.
    final previous = mediaItem.value;
    if (previous?.id != item?.id ||
        previous?.title != item?.title ||
        previous?.artist != item?.artist ||
        previous?.album != item?.album ||
        previous?.duration != item?.duration ||
        previous?.artUri != item?.artUri) {
      mediaItem.add(item);
    }
    final controls = <MediaControl>[
      if (player.canPrevious) MediaControl.skipToPrevious,
      if (player.playing) MediaControl.pause else MediaControl.play,
      if (player.canNext) MediaControl.skipToNext,
      MediaControl.stop,
    ];
    final processing = !visible
        ? AudioProcessingState.idle
        : player.resolving || player.changingQuality
        ? AudioProcessingState.loading
        : switch (player.processingState) {
            ProcessingState.idle => AudioProcessingState.ready,
            ProcessingState.loading => AudioProcessingState.loading,
            ProcessingState.buffering => AudioProcessingState.buffering,
            ProcessingState.ready => AudioProcessingState.ready,
            ProcessingState.completed => AudioProcessingState.completed,
          };
    playbackState.add(
      PlaybackState(
        controls: visible ? controls : const [],
        androidCompactActionIndices: visible
            ? List.generate(controls.length - 1, (i) => i)
            : const [],
        systemActions: visible ? const {MediaAction.seek} : const {},
        processingState: processing,
        playing: visible && player.playing,
        updatePosition: player.position,
        queueIndex: visible ? player.index : null,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (!player.playing) await player.toggle();
  }

  @override
  Future<void> pause() async {
    if (player.playing) await player.toggle();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.previous();

  @override
  Future<void> stop() async {
    _stopped = true;
    await player.reset();
    _publish();
    await super.stop();
  }

  void dispose() {
    player.removeListener(_publish);
  }

  @override
  Future<void> onTaskRemoved() => stop();
}
