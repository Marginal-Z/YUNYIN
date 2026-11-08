/// 本地语音 / 文字指令：不需要大模型就能完成的常用操作。识别不了的交给大模型（已配置时）。
sealed class AssistantIntent {
  const AssistantIntent();
}

enum PlaybackAction { play, pause, next, previous }

class PlaybackIntent extends AssistantIntent {
  const PlaybackIntent(this.action);
  final PlaybackAction action;
}

/// 搜索并播放：[artist] 为 true 时播放这位歌手的热门歌曲。
class PlayQueryIntent extends AssistantIntent {
  const PlayQueryIntent(this.query, {this.artist = false});
  final String query;
  final bool artist;
}

/// 音量：[delta] 为相对调整（-1..1），[level] 为绝对音量（0..1）。
class VolumeIntent extends AssistantIntent {
  const VolumeIntent({this.delta, this.level});
  final double? delta;
  final double? level;
}

enum ModeChoice { sequence, shuffle, repeatOne }

class ModeIntent extends AssistantIntent {
  const ModeIntent(this.mode);
  final ModeChoice mode;
}

class LikeIntent extends AssistantIntent {
  const LikeIntent({this.like = true});
  final bool like;
}

/// 定时关闭：[minutes] 为 0 表示取消。
class SleepIntent extends AssistantIntent {
  const SleepIntent(this.minutes);
  final int minutes;
}

/// 正在播放的是什么歌。
class NowPlayingIntent extends AssistantIntent {
  const NowPlayingIntent();
}

class OpenLyricsIntent extends AssistantIntent {
  const OpenLyricsIntent();
}

/// 均衡器预设（预设名称，例如“摇滚”；为空表示关闭均衡器）。
class EqIntent extends AssistantIntent {
  const EqIntent(this.preset);
  final String? preset;
}

/// 低频增强 / 空间音效开关。
class EffectIntent extends AssistantIntent {
  const EffectIntent({required this.bass, required this.on});
  final bool bass;
  final bool on;
}

