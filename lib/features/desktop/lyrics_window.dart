import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/lyrics_overlay.dart';
import '../../core/settings.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../player/player_controller.dart';

/// 桌面歌词窗口的启动参数（新窗口的 Dart 入口参数为 ["multi_window", 窗口 ID, 这个值]）。
const kLyricsWindowArgument = 'desktop_lyrics';

/// 两个窗口之间的通道：主窗口推送歌词与样式，歌词窗口回传切歌、暂停、关闭与拖动后的位置。
const _channel = WindowMethodChannel('yunyin/desktop_lyrics');

const _size = Size(820, 124);

/// 主窗口一侧：桌面歌词开关打开时创建（或显示）独立的置顶歌词窗口，主窗口保持原样。
class DesktopLyricsWindow {
  DesktopLyricsWindow._(this._overlay, this._player, this._settings);

  final LyricsOverlay _overlay;
  final PlayerController _player;
  final AppSettings _settings;
  WindowController? _window;
  Future<void>? _creating;
  bool _shown = false;
  bool _ready = false;
  String _last = '';

  static const _positionKey = 'desktopLyrics.position';

  static DesktopLyricsWindow attach(LyricsOverlay overlay, PlayerController player, AppSettings settings) {
    final w = DesktopLyricsWindow._(overlay, player, settings);
    _channel.setMethodCallHandler(w._onCall);
    overlay.addListener(w._push);
    player.addListener(w._push);
    settings.addListener(w._sync);
    w._sync();
    return w;
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'ready':
        _ready = true;
        _last = '';
        // 创建期间又关掉了桌面歌词：新窗口已自己显示出来，收起。
        if (!_shown) unawaited(_window?.hide());
        return _state();
      case 'previous':
        await _player.previous();
      case 'toggle':
        await _player.toggle();
      case 'next':
        await _player.next();
      case 'close':
        _settings.setFlag('desktopLyrics', false);
      case 'moved':
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_positionKey, jsonEncode(call.arguments));
    }
    return null;
  }

  Map<String, Object?> _state() => {
    'line': _overlay.line,
    'next': _overlay.next,
    'playing': _player.playing,
    'color': _settings.lyricsDisplayColor.toARGB32(),
    'opacity': _settings.lyricsOpacity,
    'locked': _settings.lyricsLocked,
  };

  void _sync() {
    final on = _settings.desktopLyrics;
    if (on != _shown) {
      _shown = on;
      unawaited(on ? _show() : _hide());
    }
    _push();
  }

  Future<void> _show() async {
    if (_window == null) {
      final prefs = await SharedPreferences.getInstance();
      _creating ??= WindowController.create(
        WindowConfiguration(arguments: jsonEncode({'type': kLyricsWindowArgument, 'position': prefs.getString(_positionKey)})),
      ).then((w) => _window = w);
      await _creating;
      // 新窗口准备好后会发来 ready，自己显示出来。
      return;
    }
    if (_shown) await _window!.show();
  }

  Future<void> _hide() async {
    await _creating;
    if (!_shown) await _window?.hide();
  }

  /// 推送当前歌词与样式，内容没有变化时不发送。
  void _push() {
    if (!_ready || !_shown) return;
    final state = _state();
    final key = jsonEncode(state);
    if (key == _last) return;
    _last = key;
    _channel.invokeMethod<void>('update', state).catchError((Object e) => debugPrint('desktop lyrics: $e'));
  }
}

/// 歌词窗口一侧的入口：无边框、置顶、不显示在任务栏的歌词条。
Future<void> runLyricsWindow(String arguments) async {
  final args = jsonDecode(arguments) as Map<String, dynamic>;
  await windowManager.ensureInitialized();
  await windowManager.setAsFrameless();
  await windowManager.setBackgroundColor(Colors.transparent);
  await windowManager.setTitle('云音桌面歌词');
  await windowManager.setSkipTaskbar(true);
  await windowManager.setMinimumSize(const Size(420, 96));
  await windowManager.setSize(_size);
  await windowManager.setAlwaysOnTop(true);
  Offset? position;
  try {
    final p = jsonDecode('${args['position']}') as Map<String, dynamic>;
    position = Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble());
  } catch (_) {}
  if (position == null) {
    // 默认放在屏幕下方居中。
    final display = ui.PlatformDispatcher.instance.displays.firstOrNull;
    if (display != null) {
      final screen = display.size / display.devicePixelRatio;
      position = Offset((screen.width - _size.width) / 2, screen.height - _size.height - 96);
    }
  }
  if (position != null) await windowManager.setPosition(position);
  runApp(const _LyricsApp());
  await windowManager.show();
}

class _LyricsApp extends StatefulWidget {
  const _LyricsApp();

  @override
  State<_LyricsApp> createState() => _LyricsAppState();
}

class _LyricsAppState extends State<_LyricsApp> with WindowListener {
  Map<dynamic, dynamic> _state = const {};
  bool _hover = false;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'update') _apply(call.arguments as Map);
      return null;
    });
    _channel.invokeMethod<Map>('ready').then((s) => s == null ? null : _apply(s)).catchError((Object e) => debugPrint('desktop lyrics: $e'));
  }

  void _apply(Map<dynamic, dynamic> s) {
    final locked = s['locked'] == true;
    if (locked != _locked) {
      _locked = locked;
      // 锁定后鼠标穿透歌词窗口，在设置里解锁。
      windowManager.setIgnoreMouseEvents(locked);
    }
    if (mounted) setState(() => _state = s);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMoved() async {
    final p = await windowManager.getPosition();
    _channel.invokeMethod<void>('moved', {'x': p.dx, 'y': p.dy}).catchError((Object _) {});
  }

  void _send(String method) => _channel.invokeMethod<void>(method).catchError((Object e) => debugPrint('desktop lyrics: $e'));

  @override
  Widget build(BuildContext context) {
    final color = Color(_state['color'] as int? ?? 0xFFFFFFFF);
    final opacity = (_state['opacity'] as num?)?.toDouble() ?? 1;
    final playing = _state['playing'] == true;
    const shadow = [Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1))];
    Widget button(YIconData icon, String label, String method) => Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: () => _send(method),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(child: YIcon(icon, size: 20, color: Colors.white)),
        ),
      ),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(canvasColor: Colors.transparent, scaffoldBackgroundColor: Colors.transparent),
      home: Material(
        type: MaterialType.transparency,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startDragging(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                // 不支持透明窗口的系统上也能看清：始终保留一层很淡的底板。
                color: Color.fromRGBO(0, 0, 0, _hover ? 0.55 : 0.18),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          child: Text(
                            '${_state['line'] ?? ''}',
                            key: ValueKey('${_state['line']}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ts(30, weight: w700, color: color.withValues(alpha: opacity)).copyWith(shadows: shadow),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_state['next'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(17, weight: w500, color: Colors.white.withValues(alpha: 0.9 * opacity)).copyWith(shadows: shadow),
                        ),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: _hover ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_hover,
                      child: Row(
                        children: [
                          button(YIcons.prev, '上一首', 'previous'),
                          button(playing ? YIcons.pause : YIcons.play, playing ? '暂停' : '播放', 'toggle'),
                          button(YIcons.next, '下一首', 'next'),
                          button(YIcons.close, '关闭桌面歌词', 'close'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
