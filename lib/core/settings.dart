import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import 'theme/palette.dart';

/// 用户设置，持久化在 SharedPreferences。
class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;

  ThemeMode themeMode = ThemeMode.light;
  AccentColor accent = AccentColor.red;
  AudioQuality quality = AudioQuality.lossless;
  AudioQuality downloadQuality = AudioQuality.higher;
  bool crossfade = true;
  bool normalize = true;
  bool wifiOnlyDownload = true;
  bool autoClean = true;
  bool glass = true;
  bool pushNotify = true;
  bool personalized = true;
  bool showTranslation = false;
  String? downloadDir;
  double volume = 0.65;
  List<String> searchHistory = [];

  final Map<(bool, AccentColor), Palette> _palettes = {};

  Palette palette(bool dark) =>
      _palettes.putIfAbsent((dark, accent), () => dark ? Palette.dark(accent) : Palette.light(accent));

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[_p.getInt('themeMode') ?? ThemeMode.light.index];
    accent = AccentColor.values[_p.getInt('accent') ?? 0];
    quality = AudioQuality.values[_p.getInt('quality') ?? AudioQuality.lossless.index];
    downloadQuality = AudioQuality.values[_p.getInt('downloadQuality') ?? AudioQuality.higher.index];
    crossfade = _p.getBool('crossfade') ?? true;
    normalize = _p.getBool('normalize') ?? true;
    wifiOnlyDownload = _p.getBool('wifiOnlyDownload') ?? true;
    autoClean = _p.getBool('autoClean') ?? true;
    glass = _p.getBool('glass') ?? true;
    pushNotify = _p.getBool('pushNotify') ?? true;
    personalized = _p.getBool('personalized') ?? true;
    showTranslation = _p.getBool('showTranslation') ?? false;
    downloadDir = _p.getString('downloadDir');
    volume = _p.getDouble('volume') ?? 0.65;
    searchHistory = _p.getStringList('searchHistory') ?? ['晚风', '雨天唱片行', '沈南乔', '民谣', '海岸线', '夜行列车'];
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
    }
    _p.setBool(key, v);
    notifyListeners();
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