/// 解析一句话。返回 null 表示不是本地能处理的指令。
AssistantIntent? parseIntent(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'[，。！？、,.!?\s]'), '');
  // 去掉礼貌用语与唤醒词。
  s = s.replaceAll(RegExp(r'^(你好云音|嗨云音|云音云音|云音|请|帮我|麻烦|给我)+'), '').replaceAll(RegExp(r'(吧|呗|一下|好吗|谢谢)+$'), '');
  if (s.isEmpty) return null;

  if (RegExp(r'^(暂停|停止|停止播放|别放了|不听了|停一下|先停)').hasMatch(s)) return const PlaybackIntent(PlaybackAction.pause);
  if (RegExp(r'^(继续|继续播放|开始播放|播放音乐|放歌|放音乐|接着放|恢复播放)$').hasMatch(s)) return const PlaybackIntent(PlaybackAction.play);
  if (RegExp(r'^(下一首|下一曲|切歌|换一首|换首歌|跳过|不想听这首)').hasMatch(s)) return const PlaybackIntent(PlaybackAction.next);
  if (RegExp(r'^(上一首|上一曲|前一首)').hasMatch(s)) return const PlaybackIntent(PlaybackAction.previous);

  if (RegExp(r'单曲循环').hasMatch(s)) return const ModeIntent(ModeChoice.repeatOne);
  if (RegExp(r'随机播放|打乱').hasMatch(s)) return const ModeIntent(ModeChoice.shuffle);
  if (RegExp(r'顺序播放|列表循环').hasMatch(s)) return const ModeIntent(ModeChoice.sequence);

  if (RegExp(r'^(取消收藏|取消喜欢|不喜欢这首)').hasMatch(s)) return const LikeIntent(like: false);
  if (RegExp(r'^(收藏|喜欢|红心|加入我喜欢)(这首|这首歌|当前歌曲)?(歌)?$').hasMatch(s) || s == '我喜欢这首歌') return const LikeIntent();

  if (RegExp(r'^(这是什么歌|这首歌叫什么|现在放的是什么|正在播放什么|这是谁唱的|这首歌是谁唱的)').hasMatch(s)) return const NowPlayingIntent();
  if (RegExp(r'^(打开|显示|看)歌词').hasMatch(s)) return const OpenLyricsIntent();

  // 定时关闭。
  if (RegExp(r'取消定时|关闭定时').hasMatch(s)) return const SleepIntent(0);
  final sleep = RegExp(r'^(?:(.+?)(分钟|小时)(?:后|以后|之后)(?:停止播放|关闭|停止|暂停|关掉)|定时(?:关闭|停止)?(.+?)(分钟|小时))').firstMatch(s);
  if (sleep != null) {
    final n = parseChineseNumber(sleep.group(1) ?? sleep.group(3) ?? '');
    final hour = (sleep.group(2) ?? sleep.group(4)) == '小时';
    if (n != null && n > 0) return SleepIntent((hour ? n * 60 : n).round());
  }
  if (RegExp(r'^半(个)?小时后(停止播放|关闭|停止|暂停)').hasMatch(s)) return const SleepIntent(30);

  // 音量。
  final vol = RegExp(r'音量(?:调到|设为|设置为|调成|到)?(百分之)?(.+?)(%)?$').firstMatch(s);
  if (vol != null && RegExp(r'[0-9零一二两三四五六七八九十百]').hasMatch(vol.group(2)!)) {
    final n = parseChineseNumber(vol.group(2)!);
    if (n != null) return VolumeIntent(level: (n > 1 || vol.group(1) != null || vol.group(3) != null ? n / 100 : n).clamp(0, 1).toDouble());
  }
  if (RegExp(r'(大声|音量大|调大|声音大|音量高|调高)').hasMatch(s)) return const VolumeIntent(delta: 0.15);
  if (RegExp(r'(小声|音量小|调小|声音小|音量低|调低|太吵)').hasMatch(s)) return const VolumeIntent(delta: -0.15);
  if (RegExp(r'^(静音)$').hasMatch(s)) return const VolumeIntent(level: 0);

  // 音效。
  if (RegExp(r'(关闭|关掉)均衡器').hasMatch(s)) return const EqIntent(null);
  final eq = RegExp(r'(?:切换到|切到|使用|用|打开|换成)?(流行|摇滚|古典|爵士|电子|人声|低音增强|高音增强|现场|温暖|DJ|平直)(?:音效|模式|均衡器)').firstMatch(s);
  if (eq != null) return EqIntent(eq.group(1));
  if (RegExp(r'(打开|开启)(低频增强|重低音|低音)').hasMatch(s)) return const EffectIntent(bass: true, on: true);
  if (RegExp(r'(关闭|关掉)(低频增强|重低音|低音)').hasMatch(s)) return const EffectIntent(bass: true, on: false);
  if (RegExp(r'(打开|开启)(空间音效|环绕)').hasMatch(s)) return const EffectIntent(bass: false, on: true);
  if (RegExp(r'(关闭|关掉)(空间音效|环绕)').hasMatch(s)) return const EffectIntent(bass: false, on: false);

  // 播放某首歌 / 某位歌手。“播放适合跑步的歌”这类描述交给大模型。
  bool descriptive(String q) => RegExp(r'适合|一些|点|推荐|心情|感觉|好听|随便|类似|风格|时候|的时|轻松|安静|欢快|伤感|热门|新歌|经典').hasMatch(q);
  final artist = RegExp(r'^(?:播放|放|来点|听|我想听|想听)(.+?)的(?:歌|歌曲|音乐)$').firstMatch(s);
  if (artist != null && !descriptive(artist.group(1)!)) return PlayQueryIntent(artist.group(1)!, artist: true);
  final song = RegExp(r'^(?:播放|放一首|放首|来一首|来首|我想听|想听|听一下|听|放)(.+)$').firstMatch(s);
  if (song != null) {
    final q = song.group(1)!.replaceAll(RegExp(r'^(一首|首|歌曲|歌)'), '').replaceAll(RegExp(r'(这首歌|这首|的歌)$'), '');
    if (q.isNotEmpty && !descriptive(q)) return PlayQueryIntent(q);
  }
  return null;
}

/// 解析中文或阿拉伯数字（支持到百位，例如“二十五”“一百”“3”）。
double? parseChineseNumber(String s) {
  s = s.replaceAll(RegExp(r'[个\s]'), '');
  final arabic = double.tryParse(s);
  if (arabic != null) return arabic;
  if (s == '半') return 0.5;
  const digits = {'零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9};
  if (s.isEmpty) return null;
  var total = 0;
  var current = 0;
  for (final ch in s.split('')) {
    if (digits.containsKey(ch)) {
      current = digits[ch]!;
    } else if (ch == '十') {
      total += (current == 0 ? 1 : current) * 10;
      current = 0;
    } else if (ch == '百') {
      total += (current == 0 ? 1 : current) * 100;
      current = 0;
    } else if (ch == '半') {
      return total + current + 0.5;
    } else {
      return null;
    }
  }
  return (total + current).toDouble();
}
