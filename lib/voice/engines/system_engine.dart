import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pitch.dart';
import '../tts_types.dart';

/// 系统朗读：所有引擎都不可用时的最后降级。不区分具体音色，但 Android 上会按音色的性别选择系统里的
/// 男声或女声（见 [_voiceFor]）。合成为 WAV 文件后与其他引擎一样进入播放队列，可以被打断。
class SystemTtsEngine extends TtsEngine {
  static const _channel = MethodChannel('yunyin/voice');

  @override
  String get id => 'system';

  @override
  String get name => '系统朗读';

  @override
  bool get offline => true;

  @override
  bool get configured => true;

  @override
  Set<VoiceLanguage> get languages => VoiceLanguage.values.toSet();

  @override
  Future<bool> ready(EngineVoice voice, VoiceLanguage lang) async => !kIsWeb;

  @override
  Stream<TtsAudio> synthesize(EngineVoice voice, TtsRequest request, {CancelToken? cancel}) async* {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/yunyin_sys_${DateTime.now().microsecondsSinceEpoch}.wav';
    final rate = request.prosody.rate;
    final lang = request.language;
    try {
      if (Platform.isAndroid) {
        final gender = voice.voices[lang];
        final systemVoice = gender == null ? null : await _voiceFor(gender);
        final ok = await _channel.invokeMethod<bool>('synthesize', {'text': request.text, 'path': path, 'rate': rate, 'lang': lang.name, 'voice': systemVoice});
        if (ok != true) throw TtsException('系统朗读不可用（请在系统设置中安装中文语音包）', engine: name);
      } else if (Platform.isMacOS) {
        await _run('say', ['-v', 'Tingting', '-r', '${(180 * rate).round()}', '-o', path, '--file-format=WAVE', '--data-format=LEI16@22050', request.text]);
      } else if (Platform.isWindows) {
        final escaped = request.text.replaceAll("'", "''");
        final r = ((rate - 1) * 10).round().clamp(-10, 10);
        await _run('powershell', [
          '-NoProfile',
          '-Command',
          "Add-Type -AssemblyName System.Speech; \$s=New-Object System.Speech.Synthesis.SpeechSynthesizer; \$s.Rate=$r; \$s.SetOutputToWaveFile('$path'); \$s.Speak('$escaped'); \$s.Dispose()",
        ]);
      } else if (Platform.isLinux) {
        await _run('espeak-ng', ['-v', 'cmn', '-s', '${(170 * rate).round()}', '-w', path, request.text]);
      }
      final f = File(path);
      if (!f.existsSync() || f.lengthSync() < 100) throw TtsException('系统朗读没有生成音频', engine: name);
      final bytes = await f.readAsBytes();
      f.deleteSync();
      yield TtsAudio(bytes, format: 'wav');
    } on TtsException {
      rethrow;
    } catch (e) {
      throw TtsException('系统朗读不可用（$e）', engine: name);
    }
  }

  static Future<void> _run(String exe, List<String> args) async {
    final r = await Process.run(exe, args);
    if (r.exitCode != 0) throw TtsException('${r.stderr}'.trim(), engine: '系统朗读');
  }

  /// 系统里各个中文声音的音高（Hz），每次启动只测一次；声音列表没变时用上次的结果。
  static Future<Map<String, double>>? _pitches;

  /// 女声音色用音高最高、男声音色用音高最低的系统声音（以 165 Hz 为界）；找不到合适的声音时用系统默认。
  static Future<String?> _voiceFor(String gender) async {
    final pitches = await (_pitches ??= _measure());
    if (pitches.isEmpty) return null;
    final sorted = pitches.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    if (gender == 'female') return sorted.last.value >= 165 ? sorted.last.key : null;
    return sorted.first.value < 165 ? sorted.first.key : null;
  }

  static Future<Map<String, double>> _measure() async {
    try {
      final names = (await _channel.invokeListMethod<String>('systemVoices')) ?? const [];
      if (names.isEmpty) return const {};
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(_prefsKey) ?? '{}') as Map<String, dynamic>;
      if (listEquals((saved['names'] as List?)?.cast<String>(), names)) {
        return {for (final e in (saved['pitch'] as Map).entries) '${e.key}': (e.value as num).toDouble()};
      }
      final dir = await getTemporaryDirectory();
      final out = <String, double>{};
      for (final name in names) {
        final path = '${dir.path}/yunyin_probe_${name.hashCode}.wav';
        final ok = await _channel.invokeMethod<bool>('synthesize', {'text': '你好，我是云音助手，很高兴认识你。', 'path': path, 'rate': 1.0, 'lang': 'zh', 'voice': name});
        final f = File(path);
        if (ok == true && f.existsSync()) {
          final pitch = medianPitch(await f.readAsBytes());
          if (pitch != null) out[name] = pitch;
          f.deleteSync();
        }
      }
      debugPrint('system voices: $out');
      await prefs.setString(_prefsKey, jsonEncode({'names': names, 'pitch': out}));
      return out;
    } catch (e) {
      debugPrint('system voices: $e');
      return const {};
    }
  }

  static const _prefsKey = 'voice.systemPitch';
}
