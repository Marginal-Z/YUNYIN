import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yunyin/core/lyrics_overlay.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/data/sources/local/local_source.dart';
import 'package:yunyin/data/local_library.dart';
import 'package:yunyin/features/desktop/lyrics_window.dart';
import 'package:yunyin/player/player_controller.dart';

/// 桌面端：打开桌面歌词时创建独立的歌词窗口，主窗口保持原来的大小（不再缩小成歌词条）。
Future<void> main(List<String> args) async {
  // 歌词窗口的新引擎也从这个入口启动。
  if (args.firstOrNull == 'multi_window') {
    WidgetsFlutterBinding.ensureInitialized();
    await runLyricsWindow(args.length > 2 ? args[2] : '{}');
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('打开桌面歌词：独立的歌词窗口启动并连通，主窗口大小不变', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await windowManager.ensureInitialized();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: Text('云音')))));
    await windowManager.setSize(const Size(1100, 760));
    await tester.pump(const Duration(milliseconds: 300));
    final before = await windowManager.getSize();

    final settings = AppSettings();
    await settings.init();
    final player = PlayerController(SourceManager([LocalSource(LocalLibrary())]), settings);
    final overlay = LyricsOverlay.attach(player, settings);
    final lyrics = DesktopLyricsWindow.attach(overlay, player, settings);

    settings.setFlag('desktopLyrics', true);
    for (var i = 0; i < 100 && !lyrics.ready; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(lyrics.ready, isTrue, reason: '歌词窗口应在 20 秒内启动并与主窗口连通');
    expect(await WindowController.getAll(), hasLength(2));
    expect(await windowManager.getSize(), before, reason: '主窗口不应改变大小');

    settings.setFlag('desktopLyrics', false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(await windowManager.getSize(), before);
  });
}
