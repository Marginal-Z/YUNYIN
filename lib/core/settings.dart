import 'lyric_fonts.dart';
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

/// 播放进度条的样式。
enum ProgressStyle {
  /// 已播放部分是流动的正弦波。
  wave('波浪'),

  /// 细直线加圆点。
  line('直线'),

  /// 粗圆角条，拖动时变粗。
  capsule('胶囊'),

  /// 一串圆点，当前位置的圆点随播放跳动。
  dots('节拍点'),

  /// 高低错落的声波柱（每首歌的形状固定）。
  bars('声波柱'),

  /// 渐变的发光线条，播放时有流光掠过。
  glow('流光');

  const ProgressStyle(this.label);
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

/// 界面风格。
enum UiStyle {
  glass('默认', '背景光晕与半透明卡片，可在下方开启液态玻璃效果'),
  neumorphic('新拟态', '同色柔和凸起，干净、不模糊，更省电');

  const UiStyle(this.label, this.description);
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
  custom('自定义', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  // 以下为后加入的音效（按序号保存，只能加在末尾）。
  hifi('Hi-Fi 臻品', [2, 2, 1, 0, 0, 0, 1, 1, 2, 3]),
  live('现场', [2, 1, 0, 1, 2, 3, 2, 1, 1, 2]),
  warm('温暖', [3, 3, 2, 1, 0, -1, -1, -2, -2, -3]),
  dj('DJ 劲爆', [6, 5, 3, 0, -1, 0, 1, 2, 3, 4]);

  const EqPreset(this.label, this.gains);
  final String label;
  final List<int> gains;

  /// 音效页中的显示顺序（自定义放在最后）。
  static const ordered = [flat, hifi, pop, vocal, live, rock, classical, jazz, electronic, dj, warm, bass, treble, custom];
}

/// 用户设置，持久化在 SharedPreferences。
class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;

  ThemeMode themeMode = ThemeMode.light;
  AccentColor accent = AccentColor.red;
  AudioQuality quality = AudioQuality.hires;
  AudioQuality downloadQuality = AudioQuality.higher;
  bool crossfade = true;

  /// 一首歌播放完后自动播放下一首；关闭时停在这首歌的结尾。
  bool autoNext = true;
  bool normalize = true;

  /// Android：使用 OpenSL ES 输出音频（个别设备上 AudioTrack 输出没有声音时的兼容选项）。
  bool openSles = false;

  /// 已播放过完整的启动动画；之后冷启动只播缩短版。
  bool splashSeen = false;

  /// 已同意的使用声明版本（首次启动时阅读并同意后才能进入应用；条款更新时提高 [kConsentVersion] 会重新询问）。
  int consentVersion = 0;
  static const kConsentVersion = 2;
  bool get consentAccepted => consentVersion >= kConsentVersion;

  void acceptConsent() {
    consentVersion = kConsentVersion;
    _p.setInt('consentVersion', consentVersion);
    notifyListeners();
  }

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

  /// 界面风格：液态玻璃或新拟态。
  UiStyle uiStyle = UiStyle.glass;

  /// 液态玻璃材质。
  GlassMaterial glassMaterial = GlassMaterial.clear;

  /// 界面背景。
  BackgroundMode background = BackgroundMode.glow;

  /// 播放页样式。
  PlayerStyle playerStyle = PlayerStyle.cover;

  /// 首页样式。
  HomeLayout homeLayout = HomeLayout.standard;

  /// 屏幕方向。

  /// 播放进度条的波浪动画。
  ProgressStyle progressStyle = ProgressStyle.wave;

  /// 音量增强（dB）：0–10。增益之后经过限幅器，响亮的歌曲也不会削波破音。
  int volumeBoost = 0;
  static const maxVolumeBoost = 10;

  /// 高保真引擎：高质量重采样（更长的 sinc 滤镜）与三角高通抖动，转换为 16 位输出时保留更多细节。
  bool hifiEngine = true;

  /// Android：空间音效（系统虚拟环绕）强度 0–1，0 为关闭。
  double spatial = 0;

  /// Android：低频增强强度 0–1，0 为关闭。
  double bassEnhance = 0;

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

  /// 切换平台时一并切换界面样式（主题色与播放样式），每个平台记住自己的样式。
  String _platform = 'netease';
  final Map<String, (int, int)> _platformStyles = {};

