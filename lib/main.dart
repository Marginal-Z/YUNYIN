import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'debug/lx_selftest.dart';
import 'assistant/assistant_controller.dart';
import 'assistant/assistant_settings.dart';
import 'core/app_icon.dart';
import 'core/data_cache.dart';
import 'core/lyrics_overlay.dart';
import 'core/widget_bridge.dart';
import 'data/listen_stats.dart';
import 'core/ui/liquid_glass_filter.dart';
import 'core/update/updater.dart';
import 'core/lyric_fonts.dart';
import 'core/settings.dart';
import 'core/smooth_wheel.dart';
import 'debug/benchmark.dart';
import 'debug/screenshots.dart';
import 'data/downloads.dart';
import 'data/cloud/cloud_drives.dart';
import 'data/local_library.dart';
import 'data/lx/lx_sources.dart';
import 'data/sources/source_manager.dart';
import 'features/desktop/lyrics_window.dart';
import 'features/desktop/window_controls.dart';
import 'player/player_controller.dart';
import 'player/system_media.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // 桌面歌词是独立的窗口（单独的 Flutter 引擎），入口参数为 ["multi_window", 窗口 ID, 窗口参数]。
  if (isDesktopPlatform && args.firstOrNull == 'multi_window') {
    await runLyricsWindow(args.length > 2 ? args[2] : '{}');
    return;
  }
  SmoothWheel.install();

  if (isDesktopPlatform) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 820),
      minimumSize: Size(960, 640),
      center: true,
      title: '云音',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } else if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    // 许多 Android 设备默认把应用限制在 60Hz，这里请求屏幕支持的最高刷新率（90/120/144Hz…）。
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e) {
      debugPrint('display mode: $e');
    }
  }

  if (lxSelfTestRequested) {
    await runLxSelfTest();
    return;
  }
  await LiquidGlassShader.init();
  // 液态玻璃着色器的第三方许可证，显示在“开源许可”中。
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['liquid-glass-studio', 'GLSL-Color-Functions'], await rootBundle.loadString('shaders/THIRD_PARTY_NOTICES.txt'));
  });
  final settings = AppSettings();
  await settings.init();
  // 已下载的歌词字体（霞鹜文楷）在后台载入，不拖慢启动。
  unawaited(LyricFonts.instance.init());
  final local = LocalLibrary();
  await local.init();
  final drives = CloudDrives();
  await drives.init();
  // 洛雪音源：只用于洛雪曲库模式（三个平台只播放各自官方接口的歌曲）。
  final lx = LxSources();
  await lx.init();
  final sources = SourceManager(SourceRegistry.create(local, drives, lx));
  // 本地歌曲联网补全封面与歌词：依次在网易云、QQ 音乐、酷狗中匹配。
  local.onlineSources = [
    for (final id in const ['netease', 'qq', 'kugou']) ...sources.sources.where((s) => s.id == id),
  ];
  await sources.init();
  // 平台模式彼此独立：切换平台时一并切换该平台的界面样式与播放队列。
  settings.initPlatform(sources.current.id);
  sources.addListener(() => settings.applyPlatform(sources.current.id));
  // 首页先显示上次的数据，随后在后台刷新。
  await DataCache.restoreHome(sources.current.id, sources.current.user?.id);
  final player = PlayerController(sources, settings);
  await player.init();
  final stats = ListenStats();
  await stats.init();
  stats.attach(player);
  // Android 桌面小组件显示正在播放的歌曲。
  WidgetBridge.attach(player);
  // 桌面歌词与状态栏歌词。
  final lyricsOverlay = LyricsOverlay.attach(player, settings);
  if (isDesktopPlatform) DesktopLyricsWindow.attach(lyricsOverlay, player, settings);
  final downloads = DownloadManager(sources, settings);
  await downloads.init();
  player.localLookup = downloads.local;
  await SystemMediaHandler.attach(player);
  AppIconController(settings);
  final updater = UpdateManager();
  await updater.init();
  // 云音助手（语音唤醒打开时在这里开始监听）。
  final assistantSettings = AssistantSettings();
  await assistantSettings.init();
  final assistant = AssistantController(settings: assistantSettings, app: settings, player: player, sources: sources, stats: stats);
  if (!benchmarkRequested && !screenshotsRequested) unawaited(assistant.init());

  if (splashShotsRequested) prepareSplashShots();
  runApp(YunyinApp(settings: settings, sources: sources, player: player, downloads: downloads, local: local, drives: drives, updater: updater, stats: stats, lyricsOverlay: lyricsOverlay, lx: lx, assistant: assistant));
  if (benchmarkRequested) unawaited(runBenchmark(rootNavigatorKey));
  if (screenshotsRequested) unawaited(runScreenshots(rootNavigatorKey));
  if (splashShotsRequested) unawaited(runSplashShots());
}
