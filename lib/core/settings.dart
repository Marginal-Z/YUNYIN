import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import 'theme/palette.dart';

/// 液态玻璃材质（与 Liquid Glass 演示中的两种材质一致）。
enum GlassMaterial {
  /// 清透：几乎不模糊，没有色调。
  clear('清透'),

  /// 柔和：轻度模糊并叠加白色色调。
  regular('柔和');

  const GlassMaterial(this.label);
  final String label;
}

/// 播放页样式。
enum PlayerStyle {
  /// 大封面。
  cover('封面'),

  /// 黑胶唱片：唱片旋转、唱臂随播放落下。
  vinyl('黑胶'),

  /// 光盘：封面印在光盘上，表面有流转的彩虹光泽。
  disc('光盘'),

  /// 沉浸：封面铺满上半屏并与模糊的封面背景融为一体。
  immersive('沉浸'),

  /// 卡片流：播放队列的封面横向排开，当前歌曲大卡片居中，两侧卡片立体倾斜，左右滑动切歌。
  cardFlow('卡片流'),

  /// 3D 封面流：两侧封面大角度翻转叠放，带倒影，左右滑动切歌。
  coverFlow('3D 封面流'),

  /// 照片墙：播放队列铺成封面墙，自动聚焦当前歌曲，点按播放。
  wall('照片墙'),

  /// 极简：小圆形封面，只保留歌名、进度与播放控件。
  minimal('极简');

  const PlayerStyle(this.label);
  final String label;

  /// 横向铺满整个宽度的样式（以播放队列为内容）。
  bool get wide => this == cardFlow || this == coverFlow || this == wall;
}

/// 界面背景。
enum BackgroundMode {
  /// 默认：纯色（浅色模式纯白）。枚举名保留 glow 以兼容已保存的设置。
  glow('默认'),

  /// 根据正在播放歌曲的封面取色。
  cover('封面取色'),

  /// 自定义图片。
  image('自定义图片');

  const BackgroundMode(this.label);
  final String label;
}

/// 屏幕方向（手机与平板）。
enum ScreenOrientation {
  portrait('竖屏'),
  auto('自动旋转'),
  landscape('横屏');

  const ScreenOrientation(this.label);
  final String label;
}

/// 首页样式。
enum HomeLayout {
  /// 推荐、歌单、最近播放分区。
  standard('标准', '推荐、歌单与最近播放分区'),

  /// 封面铺满的无限照片墙，可以向任意方向拖动。
  photoWall('照片墙', '封面铺满屏幕，向任意方向无限拖动');

  const HomeLayout(this.label, this.description);
  final String label;
  final String description;
}

/// 均衡器的 10 个频段（Hz）。
const kEqBands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

