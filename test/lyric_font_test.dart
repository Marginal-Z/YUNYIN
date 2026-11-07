import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/lyric_fonts.dart';
import 'package:yunyin/core/settings.dart';

void main() {
  test('歌词字体样式：各样式的字体族与字重', () {
    expect(lyricTextStyle(LyricFont.system, 30).fontWeight, FontWeight.w700);
    expect(lyricTextStyle(LyricFont.light, 30).fontWeight, FontWeight.w300);
    expect(lyricTextStyle(LyricFont.heavy, 30).fontWeight, FontWeight.w900);
    final serif = lyricTextStyle(LyricFont.serif, 30);
    expect(serif.fontFamily, 'Noto Serif CJK SC');
    expect(serif.fontFamilyFallback, contains('serif'), reason: 'Android 上按通用的 serif 字体族找到系统宋体');
    expect(serif.fontWeight, FontWeight.w400, reason: '系统宋体通常只有常规字重');
    expect(lyricTextStyle(LyricFont.kai, 30).fontFamilyFallback, contains('KaiTi'));
    expect(lyricTextStyle(LyricFont.wenkai, 30).fontFamily, LyricFonts.family);
    expect(lyricTextStyle(LyricFont.wenkai, 30).fontWeight, FontWeight.w500);
    expect(lyricTextStyle(LyricFont.serif, 30, color: const Color(0xFFFF0000)).color, const Color(0xFFFF0000));
  });

  test('歌词字体样式随设置保存，损坏的值退回默认', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    await s.init();
    expect(s.lyricFont, LyricFont.system);
    s.setLyricFont(LyricFont.kai);
    final again = AppSettings();
    await again.init();
    expect(again.lyricFont, LyricFont.kai);
    SharedPreferences.setMockInitialValues({'flutter.lyricFont': 99});
    final broken = AppSettings();
    await broken.init();
    expect(broken.lyricFont, LyricFont.system);
  });
}
