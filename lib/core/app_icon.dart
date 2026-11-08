import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'settings.dart';

/// 让系统中的应用图标跟随主题色：
/// Android 切换桌面图标入口；Windows / Linux 更换窗口与任务栏图标；macOS 更换程序坞图标。
class AppIconController {
  AppIconController(this.settings) {
    settings.addListener(_sync);
    _sync();
  }

  static const _channel = MethodChannel('yunyin/app_icon');

  final AppSettings settings;
  String? _applied;

  /// Android：三星 Good Lock“主题公园”是否套用了图标主题。它按应用包名统一替换图标（不在主题里的应用
  /// 显示默认图标），切换图标入口不会生效。其他系统或读取失败时为 false。
  static Future<bool> iconThemeOverrides() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<String>('iconTheme') != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _sync() async {
    final name = settings.iconAccent.name;
    // Android 关闭“跟随主题色”时使用默认入口：它带单色图层，系统开启主题图标时随壁纸变色；
    // 彩色入口不带单色图层，开启主题图标后仍显示所选的主题色。
    final android = settings.iconFollowsAccent ? name : 'default';
    final key = defaultTargetPlatform == TargetPlatform.android ? android : name;
    if (kIsWeb || key == _applied) return;
    _applied = key;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await _channel.invokeMethod('setIcon', {'name': android});
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
