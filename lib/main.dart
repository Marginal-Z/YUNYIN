import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_icon.dart';
import 'core/update/updater.dart';
import 'core/settings.dart';
import 'debug/benchmark.dart';
import 'data/downloads.dart';
import 'data/local_library.dart';
import 'data/sources/source_manager.dart';
import 'features/desktop/window_controls.dart';
import 'player/player_controller.dart';
import 'player/system_media.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  final settings = AppSettings();
  await settings.init();
  final local = LocalLibrary();
  await local.init();
  final sources = SourceManager(SourceRegistry.create(local));
  await sources.init();
  final player = PlayerController(sources, settings);
  await player.init();
  final downloads = DownloadManager(sources, settings);
  await downloads.init();
  player.localLookup = downloads.local;
  await SystemMediaHandler.attach(player);
  AppIconController(settings);
  final updater = UpdateManager();
  await updater.init();

  runApp(YunyinApp(settings: settings, sources: sources, player: player, downloads: downloads, local: local, updater: updater));
  if (benchmarkRequested) unawaited(runBenchmark(rootNavigatorKey));
}
