import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/settings.dart';
import 'debug/benchmark.dart';
import 'data/downloads.dart';
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

  final settings = AppSettings();
  await settings.init();
  final sources = SourceManager(SourceRegistry.create());
  await sources.init(fallbackId: defaultSourceFor(isWeb: kIsWeb));
  final player = PlayerController(sources, settings);
  await player.init();
  final downloads = DownloadManager(sources, settings);
  await downloads.init();
  player.localLookup = downloads.local;
  await SystemMediaHandler.attach(player);

  runApp(YunyinApp(settings: settings, sources: sources, player: player, downloads: downloads));
  if (benchmarkRequested) unawaited(runBenchmark(rootNavigatorKey));
}
