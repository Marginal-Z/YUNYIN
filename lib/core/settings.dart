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

/// 用户设置，持久化在 SharedPreferences。
class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;

  ThemeMode themeMode = ThemeMode.light;
  AccentColor accent = AccentColor.red;
  AudioQuality quality = AudioQuality.lossless;
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
    quality = AudioQuality.values[_p.getInt('quality') ?? AudioQuality.lossless.index];
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
    notifyListeners();
  }

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
    }
    _p.setBool(key, v);
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
