import 'package:flutter/foundation.dart';

import '../models.dart';
import 'music_source.dart';

/// 播放源之间的协作策略。
///
/// 网易云、QQ 音乐、酷狗是彼此独立的平台模式：默认只使用当前平台自己的音源与歌词。
/// 用户在设置中打开“其他平台补位”后，当前平台无法播放的歌曲才会在网易云中匹配同一首歌播放。
abstract final class SourcePolicy {
  static bool crossSource = false;

  /// 洛雪音源：当前平台取不到完整播放地址时使用（未导入音源时为 null）。
  static Future<StreamInfo?> Function(Song song, AudioQuality quality)? custom;
}

/// 取播放地址：先用歌曲所属平台自己的接口；取不到或只有试听片段时，再用洛雪音源（[SourcePolicy.custom]）获取同一首歌的地址。
Future<StreamInfo> resolveStream(MusicSource source, Song song, AudioQuality quality) async {
  StreamInfo? own;
  Object? error;
  try {
    own = await source.stream(song, quality);
  } catch (e) {
    error = e;
  }
  if (own?.url != null && !own!.trial) return own;
  final custom = SourcePolicy.custom;
  if (custom != null) {
    try {
      final c = await custom(song, quality);
      if (c?.url != null) return c!;
    } catch (e) {
      debugPrint('lx ${song.name}: $e');
      error ??= e;
    }
  }
  if (own != null) return own;
  throw error ?? Exception('无法播放这首歌');
}
