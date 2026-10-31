import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 状态栏与导航栏的沉浸（隐藏）状态。多个页面可以同时要求沉浸（例如横屏播放页上再打开歌词页），
/// 全部释放后才恢复显示，避免关闭上层页面时把下层页面的沉浸状态一并取消。
abstract final class SystemBars {
  static final _owners = <Object>{};
  static bool? _applied;

  static bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static void immersive(Object owner, bool on) {
    if (on) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    if (!_supported) return;
    final want = _owners.isNotEmpty;
    if (want == _applied) return;
    _applied = want;
    SystemChrome.setEnabledSystemUIMode(want ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }
}
