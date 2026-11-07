@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/core/lyric_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('霞鹜文楷：从官方发布地址下载、校验并载入', () async {
    // 测试框架默认拦截所有网络请求（返回 400），联网测试需要真实网络。
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('yunyin_font');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    await LyricFonts.instance.download();
    expect(LyricFonts.instance.loaded, isTrue);
    expect(File(LyricFonts.instance.filePath!).lengthSync(), greaterThan(10000000));
    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
