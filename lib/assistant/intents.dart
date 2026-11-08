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

/// 控制云音本身的功能（大模型的 control_app 函数也使用同一套动作）。
enum AppAction {
  /// 切换平台模式：value 为平台名称（网易云 / QQ 音乐 / 酷狗 / 洛雪）。
  platform,

  /// 深浅色：light / dark / system。
  themeMode,

  /// 主题色：朱红 / 蓝 / 青绿 / 橙 / 石墨。
  accent,

  /// 播放页样式：封面 / 黑胶 / 光盘 / 沉浸 / 卡片流 / 3D 封面流 / 照片墙 / 极简。
  playerStyle,

  /// 开关：value 为 on / off。
  desktopLyrics,
  statusLyrics,
  translation,
  glass,

  /// 桌宠：团团 / 星月 / 阿曜 / off。
  pet,

  /// 助手音色：云汐 / 小柚 / 晚星 / 清川 / 暮言。
  voice,

  /// 下载正在播放的歌曲。
  download,

  /// 播放：daily（每日推荐）/ liked（我喜欢的音乐）/ recent（最近播放）。
  playCollection,

  /// 打开页面：settings / downloads / stats / voice / pet / player / lyrics / library / search（附带关键词）。
  open,
}

class AppIntent extends AssistantIntent {
  const AppIntent(this.action, [this.value, this.query]);
  final AppAction action;
  final String? value;

  /// 搜索关键词（open search 时）。
  final String? query;
}

AppIntent? _appIntent(String s) {
  String? onOff(String verbOn, String verbOff, String what) {
    if (RegExp('($verbOn)($what)').hasMatch(s)) return 'on';
    if (RegExp('($verbOff)($what)').hasMatch(s)) return 'off';
    return null;
  }

  const on = '打开|开启|显示|开|启用';
  const off = '关闭|关掉|关|隐藏|收起|不要';
  // 平台模式：“切换到网易云”“用 QQ 音乐”“酷狗模式”。
  final platform = RegExp(r'(?:切换到|切到|换到|换成|改用|使用|用)(网易云|网易|QQ音乐|qq音乐|QQ|qq|酷狗|洛雪)(?:音乐)?(?:模式|平台)?$|^(网易云|QQ音乐|qq音乐|酷狗|洛雪)(?:音乐)?模式$').firstMatch(s);
  if (platform != null) return AppIntent(AppAction.platform, platform.group(1) ?? platform.group(2));
  // 深浅色。
  if (RegExp(r'(深色|暗色|夜间|黑暗|暗黑)模式').hasMatch(s)) return AppIntent(AppAction.themeMode, RegExp('^($off)').hasMatch(s) ? 'light' : 'dark');
  if (RegExp(r'(浅色|亮色|白天|日间)模式').hasMatch(s)) return const AppIntent(AppAction.themeMode, 'light');
  if (RegExp(r'(外观|主题|深浅色|颜色模式)跟随系统').hasMatch(s)) return const AppIntent(AppAction.themeMode, 'system');
  // 主题色。
  final accent = RegExp(r'(?:主题色|主题颜色|界面颜色)(?:换成|改成|切换到|设为|设置为|用)?(朱红|红色|红|蓝色|蓝|青绿|绿色|绿|橙色|橙|石墨|灰色|灰)|(?:换成|改成|切换到)(朱红|红色|蓝色|青绿|绿色|橙色|石墨|灰色)(?:主题|的主题)').firstMatch(s);
  if (accent != null) return AppIntent(AppAction.accent, accent.group(1) ?? accent.group(2));
  // 播放页样式。
  final style = RegExp(r'(?:播放页|播放界面|播放样式)?(?:换成|切换到|改成|使用|用)(封面|黑胶|光盘|沉浸|卡片流|3D封面流|封面流|照片墙|极简)(?:样式|风格|模式|播放页)?$').firstMatch(s);
  if (style != null && (s.contains('样式') || s.contains('播放') || s.contains('风格') || style.group(1) != '封面')) return AppIntent(AppAction.playerStyle, style.group(1));
  // 歌词与外观开关。
  final desktopLyrics = onOff(on, off, '桌面歌词|悬浮歌词');
  if (desktopLyrics != null) return AppIntent(AppAction.desktopLyrics, desktopLyrics);
  final statusLyrics = onOff(on, off, '状态栏歌词');
  if (statusLyrics != null) return AppIntent(AppAction.statusLyrics, statusLyrics);
  final translation = onOff(on, off, '(歌词)?翻译');
  if (translation != null) return AppIntent(AppAction.translation, translation);
  final glass = onOff(on, off, '液态玻璃');
  if (glass != null) return AppIntent(AppAction.glass, glass);
  // 桌宠。
  if (RegExp('($off)(桌宠|团团|星月|阿曜)').hasMatch(s)) return const AppIntent(AppAction.pet, 'off');
  final pet = RegExp(r'(?:打开|显示|召唤|叫出|换成|切换到|我要)(桌宠|团团|星月|阿曜)').firstMatch(s);
  if (pet != null) return AppIntent(AppAction.pet, pet.group(1) == '桌宠' ? null : pet.group(1));
  // 音色。
  final voice = RegExp(r'(?:换成|切换到|改成|用|换)(云汐|小柚|晚星|清川|暮言)(?:的)?(?:声音|音色)?$').firstMatch(s);
  if (voice != null) return AppIntent(AppAction.voice, voice.group(1));
  // 下载。
  if (RegExp(r'^下载(这首|这首歌|当前歌曲|正在播放的歌|这首歌曲)?(歌)?$').hasMatch(s)) return const AppIntent(AppAction.download);
  // 播放每日推荐 / 我喜欢的音乐 / 最近播放。
  if (RegExp(r'^(?:播放|放|听|来点)(?:今天的|今日)?每日推荐').hasMatch(s)) return const AppIntent(AppAction.playCollection, 'daily');
  if (RegExp(r'^(?:播放|放|听)(?:我喜欢的|我收藏的|我的收藏|我的红心|红心|我喜欢)(?:音乐|歌曲|歌)?$').hasMatch(s)) return const AppIntent(AppAction.playCollection, 'liked');
  if (RegExp(r'^(?:播放|放|听)(?:最近播放|最近听)(?:的)?(?:歌|歌曲)?$').hasMatch(s)) return const AppIntent(AppAction.playCollection, 'recent');
  // 打开页面与搜索。
  final search = RegExp(r'^(?:搜索|搜一下|搜|查找)(.+)$').firstMatch(s);
  if (search != null) return AppIntent(AppAction.open, 'search', search.group(1));
  const pages = {
    '设置': 'settings',
    '下载管理': 'downloads',
    '下载': 'downloads',
    '听歌统计': 'stats',
    '听歌报告': 'stats',
    '音色中心': 'voice',
    '桌宠设置': 'pet',
    '播放页': 'player',
    '播放界面': 'player',
    '乐库': 'library',
    '我的音乐': 'library',
  };
  final page = RegExp(r'^(?:打开|进入|去|跳到|看看)(设置|下载管理|下载|听歌统计|听歌报告|音色中心|桌宠设置|播放页|播放界面|乐库|我的音乐)$').firstMatch(s);
  if (page != null) return AppIntent(AppAction.open, pages[page.group(1)]);
  return null;
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
  // 云音本身的功能（放在点歌之前：“播放每日推荐”不是搜歌）。
  final app = _appIntent(s);
  if (app != null) return app;
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

  // “播放页换个样式”这类说的是播放界面，不是点歌：交给大模型。
  if (RegExp(r'^播放(页|界面|样式|器|模式|设置)').hasMatch(s)) return null;
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
