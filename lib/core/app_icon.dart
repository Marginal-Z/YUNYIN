import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'settings.dart';
import 'theme/palette.dart';

/// 让系统中的应用图标跟随主题色：
/// Android 切换桌面图标入口；Windows / Linux 更换窗口与任务栏图标；macOS 更换程序坞图标。
class AppIconController {
  AppIconController(this.settings) {
    settings.addListener(_sync);
    _sync();
  }

  static const _channel = MethodChannel('yunyin/app_icon');

  final AppSettings settings;
  AccentColor? _applied;

  Future<void> _sync() async {
    final accent = settings.iconAccent;
    if (kIsWeb || accent == _applied) return;
    _applied = accent;
    final name = accent.name;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await _channel.invokeMethod('setIcon', {'name': name});
        case TargetPlatform.windows:
          await windowManager.setIcon('assets/icon/themes/$name.ico');
        case TargetPlatform.linux:
          await windowManager.setIcon('assets/icon/themes/$name.png');
        case TargetPlatform.macOS:
          await _channel.invokeMethod('setIcon', {'asset': 'assets/icon/themes/$name.png'});
        default:
          break;
      }
    } catch (e) {
      debugPrint('app icon: $e');
    }
  }
}
