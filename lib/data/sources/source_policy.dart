/// 播放源之间的协作策略。
///
/// 网易云、QQ 音乐、酷狗是彼此独立的平台模式：默认只使用当前平台自己的音源与歌词。
/// 用户在设置中打开“其他平台补位”后，当前平台无法播放的歌曲才会在网易云中匹配同一首歌播放。
abstract final class SourcePolicy {
  static bool crossSource = false;
}