/// 均衡器预设（每个频段的增益，dB）。
enum EqPreset {
  flat('平直', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  pop('流行', [-1, 1, 3, 4, 2, 0, -1, -1, 1, 2]),
  rock('摇滚', [4, 3, 1, -1, -2, -1, 1, 3, 4, 4]),
  classical('古典', [3, 2, 1, 0, 0, 0, -1, -1, 2, 3]),
  jazz('爵士', [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
  electronic('电子', [5, 4, 1, 0, -2, 1, 0, 1, 4, 5]),
  vocal('人声', [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]),
  bass('低音增强', [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
  treble('高音增强', [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
  custom('自定义', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

  const EqPreset(this.label, this.gains);
  final String label;
  final List<int> gains;
}

/// 用户设置，持久化在 SharedPreferences。
class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;

  ThemeMode themeMode = ThemeMode.light;
  AccentColor accent = AccentColor.red;
  AudioQuality quality = AudioQuality.hires;
  AudioQuality downloadQuality = AudioQuality.higher;
  bool crossfade = true;
  bool normalize = true;

  /// Android：使用 OpenSL ES 输出音频（个别设备上 AudioTrack 输出没有声音时的兼容选项）。
  bool openSles = false;

  /// 已播放过完整的启动动画；之后冷启动只播缩短版。
  bool splashSeen = false;
  bool wifiOnlyDownload = true;
  bool autoClean = true;
  bool glass = true;
  bool pushNotify = true;
  bool personalized = true;
  bool showTranslation = false;

  /// 应用图标跟随主题色。
  bool iconFollowsAccent = true;

  /// 播放页背景按封面取色。
  bool coverColors = true;

  /// 液态玻璃材质。
  GlassMaterial glassMaterial = GlassMaterial.clear;

  /// 界面背景。
  BackgroundMode background = BackgroundMode.glow;

  /// 播放页样式。
  PlayerStyle playerStyle = PlayerStyle.cover;

  /// 首页样式。
  HomeLayout homeLayout = HomeLayout.standard;

  /// 屏幕方向。
  ScreenOrientation orientation = ScreenOrientation.auto;

  /// 播放进度条的波浪动画。
  bool waveProgress = true;

  /// 音量增强（dB）：0–6。
  int volumeBoost = 0;

  /// 均衡器。
  bool eqEnabled = false;
  EqPreset eqPreset = EqPreset.flat;
  List<double> eqGains = List.filled(kEqBands.length, 0);

  /// 音量均衡强度（0–1）：1 为完全按平台响度增益调整，0 等同关闭。
  double normalizeStrength = 1;

  /// Android：以 32 位浮点 PCM 输出，保留完整动态范围（个别平板的音频驱动不支持，默认关闭）。
  bool hiResOutput = false;

  /// Windows / macOS：独占音频设备，绕过系统混音，按音源原始采样率输出。
  bool exclusiveAudio = false;

  /// 当前平台无法播放的歌曲换用网易云的同一首歌（默认关闭：各平台彼此独立）。
  bool crossSource = false;

  /// 切换平台时一并切换界面样式（主题色与播放样式），每个平台记住自己的样式。
  bool platformStyle = true;

  String _platform = 'netease';
  final Map<String, (int, int)> _platformStyles = {};

  /// 各平台第一次使用时的默认样式：网易云朱红 + 封面，QQ 音乐绿色 + 卡片流，酷狗蓝色 + 3D 封面流。
  static const _platformDefaults = {
    'netease': (AccentColor.red, PlayerStyle.cover),
    'qq': (AccentColor.teal, PlayerStyle.cardFlow),
    'kugou': (AccentColor.blue, PlayerStyle.coverFlow),
  };

  /// 桌面歌词（Android 为悬浮窗，桌面端为置顶的歌词条窗口）。
  bool desktopLyrics = false;

  /// 状态栏歌词（Android）。
  bool statusBarLyrics = false;

  /// 桌面歌词锁定：不接收触摸，点按穿透到下方应用。
  bool lyricsLocked = false;

  /// 桌面歌词颜色（ARGB）；0 表示跟随主题色。
  int lyricsColor = 0;

  /// 桌面歌词不透明度（0.3–1）。
  double lyricsOpacity = 1;

  /// 状态栏歌词水平位置（相对屏幕宽度的偏移，-0.4–0.4）。
  double statusLyricsOffset = 0;

  /// 自定义背景图片（应用数据目录中的副本）。
  String? backgroundImage;

  /// 自定义背景图片是否模糊。
  bool backgroundBlur = false;

  /// 启动时检查更新。
  bool autoUpdate = true;

  /// 用户选择跳过的版本号，不再自动提示。
  String? skippedUpdate;

  /// 歌词字号倍数（0.85 / 1.0 / 1.15）。
  double lyricScale = 1.0;
  String? downloadDir;
  double volume = 0.65;
  List<String> searchHistory = [];

  final Map<(bool, AccentColor), Palette> _palettes = {};

  Palette palette(bool dark) => _palettes.putIfAbsent((dark, accent), () => dark ? Palette.dark(accent) : Palette.light(accent));

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[_p.getInt('themeMode') ?? ThemeMode.light.index];
    accent = AccentColor.values[_p.getInt('accent') ?? 0];
    quality = AudioQuality.values[_p.getInt('quality') ?? AudioQuality.hires.index];
    downloadQuality = AudioQuality.values[_p.getInt('downloadQuality') ?? AudioQuality.higher.index];
    crossfade = _p.getBool('crossfade') ?? true;
    normalize = _p.getBool('normalize') ?? true;
    openSles = _p.getBool('openSles') ?? false;
    splashSeen = _p.getBool('splashSeen') ?? false;
    wifiOnlyDownload = _p.getBool('wifiOnlyDownload') ?? true;
    autoClean = _p.getBool('autoClean') ?? true;
    glass = _p.getBool('glass') ?? true;
    pushNotify = _p.getBool('pushNotify') ?? true;
    personalized = _p.getBool('personalized') ?? true;
    showTranslation = _p.getBool('showTranslation') ?? false;
    iconFollowsAccent = _p.getBool('iconFollowsAccent') ?? true;
    coverColors = _p.getBool('coverColors') ?? true;
    autoUpdate = _p.getBool('autoUpdate') ?? true;
    glassMaterial = GlassMaterial.values[(_p.getInt('glassMaterial') ?? 0).clamp(0, GlassMaterial.values.length - 1)];
    playerStyle = PlayerStyle.values[(_p.getInt('playerStyle') ?? 0).clamp(0, PlayerStyle.values.length - 1)];
    homeLayout = HomeLayout.values[(_p.getInt('homeLayout') ?? 0).clamp(0, HomeLayout.values.length - 1)];
    orientation = ScreenOrientation.values[(_p.getInt('orientation') ?? ScreenOrientation.auto.index).clamp(0, ScreenOrientation.values.length - 1)];
    waveProgress = _p.getBool('waveProgress') ?? true;
    volumeBoost = _p.getInt('volumeBoost') ?? 0;
    eqEnabled = _p.getBool('eqEnabled') ?? false;
    eqPreset = EqPreset.values[(_p.getInt('eqPreset') ?? 0).clamp(0, EqPreset.values.length - 1)];
    final gains = _p.getStringList('eqGains');
    if (gains != null && gains.length == kEqBands.length) eqGains = [for (final g in gains) double.tryParse(g) ?? 0];
    normalizeStrength = _p.getDouble('normalizeStrength') ?? 1;
    hiResOutput = _p.getBool('hiResOutput') ?? false;
    exclusiveAudio = _p.getBool('exclusiveAudio') ?? false;
    crossSource = _p.getBool('crossSource') ?? false;
    platformStyle = _p.getBool('platformStyle') ?? true;
    try {
      final raw = _p.getString('platformStyles');
      if (raw != null) {
        (jsonDecode(raw) as Map).forEach((k, v) => _platformStyles['$k'] = ((v as List)[0] as int, v[1] as int));
      }
    } catch (_) {}
    desktopLyrics = _p.getBool('desktopLyrics') ?? false;
    statusBarLyrics = _p.getBool('statusBarLyrics') ?? false;
    lyricsLocked = _p.getBool('lyricsLocked') ?? false;
    lyricsColor = _p.getInt('lyricsColor') ?? 0;
    lyricsOpacity = _p.getDouble('lyricsOpacity') ?? 1;
    statusLyricsOffset = _p.getDouble('statusLyricsOffset') ?? 0;
    background = BackgroundMode.values[(_p.getInt('background') ?? 0).clamp(0, BackgroundMode.values.length - 1)];
    backgroundImage = _p.getString('backgroundImage');
    backgroundBlur = _p.getBool('backgroundBlur') ?? false;
    if (background == BackgroundMode.image && backgroundImage == null) background = BackgroundMode.glow;
    skippedUpdate = _p.getString('skippedUpdate');
    lyricScale = _p.getDouble('lyricScale') ?? 1.0;
    downloadDir = _p.getString('downloadDir');
    volume = _p.getDouble('volume') ?? 0.65;
    searchHistory = _p.getStringList('searchHistory') ?? [];
  }

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _p.setInt('themeMode', m.index);
    notifyListeners();
  }

  void setAccent(AccentColor a) {
    accent = a;
    _p.setInt('accent', a.index);
    _rememberPlatformStyle();
    notifyListeners();
  }

  void _rememberPlatformStyle() {
    _platformStyles[_platform] = (accent.index, playerStyle.index);
    _p.setString('platformStyles', jsonEncode({for (final e in _platformStyles.entries) e.key: [e.value.$1, e.value.$2]}));
  }

  /// 切换平台：记下离开的平台的样式，换成新平台记住的样式（第一次使用该平台时用平台默认样式）。
  void applyPlatform(String id) {
    if (id == _platform) return;
    if (!platformStyle) {
      _platform = id;
      return;
    }
    _rememberPlatformStyle();
    _platform = id;
    final saved = _platformStyles[id];
    final def = _platformDefaults[id];
    if (saved == null && def == null) return;
    accent = saved != null ? AccentColor.values[saved.$1.clamp(0, AccentColor.values.length - 1)] : def!.$1;
    playerStyle = saved != null ? PlayerStyle.values[saved.$2.clamp(0, PlayerStyle.values.length - 1)] : def!.$2;
    _p.setInt('accent', accent.index);
    _p.setInt('playerStyle', playerStyle.index);
    notifyListeners();
  }

  /// 启动时对齐当前平台（不触发样式切换）。
  void initPlatform(String id) => _platform = id;

  void setQuality(AudioQuality q) {
    quality = q;
    _p.setInt('quality', q.index);
    notifyListeners();
  }

  void setDownloadQuality(AudioQuality q) {
    downloadQuality = q;
    _p.setInt('downloadQuality', q.index);
    notifyListeners();
  }

  void setFlag(String key, bool v) {
    switch (key) {
      case 'crossfade':
        crossfade = v;
      case 'normalize':
        normalize = v;
      case 'openSles':
        openSles = v;
      case 'splashSeen':
        splashSeen = v;
      case 'wifiOnlyDownload':
        wifiOnlyDownload = v;
      case 'autoClean':
        autoClean = v;
      case 'glass':
        glass = v;
      case 'pushNotify':
        pushNotify = v;
      case 'personalized':
        personalized = v;
      case 'showTranslation':
        showTranslation = v;
      case 'iconFollowsAccent':
        iconFollowsAccent = v;
      case 'coverColors':
        coverColors = v;
      case 'autoUpdate':
        autoUpdate = v;
      case 'backgroundBlur':
        backgroundBlur = v;
      case 'waveProgress':
        waveProgress = v;
      case 'eqEnabled':
        eqEnabled = v;
      case 'hiResOutput':
        hiResOutput = v;
      case 'exclusiveAudio':
        exclusiveAudio = v;
      case 'crossSource':
        crossSource = v;
      case 'platformStyle':
        platformStyle = v;
      case 'desktopLyrics':
        desktopLyrics = v;
      case 'statusBarLyrics':
        statusBarLyrics = v;
      case 'lyricsLocked':
        lyricsLocked = v;
    }
    _p.setBool(key, v);
    notifyListeners();
  }

  void setPlayerStyle(PlayerStyle v) {
    playerStyle = v;
    _p.setInt('playerStyle', v.index);
    _rememberPlatformStyle();
    notifyListeners();
  }

  void setEqPreset(EqPreset p) {
    eqPreset = p;
    if (p != EqPreset.custom) eqGains = [for (final g in p.gains) g.toDouble()];
    _p.setInt('eqPreset', p.index);
    _p.setStringList('eqGains', [for (final g in eqGains) '$g']);
    notifyListeners();
  }

  /// 调整单个频段：自动切换为“自定义”预设。
  void setEqGain(int band, double db) {
    eqGains = List.of(eqGains)..[band] = db.clamp(-12, 12).toDouble();
    eqPreset = EqPreset.custom;
    _p.setInt('eqPreset', eqPreset.index);
    _p.setStringList('eqGains', [for (final g in eqGains) '$g']);
    notifyListeners();
  }

  void setNormalizeStrength(double v) {
    normalizeStrength = v.clamp(0, 1).toDouble();
    _p.setDouble('normalizeStrength', normalizeStrength);
    notifyListeners();
  }

  void setLyricsStyle({int? color, double? opacity, double? statusOffset}) {
    if (color != null) {
      lyricsColor = color;
      _p.setInt('lyricsColor', color);
    }
    if (opacity != null) {
      lyricsOpacity = opacity.clamp(0.3, 1).toDouble();
      _p.setDouble('lyricsOpacity', lyricsOpacity);
    }
    if (statusOffset != null) {
      statusLyricsOffset = statusOffset.clamp(-0.4, 0.4).toDouble();
      _p.setDouble('statusLyricsOffset', statusLyricsOffset);
    }
    notifyListeners();
  }

  /// 桌面歌词实际使用的颜色。
  Color get lyricsDisplayColor => lyricsColor == 0 ? accent.base : Color(lyricsColor);

  void setVolumeBoost(int db) {
    volumeBoost = db;
    _p.setInt('volumeBoost', db);
    notifyListeners();
  }

  void setHomeLayout(HomeLayout v) {
    homeLayout = v;
    _p.setInt('homeLayout', v.index);
    notifyListeners();
  }

  void setOrientation(ScreenOrientation v) {
    orientation = v;
    _p.setInt('orientation', v.index);
    notifyListeners();
  }

  void setGlassMaterial(GlassMaterial m) {
    glassMaterial = m;
    _p.setInt('glassMaterial', m.index);
    notifyListeners();
  }

  void setBackground(BackgroundMode m, {String? image}) {
    background = m;
    _p.setInt('background', m.index);
    if (image != null) {
      backgroundImage = image;
      _p.setString('backgroundImage', image);
    }
    notifyListeners();
  }

  void setLyricScale(double v) {
    lyricScale = v;
    _p.setDouble('lyricScale', v);
    notifyListeners();
  }

  /// 当前应使用的图标颜色。
  AccentColor get iconAccent => iconFollowsAccent ? accent : AccentColor.red;

  void skipUpdate(String version) {
    skippedUpdate = version;
    _p.setString('skippedUpdate', version);
  }

  void setDownloadDir(String dir) {
    downloadDir = dir;
    _p.setString('downloadDir', dir);
    notifyListeners();
  }

  void setVolume(double v) {
    volume = v;
    _p.setDouble('volume', v);
  }

  void addSearch(String q) {
    final k = q.trim();
    if (k.isEmpty) return;
    searchHistory.remove(k);
    searchHistory.insert(0, k);
    if (searchHistory.length > 12) searchHistory = searchHistory.sublist(0, 12);
    _p.setStringList('searchHistory', searchHistory);
    notifyListeners();
  }

  void clearSearch() {
    searchHistory = [];
    _p.setStringList('searchHistory', searchHistory);
    notifyListeners();
  }
}
