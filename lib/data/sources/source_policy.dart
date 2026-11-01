import 'package:flutter/foundation.dart';

import '../models.dart';
import 'music_source.dart';

/// 播放源之间的协作策略。
///
/// 网易云、QQ 音乐、酷狗是彼此独立的平台模式，只使用当前平台自己的音源与歌词；
/// 未登录、没有会员或只有试听时，由洛雪音源按同一平台的歌曲 id 兜底获取完整地址。
abstract final class SourcePolicy {
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
  Object? lxError;
  if (custom != null) {
    try {
      final c = await custom(song, quality);
      if (c?.url != null) return c!;
    } catch (e) {
      debugPrint('lx ${song.name}: $e');
      lxError = e;
    }
  }
  if (own != null) return own;
  String text(Object e) => e.toString().replaceFirst('Exception: ', '');
  // 平台与洛雪音源都失败时两边的原因都给出，便于判断是账号问题还是音源失效。
  if (error != null && lxError != null) throw Exception('${text(error)}；洛雪音源也没有取到：${text(lxError)}');
  throw error ?? lxError ?? Exception('无法播放这首歌');
}
