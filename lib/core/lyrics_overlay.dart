import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../player/player_controller.dart';
import 'settings.dart';

/// 桌面歌词与状态栏歌词的当前内容：跟随播放进度计算当前句与下一句，只在换句时通知。
///
/// Android 上把内容推给原生悬浮窗（见 android/.../LyricsOverlay.kt）；桌面端由外壳读取 [line] / [next]
/// 显示为置顶的歌词条窗口。
class LyricsOverlay extends ChangeNotifier {
  LyricsOverlay._(this._player, this._settings);

  static const _channel = MethodChannel('yunyin/lyrics_overlay');
  static bool get _android => !kIsWeb && Platform.isAndroid;

  final PlayerController _player;
  final AppSettings _settings;

  String line = '';
  String next = '';
  int _index = -2;
  Object? _lyrics;
  String? _songKey;
  String _config = '';

  static LyricsOverlay attach(PlayerController player, AppSettings settings) {
    final o = LyricsOverlay._(player, settings);
    player.addListener(o._onPlayer);
    player.position.addListener(o._compute);
    settings.addListener(o._configure);
    o._configure();
    o._onPlayer();
    return o;
  }

  /// 是否已获得悬浮窗权限（非 Android 平台总是 true）。
  static Future<bool> canDraw() async {
    if (!_android) return true;
    return await _channel.invokeMethod<bool>('canDraw') ?? false;
  }

  /// 打开系统的“显示在其他应用上层”设置页。
  static Future<void> requestPermission() async {
    if (_android) await _channel.invokeMethod<void>('requestPermission');
  }

  bool get _active => _settings.desktopLyrics || _settings.statusBarLyrics;

  void _configure() {
    final playing = _player.playing;
    final key =
        '${_settings.desktopLyrics}|${_settings.statusBarLyrics}|${_settings.lyricsLocked}|$playing|${_settings.lyricsDisplayColor.toARGB32()}|${_settings.lyricsOpacity}|${_settings.statusLyricsOffset}|${_settings.statusLyricsColor}';
    if (key == _config) return;
    _config = key;
    _index = -2;
    if (_android) {
      _channel.invokeMethod<void>('configure', {
        'desktop': _settings.desktopLyrics,
        // 暂停时收起状态栏歌词，把状态栏还给系统。
        'status': _settings.statusBarLyrics && playing,
        'locked': _settings.lyricsLocked,
        'accent': _settings.lyricsDisplayColor.toARGB32(),
        'opacity': _settings.lyricsOpacity,
        'statusOffset': _settings.statusLyricsOffset,
        'statusColor': _settings.statusLyricsDisplayColor.toARGB32(),
      });
    }
    _compute();
  }

  void _onPlayer() {
    final song = _player.current;
    final key = song?.key;
    if (!identical(_lyrics, _player.lyrics) || key != _songKey) {
      _lyrics = _player.lyrics;
      _songKey = key;
      _index = -2;
    }
    _configure();
    _compute();
  }

  void _compute() {
    if (!_active) return;
    final song = _player.current;
    final lines = _player.lyrics.lines;
    final synced = _player.lyrics.synced && lines.isNotEmpty;
    var i = -1;
    if (synced) {
      final pos = _player.position.value;
      // 二分查找最后一句开始时间不晚于当前进度的歌词。
      var lo = 0, hi = lines.length - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        if (lines[mid].time <= pos) {
          i = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
    }
    if (i == _index && _index != -2) return;
    _index = i;
    if (song == null) {
      line = '';
      next = '';
    } else if (!synced || i < 0) {
      // 没有歌词或还没到第一句：显示歌名与歌手。
      line = song.name;
      next = song.artistText;
    } else {
      line = lines[i].text;
      next = i + 1 < lines.length ? lines[i + 1].text : '';
    }
    notifyListeners();
    if (_android) _channel.invokeMethod<void>('update', {'line': line, 'next': next});
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    _player.position.removeListener(_compute);
    _settings.removeListener(_configure);
    super.dispose();
  }
}
