import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../player/player_controller.dart';
import 'ui/cover.dart';

/// 把正在播放的歌曲同步到 Android 桌面小组件（见 android/.../NowPlayingWidget.kt）。
/// 只在歌曲或播放状态变化时更新；封面先下载到图片缓存，再把文件路径交给小组件。
class WidgetBridge {
  WidgetBridge._(this._player);

  static const _channel = MethodChannel('yunyin/widget');

  final PlayerController _player;
  String? _last;
  Timer? _debounce;

  static void attach(PlayerController player) {
    if (kIsWeb || !Platform.isAndroid) return;
    final b = WidgetBridge._(player);
    player.addListener(b._onChange);
    b._onChange();
  }

  void _onChange() {
    final song = _player.current;
    final key = '${song?.sourceId}:${song?.id}:${_player.playing}';
    if (key == _last) return;
    _last = key;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _push);
  }

  Future<void> _push() async {
    final song = _player.current;
    String? cover;
    final url = song?.coverUrl;
    try {
      if (url != null && url.isNotEmpty) {
        if (isLocalPath(url)) {
          cover = url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
        } else {
          final sized = url.contains('music.126.net') && !url.contains('?') ? '$url?param=300y300' : url;
          cover = (await DefaultCacheManager().getSingleFile(sized)).path;
        }
      }
      await _channel.invokeMethod<void>('update', {
        'title': song?.name,
        'artist': song?.artistText,
        'cover': cover,
        'playing': _player.playing,
      });
    } catch (e) {
      debugPrint('widget update: $e');
    }
  }
}
