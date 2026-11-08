import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../assistant/assistant_controller.dart';
import '../assistant/assistant_settings.dart';
import '../features/desktop/window_controls.dart' show isDesktopPlatform;
import '../player/player_controller.dart';
import '../voice/speech_output.dart';
import '../voice/voice_settings.dart';
import 'pet_painter.dart';
import 'pet_rig.dart';
import 'pet_view.dart';

/// 桌面窗口的启动参数类型（见 main.dart 的多窗口入口）。
const kPetWindowArgument = 'desk_pet';

/// 主窗口与桌宠窗口之间的通道（桌面端）。
const petWindowChannel = WindowMethodChannel('yunyin/desk_pet');

/// 由助手、朗读与播放器的状态得出桌宠的状态与气泡文字。
///
/// 优先级：倾听 > 思考 > 说话 > 出错 > 刚完成 > 跟着音乐摇摆 > 打瞌睡 > 待机。
class PetMoodRules {
  PetMoodRules({DateTime Function()? now}) : _now = now ?? DateTime.now {
    _lastActive = _now();
  }

  final DateTime Function() _now;
  late DateTime _lastActive;
  DateTime? _happyUntil;
  DateTime? _sadUntil;
  String? _lastError;
  AssistantStatus _lastStatus = AssistantStatus.idle;
  bool _wasSpeaking = false;
  String _reply = '';

  /// 待机多久后打瞌睡。
  static const sleepAfter = Duration(seconds: 90);

  (PetMood, String) compute({
    required AssistantStatus status,
    required String partial,
    required bool speaking,
    required bool playing,
    required String? lastReply,
    required String? error,
  }) {
    final now = _now();
    if (status != AssistantStatus.idle || speaking) _lastActive = now;
    if (error != null && error != _lastError) _sadUntil = now.add(const Duration(seconds: 4));
    _lastError = error;
    // 回答完成（思考结束且没有朗读）或朗读结束：开心一下。
    final finished = (_lastStatus == AssistantStatus.thinking && status == AssistantStatus.idle && !speaking) || (_wasSpeaking && !speaking);
    if (finished && lastReply != null) {
      if (lastReply.startsWith('出错了')) {
        _sadUntil = now.add(const Duration(seconds: 4));
      } else {
        _happyUntil = now.add(const Duration(milliseconds: 2500));
      }
      _lastActive = now;
    }
    if (status == AssistantStatus.thinking) _reply = '';
    if (speaking && lastReply != null) _reply = lastReply;
    _lastStatus = status;
    _wasSpeaking = speaking;

    if (status == AssistantStatus.listening) return (PetMood.listening, partial.isEmpty ? '我在听…' : partial);
    if (status == AssistantStatus.thinking) return (PetMood.thinking, '');
    if (speaking) return (PetMood.speaking, _short(_reply));
    if (_sadUntil != null && now.isBefore(_sadUntil!)) return (PetMood.sad, error != null ? _short(error) : '');
    if (_happyUntil != null && now.isBefore(_happyUntil!)) return (PetMood.happy, '');
    if (playing) return (PetMood.dancing, '');
    if (now.difference(_lastActive) > sleepAfter) return (PetMood.sleepy, '');
    return (PetMood.idle, '');
  }

  /// 有人点了桌宠：醒过来。
  void touch() => _lastActive = _now();

  static String _short(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'[*#`>_]'), '').trim();
    return t.length > 42 ? '${t.substring(0, 41)}…' : t;
  }
}

/// 主程序一侧的桌宠：把状态推给 Android 悬浮窗（见 PetOverlay.kt）或桌面端的置顶小窗口，
/// 并处理点按（开始 / 停止说话）。
class PetHost with WindowListener {
  PetHost._(this.settings, this.assistant, this.speech, this.player, this.voice);

  final AssistantSettings settings;
  final AssistantController assistant;
  final SpeechOutput? speech;
  final PlayerController player;
  final VoiceSettings voice;
  final _rules = PetMoodRules();

  static const _android = MethodChannel('yunyin/pet');
  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Timer? _tick;
  String _config = '';
  String _last = '';

  // 桌面端的桌宠窗口。
  WindowController? _window;
  Future<void>? _creating;
  bool _ready = false;
  static const _positionKey = 'deskPet.position';

  PetKind? get kind => PetKind.byName(settings.pet);

