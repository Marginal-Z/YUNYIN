import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('损坏的枚举设置不会阻止启动，使用默认值', () async {
    SharedPreferences.setMockInitialValues({'themeMode': 999, 'accent': -1, 'quality': 999, 'downloadQuality': -1});
    final settings = AppSettings();
    addTearDown(settings.dispose);
    await settings.init();
    expect(settings.themeMode, ThemeMode.light);
    expect(settings.accent, AccentColor.red);
    expect(settings.quality, AudioQuality.hires);
    expect(settings.downloadQuality, AudioQuality.higher);
  });

  test('设置类型损坏及非有限数值不会使启动或滑块失败', () async {
    SharedPreferences.setMockInitialValues({
      'themeMode': 'broken',
      'crossfade': 1,
      'volume': double.nan,
      'normalizeStrength': double.infinity,
      'lyricsOpacity': 9.0,
      'statusLyricsOffset': -5.0,
      'lyricScale': double.nan,
      'volumeBoost': 900,
      'eqGains': ['NaN', 'Infinity', '-Infinity', '100', '-100', 'wrong', '0', '1', '2', '3'],
    });
    final settings = AppSettings();
    addTearDown(settings.dispose);
    await settings.init();
    expect(settings.crossfade, isTrue);
    expect(settings.volume, 0.65);
    expect(settings.normalizeStrength, 1);
    expect(settings.lyricsOpacity, 1);
    expect(settings.statusLyricsOffset, -0.4);
    expect(settings.lyricScale, 1);
    expect(settings.volumeBoost, AppSettings.maxVolumeBoost);
    expect(settings.eqGains, everyElement(inInclusiveRange(-12, 12)));
  });

  test('单个损坏的平台样式不影响其余平台样式恢复', () async {
    SharedPreferences.setMockInitialValues({'platformStyles': '{"broken":[],"qq":[1,2]}'});
    final settings = AppSettings();
    addTearDown(settings.dispose);
    await settings.init();
    settings.applyPlatform('qq');
    expect(settings.accent, AccentColor.blue);
    expect(settings.playerStyle, PlayerStyle.disc);
  });

  test('音频设置拒绝非有限值和非法频段，保持合法范围', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    addTearDown(settings.dispose);
    await settings.init();
    settings.setVolume(double.nan);
    settings.setNormalizeStrength(double.nan);
    settings.setEqGain(-1, 1);
    settings.setEqGain(0, double.nan);
    settings.setVolumeBoost(900);
    expect(settings.volume, 0.65);
    expect(settings.normalizeStrength, 1);
    expect(settings.eqGains.first, 0);
    expect(settings.volumeBoost, AppSettings.maxVolumeBoost);
  });
}
