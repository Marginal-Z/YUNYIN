import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../data/models.dart';
import 'player_controller.dart';

/// 是否接入系统媒体会话（Android 通知栏 / 锁屏、iOS / macOS 控制中心）。
bool get supportsSystemMedia =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

/// 把 [PlayerController] 的状态同步到系统媒体会话，并把系统按键转发回播放器。
class SystemMediaHandler extends BaseAudioHandler with SeekHandler {
  SystemMediaHandler(this.player) {
    player.addListener(_sync);
    _sync();
  }

  final PlayerController player;
  String? _itemKey;
  Duration? _itemDuration;

  static Future<void> attach(PlayerController player) async {
    if (!supportsSystemMedia) return;
    try {
      await AudioService.init(
        builder: () => SystemMediaHandler(player),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.marginalz.yunyin.playback',
          androidNotificationChannelName: '云音播放',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
        ),
      );
    } catch (e) {
      debugPrint('system media unavailable: $e');
    }
  }

  void _sync() {
    final Song? s = player.current;
    if (s != null && (s.key != _itemKey || player.duration != _itemDuration)) {
      _itemKey = s.key;
      _itemDuration = player.duration;
      final cover = s.coverUrl;
      mediaItem.add(
        MediaItem(
          id: s.key,
          title: s.name,
          artist: s.artistText,
          album: s.albumName,
          duration: player.duration,
          artUri: cover != null && cover.startsWith('http') ? Uri.parse('$cover?param=500y500') : null,
        ),
      );
    }
    playbackState.add(
      playbackState.value.copyWith(
        controls: [MediaControl.skipToPrevious, player.playing ? MediaControl.pause : MediaControl.play, MediaControl.skipToNext],
        systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: s == null ? AudioProcessingState.idle : (player.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready),
        playing: player.playing,
        updatePosition: player.position.value,
        speed: 1,
      ),
    );
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.previous();

  @override
  Future<void> seek(Duration position) async {
    await player.seek(position);
    _sync();
  }

  @override
  Future<void> stop() async {
    await player.pause();
    await super.stop();
  }
}
