import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_icon.dart';
import 'core/data_cache.dart';
import 'data/listen_stats.dart';
import 'core/ui/liquid_glass_filter.dart';
import 'core/update/updater.dart';
import 'core/settings.dart';
import 'core/smooth_wheel.dart';
import 'debug/benchmark.dart';
import 'debug/screenshots.dart';
import 'data/downloads.dart';
import 'data/local_library.dart';
import 'data/sources/source_manager.dart';
import 'features/desktop/window_controls.dart';
import 'player/player_controller.dart';
import 'player/system_media.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  await LiquidGlassShader.init();
  // 液态玻璃着色器的第三方许可证，显示在“开源许可”中。
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['liquid-glass-studio', 'GLSL-Color-Functions'], await rootBundle.loadString('shaders/THIRD_PARTY_NOTICES.txt'));
  });
  final settings = AppSettings();
  await settings.init();
  final local = LocalLibrary();
  await local.init();
  final sources = SourceManager(SourceRegistry.create(local));
  // 本地歌曲联网补全封面与歌词使用网易云。
  local.online = sources.sources.where((s) => s.id == 'netease').firstOrNull;
  await sources.init();
  // 首页先显示上次的数据，随后在后台刷新。
  await DataCache.restoreHome(sources.current.id, sources.current.user?.id);
  final player = PlayerController(sources, settings);
  await player.init();
  final stats = ListenStats();
  await stats.init();
  stats.attach(player);
  final downloads = DownloadManager(sources, settings);
  await downloads.init();
  player.localLookup = downloads.local;
  await SystemMediaHandler.attach(player);
  AppIconController(settings);
  final updater = UpdateManager();
  await updater.init();

  runApp(YunyinApp(settings: settings, sources: sources, player: player, downloads: downloads, local: local, updater: updater, stats: stats));
  if (benchmarkRequested) unawaited(runBenchmark(rootNavigatorKey));
  if (screenshotsRequested) unawaited(runScreenshots(rootNavigatorKey));
}