  static PetHost attach({required AssistantSettings settings, required AssistantController assistant, required SpeechOutput? speech, required PlayerController player, required VoiceSettings voice}) {
    final h = PetHost._(settings, assistant, speech, player, voice);
    settings.addListener(h._configure);
    assistant.addListener(h._push);
    speech?.addListener(h._push);
    player.addListener(h._push);
    if (_isAndroid) {
      _android.setMethodCallHandler(h._onCall);
    } else if (isDesktopPlatform) {
      petWindowChannel.setMethodCallHandler(h._onCall);
    }
    h._configure();
    return h;
  }

  /// Android：是否可以显示悬浮窗（桌宠与桌面歌词共用“显示在其他应用上层”权限）。
  static Future<bool> canDraw() async => !_isAndroid || (await const MethodChannel('yunyin/lyrics_overlay').invokeMethod<bool>('canDraw') ?? false);

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'tap':
        _rules.touch();
        await _onTap();
      case 'ready':
        _ready = true;
        _last = '';
        if (kind == null) unawaited(_window?.hide());
        return _state();
      case 'open':
        await windowManager.show();
        await windowManager.focus();
      case 'moved':
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_positionKey, jsonEncode(call.arguments));
    }
    _push();
    return null;
  }

  /// 点按桌宠：正在说话就停下；正在听就结束；否则开始听。
  Future<void> _onTap() async {
    if (speech?.speaking ?? false) {
      await speech!.stop();
      return;
    }
    await assistant.startListening();
  }

  void _configure() {
    final k = kind;
    final key = '${k?.name}|${settings.petSize}';
    if (key != _config) {
      _config = key;
      _last = '';
      // 刚打开（或换了）桌宠：从现在开始计算“多久没人理”，不要一出来就打瞌睡。
      _rules.touch();
      if (_isAndroid) {
        unawaited(_android.invokeMethod<void>('configure', {'enabled': k != null}).catchError((Object e) => debugPrint('pet: $e')));
      } else if (isDesktopPlatform) {
        unawaited(k == null ? _hideWindow() : _showWindow());
      }
      _tick?.cancel();
      // 开心、出错与打瞌睡按时间变化：开着桌宠时每秒检查一次。
      _tick = k == null ? null : Timer.periodic(const Duration(seconds: 1), (_) => _push());
    }
    _push();
  }

  Map<String, Object?> _state() {
    final last = assistant.messages.lastOrNull;
    final (mood, text) = _rules.compute(
      status: assistant.status,
      partial: assistant.partial,
      speaking: speech?.speaking ?? false,
      playing: player.playing,
      lastReply: last == null || last.fromUser ? null : last.text,
      error: assistant.voiceError,
    );
    return {'kind': kind?.name, 'mood': mood.name, 'text': text, 'height': settings.petHeight};
  }

  void _push() {
    if (kind == null) return;
    final state = _state();
    final key = jsonEncode(state);
    if (key == _last) return;
    _last = key;
    if (_isAndroid) {
      unawaited(_android.invokeMethod<void>('state', state).catchError((Object e) => debugPrint('pet: $e')));
    } else if (isDesktopPlatform && _ready) {
      unawaited(petWindowChannel.invokeMethod<void>('state', state).catchError((Object e) => debugPrint('pet: $e')));
    }
  }

  // ── 桌面端 ──────────────────────────────────────

  Future<void> _showWindow() async {
    if (_window == null) {
      final prefs = await SharedPreferences.getInstance();
      _creating ??= WindowController.create(
        WindowConfiguration(arguments: jsonEncode({'type': kPetWindowArgument, 'position': prefs.getString(_positionKey)})),
      ).then((w) {
        _window = w;
        windowManager.addListener(this);
        return windowManager.setPreventClose(true);
      });
      await _creating;
      return;
    }
    if (kind != null) await _window!.show();
  }

  Future<void> _hideWindow() async {
    await _creating;
    if (kind == null) await _window?.hide();
  }

  /// 关闭主窗口时先关掉桌宠窗口，否则它会让应用留在后台。
  @override
  void onWindowClose() async {
    try {
      await petWindowChannel.invokeMethod<void>('quit').timeout(const Duration(milliseconds: 500));
    } catch (_) {}
    await windowManager.destroy();
  }
}

/// 给定桌宠高度时窗口（或悬浮窗）需要的大小：桌宠画布，加上有气泡时头顶的气泡区域。
ui.Size petWindowSize(PetKind kind, double height, {required bool bubble}) {
  final c = PetPainter.canvasSize(kind, height);
  return ui.Size(c.width + 60, c.height + (bubble ? PetView.bubbleHeight : 0));
}
