import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../tts_types.dart';

/// 系统朗读：所有引擎都不可用时的最后降级（声音由系统决定，不区分音色）。
/// 合成为 WAV 文件后与其他引擎一样进入播放队列，可以被打断。
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
        final ok = await _channel.invokeMethod<bool>('synthesize', {'text': request.text, 'path': path, 'rate': rate, 'lang': lang.name});
        if (ok != true) throw TtsException('系统朗读不可用（请在系统设置中安装中文语音包）', engine: name);
      } else if (Platform.isMacOS) {
        final voiceArg = switch (lang) {
          VoiceLanguage.zh => ['-v', 'Tingting'],
          VoiceLanguage.th => ['-v', 'Kanya'],
          VoiceLanguage.en => <String>[],
        };
        await _run('say', [...voiceArg, '-r', '${(180 * rate).round()}', '-o', path, '--file-format=WAVE', '--data-format=LEI16@22050', request.text]);
      } else if (Platform.isWindows) {
        final escaped = request.text.replaceAll("'", "''");
        final r = ((rate - 1) * 10).round().clamp(-10, 10);
        await _run('powershell', [
          '-NoProfile',
          '-Command',
          "Add-Type -AssemblyName System.Speech; \$s=New-Object System.Speech.Synthesis.SpeechSynthesizer; \$s.Rate=$r; \$s.SetOutputToWaveFile('$path'); \$s.Speak('$escaped'); \$s.Dispose()",
        ]);
      } else if (Platform.isLinux) {
        await _run('espeak-ng', ['-v', lang == VoiceLanguage.zh ? 'cmn' : (lang == VoiceLanguage.th ? 'th' : 'en'), '-s', '${(170 * rate).round()}', '-w', path, request.text]);
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
}