  /// 各平台第一次使用时的默认样式：网易云朱红 + 封面，QQ 音乐绿色 + 卡片流，酷狗蓝色 + 3D 封面流。
  static const _platformDefaults = {
    'netease': (AccentColor.red, PlayerStyle.cover),
    'qq': (AccentColor.teal, PlayerStyle.cardFlow),
    'kugou': (AccentColor.blue, PlayerStyle.coverFlow),
    'lx': (AccentColor.orange, PlayerStyle.wall),
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

  /// 状态栏歌词颜色（ARGB）；0 表示白色。
  int statusLyricsColor = 0;

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

  /// 歌词字体样式。
  LyricFont lyricFont = LyricFont.system;
  String? downloadDir;
  double volume = 0.65;
  List<String> searchHistory = [];

  final Map<(bool, AccentColor), Palette> _palettes = {};

  final Map<(bool, AccentColor), Palette> _neumorphic = {};

  /// 当前界面风格下的色板（新拟态为同色柔和凸起的变体）。按主题色缓存，色板对象不变时不会让整棵树重建。
  Palette palette(bool dark) {
    final base = _palettes.putIfAbsent((dark, accent), () => dark ? Palette.dark(accent) : Palette.light(accent));
    return uiStyle == UiStyle.neumorphic ? _neumorphic.putIfAbsent((dark, accent), base.neumorphicVariant) : base;
  }

  T? _read<T>(String key) {
    final value = _p.get(key);
    return value is T ? value : null;
  }

  T _enumValue<T>(String key, List<T> values, T fallback) {
    final index = _read<int>(key);
    return index != null && index >= 0 && index < values.length ? values[index] : fallback;
  }

  static double _boundedValue(double? value, double fallback, double minimum, double maximum) =>
      value != null && value.isFinite ? value.clamp(minimum, maximum).toDouble() : fallback;

  double _number(String key, double fallback, double minimum, double maximum) => _boundedValue(_read<num>(key)?.toDouble(), fallback, minimum, maximum);

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    themeMode = _enumValue('themeMode', ThemeMode.values, ThemeMode.light);
    accent = _enumValue('accent', AccentColor.values, AccentColor.red);
    quality = _enumValue('quality', AudioQuality.values, AudioQuality.hires);
    downloadQuality = _enumValue('downloadQuality', AudioQuality.values, AudioQuality.higher);
    crossfade = _read<bool>('crossfade') ?? true;
    autoNext = _read<bool>('autoNext') ?? true;
    normalize = _read<bool>('normalize') ?? true;
    openSles = _read<bool>('openSles') ?? false;
    splashSeen = _read<bool>('splashSeen') ?? false;
    consentVersion = _read<int>('consentVersion') ?? 0;
    wifiOnlyDownload = _read<bool>('wifiOnlyDownload') ?? true;
    autoClean = _read<bool>('autoClean') ?? true;
    glass = _read<bool>('glass') ?? true;
    pushNotify = _read<bool>('pushNotify') ?? true;
    personalized = _read<bool>('personalized') ?? true;
    showTranslation = _read<bool>('showTranslation') ?? false;
    iconFollowsAccent = _read<bool>('iconFollowsAccent') ?? true;
    coverColors = _read<bool>('coverColors') ?? true;
    autoUpdate = _read<bool>('autoUpdate') ?? true;
    glassMaterial = GlassMaterial.values[(_read<int>('glassMaterial') ?? 0).clamp(0, GlassMaterial.values.length - 1)];
    playerStyle = PlayerStyle.values[(_read<int>('playerStyle') ?? 0).clamp(0, PlayerStyle.values.length - 1)];
    homeLayout = HomeLayout.values[(_read<int>('homeLayout') ?? 0).clamp(0, HomeLayout.values.length - 1)];
    // 旧版本只有“波浪动画”开关：关闭时迁移为直线。
    final ps = _read<int>('progressStyle');
    progressStyle = ps != null
        ? ProgressStyle.values[ps.clamp(0, ProgressStyle.values.length - 1)]
        : (_read<bool>('waveProgress') ?? true ? ProgressStyle.wave : ProgressStyle.line);
    uiStyle = _enumValue('uiStyle', UiStyle.values, UiStyle.glass);
    volumeBoost = (_read<int>('volumeBoost') ?? 0).clamp(0, maxVolumeBoost);
    hifiEngine = _read<bool>('hifiEngine') ?? true;
    spatial = _number('spatial', 0, 0, 1);
    bassEnhance = _number('bassEnhance', 0, 0, 1);
    eqEnabled = _read<bool>('eqEnabled') ?? false;
    eqPreset = EqPreset.values[(_read<int>('eqPreset') ?? 0).clamp(0, EqPreset.values.length - 1)];
    final gains = _read<List<String>>('eqGains');
    if (gains != null && gains.length == kEqBands.length) eqGains = [for (final gain in gains) _boundedValue(double.tryParse(gain), 0, -12, 12)];
    normalizeStrength = _number('normalizeStrength', 1, 0, 1);
    hiResOutput = _read<bool>('hiResOutput') ?? false;
    exclusiveAudio = _read<bool>('exclusiveAudio') ?? false;
    try {
      final raw = _read<String>('platformStyles');
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is List && value.length == 2 && value[0] is int && value[1] is int) {
              _platformStyles['${entry.key}'] = (value[0] as int, value[1] as int);
            }
          }
        }
      }
    } catch (_) {}
    desktopLyrics = _read<bool>('desktopLyrics') ?? false;
    statusBarLyrics = _read<bool>('statusBarLyrics') ?? false;
    lyricsLocked = _read<bool>('lyricsLocked') ?? false;
    lyricsColor = _read<int>('lyricsColor') ?? 0;
    lyricsOpacity = _number('lyricsOpacity', 1, 0.3, 1);
    statusLyricsOffset = _number('statusLyricsOffset', 0, -0.4, 0.4);
    statusLyricsColor = _read<int>('statusLyricsColor') ?? 0;
    background = BackgroundMode.values[(_read<int>('background') ?? 0).clamp(0, BackgroundMode.values.length - 1)];
    backgroundImage = _read<String>('backgroundImage');
    backgroundBlur = _read<bool>('backgroundBlur') ?? false;
    if (background == BackgroundMode.image && backgroundImage == null) background = BackgroundMode.glow;
    skippedUpdate = _read<String>('skippedUpdate');
    lyricScale = _number('lyricScale', 1, 0.5, 2);
    lyricFont = _enumValue('lyricFont', LyricFont.values, LyricFont.system);
    downloadDir = _read<String>('downloadDir');
    volume = _number('volume', 0.65, 0, 1);
    searchHistory = _read<List<String>>('searchHistory') ?? [];
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
    _p.setString(
      'platformStyles',
      jsonEncode({
        for (final e in _platformStyles.entries) e.key: [e.value.$1, e.value.$2],
      }),
    );
  }

  /// 切换平台：记下离开的平台的样式，换成新平台记住的样式（第一次使用该平台时用平台默认样式）。
  void applyPlatform(String id) {
    if (id == _platform) return;
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
      case 'autoNext':
        autoNext = v;
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
      case 'eqEnabled':
        eqEnabled = v;
      case 'hiResOutput':
        hiResOutput = v;
      case 'exclusiveAudio':
        exclusiveAudio = v;
      case 'hifiEngine':
        hifiEngine = v;
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
    if (band < 0 || band >= eqGains.length || !db.isFinite) return;
    eqGains = List.of(eqGains)..[band] = db.clamp(-12, 12).toDouble();
    eqPreset = EqPreset.custom;
    _p.setInt('eqPreset', eqPreset.index);
    _p.setStringList('eqGains', [for (final g in eqGains) '$g']);
    notifyListeners();
  }

  void setNormalizeStrength(double v) {
    if (!v.isFinite) return;
    normalizeStrength = v.clamp(0, 1).toDouble();
    _p.setDouble('normalizeStrength', normalizeStrength);
    notifyListeners();
  }

  void setLyricsStyle({int? color, double? opacity, double? statusOffset, int? statusColor}) {
    if (statusColor != null) {
      statusLyricsColor = statusColor;
      _p.setInt('statusLyricsColor', statusColor);
    }
    if (color != null) {
      lyricsColor = color;
      _p.setInt('lyricsColor', color);
    }
    if (opacity != null && opacity.isFinite) {
      lyricsOpacity = opacity.clamp(0.3, 1).toDouble();
      _p.setDouble('lyricsOpacity', lyricsOpacity);
    }
    if (statusOffset != null && statusOffset.isFinite) {
      statusLyricsOffset = statusOffset.clamp(-0.4, 0.4).toDouble();
      _p.setDouble('statusLyricsOffset', statusLyricsOffset);
    }
    notifyListeners();
  }

  /// 状态栏歌词实际使用的颜色。
  Color get statusLyricsDisplayColor => statusLyricsColor == 0 ? const Color(0xFFFFFFFF) : Color(statusLyricsColor);

  /// 桌面歌词实际使用的颜色。
  Color get lyricsDisplayColor => lyricsColor == 0 ? accent.base : Color(lyricsColor);

  void setVolumeBoost(int db) {
    volumeBoost = db.clamp(0, maxVolumeBoost);
    _p.setInt('volumeBoost', volumeBoost);
    notifyListeners();
  }

  void setUiStyle(UiStyle v) {
    uiStyle = v;
    _p.setInt('uiStyle', v.index);
    notifyListeners();
  }

  void setSpatial(double v) {
    if (!v.isFinite) return;
    spatial = v.clamp(0, 1).toDouble();
    _p.setDouble('spatial', spatial);
    notifyListeners();
  }

  void setBassEnhance(double v) {
    if (!v.isFinite) return;
    bassEnhance = v.clamp(0, 1).toDouble();
    _p.setDouble('bassEnhance', bassEnhance);
    notifyListeners();
  }

  void setHomeLayout(HomeLayout v) {
    homeLayout = v;
    _p.setInt('homeLayout', v.index);
    notifyListeners();
  }

  void setProgressStyle(ProgressStyle v) {
    progressStyle = v;
    _p.setInt('progressStyle', v.index);
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

  void setLyricFont(LyricFont v) {
    lyricFont = v;
    _p.setInt('lyricFont', v.index);
    notifyListeners();
  }

  void setLyricScale(double v) {
    if (!v.isFinite) return;
    lyricScale = v.clamp(0.5, 2).toDouble();
    _p.setDouble('lyricScale', lyricScale);
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
    if (!v.isFinite) return;
    volume = v.clamp(0, 1).toDouble();
    _p.setDouble('volume', volume);
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
