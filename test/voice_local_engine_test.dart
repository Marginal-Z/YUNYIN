import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/voice/engines/local_engine.dart';
import 'package:yunyin/voice/pitch.dart';
import 'package:yunyin/voice/tts_types.dart';
import 'package:yunyin/voice/voice_library.dart';
import 'package:yunyin/voice/wav.dart';

/// 合成测试需要已下载的 ZipVoice 模型与 sherpa-onnx 动态库，默认跳过：
/// `YUNYIN_VOICE_ROOT=声音模型目录 SHERPA_LIB=动态库目录 flutter test test/voice_local_engine_test.dart`
/// （目录里放 sherpa-onnx-zipvoice-distill-int8-zh-en-emilia/ 与 vocos_24khz.onnx，模型目录下要有 .ok 文件）
final _root = Platform.environment['YUNYIN_VOICE_ROOT'];
final _lib = Platform.environment['SHERPA_LIB'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('五个音色各用一段不同的真人参考录音：16 kHz、3–6 秒，能解码', () async {
    final ids = <String>{};
    for (final preset in VoicePresets.all) {
      final id = preset.binding('local')!.voices[VoiceLanguage.zh]!;
      ids.add(id);
      final m = LocalVoiceModels.byId(id)!;
      final (samples, rate) = decodeWav16((await rootBundle.load(m.prompt)).buffer.asUint8List());
      expect(rate, 16000, reason: preset.name);
      expect(samples.length / rate, inInclusiveRange(3, 6), reason: preset.name);
      expect(m.promptText, isNotEmpty);
    }
    expect(ids.length, VoicePresets.all.length);
  });

  test('WAV 编解码往返', () {
    final x = Float32List.fromList([0, 0.5, -0.5, 0.25]);
    final (y, rate) = decodeWav16(encodeWav(x, 24000));
    expect(rate, 24000);
    for (var i = 0; i < x.length; i++) {
      expect(y[i], closeTo(x[i], 1 / 16000));
    }
  });

  test('采样步数随设备速度调整：慢了减一步，快了加一步，在 2–4 步之间', () {
    expect(zipVoiceSteps(4, 0.9), 3);
    expect(zipVoiceSteps(2, 1.5), 2);
    expect(zipVoiceSteps(3, 0.5), 3);
    expect(zipVoiceSteps(3, 0.2), 4);
    expect(zipVoiceSteps(4, 0.1), 4);
  });

  test('本地引擎：在后台 isolate 中按参考录音合成，女声与男声音高分得开', () async {
    final engine = LocalTtsEngine(libraryDir: _lib, rootOverride: _root);
    for (final voice in VoicePresets.all) {
      final b = voice.binding('local')!;
      expect(await engine.ready(b, VoiceLanguage.zh), isTrue, reason: voice.name);
      final audio = await engine.synthesize(b, const TtsRequest('你好，我是云音助手，今天想听点什么？', language: VoiceLanguage.zh, prosody: Prosody(emotion: Emotion.happy))).toList();
      final wav = audio.single.bytes;
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      final f0 = medianPitch(wav)!;
      // ignore: avoid_print
      print('${voice.name} ${wav.length} bytes ${f0.toStringAsFixed(0)} Hz');
      if (voice.traits.contains('女声')) {
        expect(f0, greaterThan(190), reason: voice.name);
      } else {
        expect(f0, lessThan(190), reason: voice.name);
      }
    }
    engine.dispose();
  }, skip: _root == null || _lib == null ? '需要声音模型（见文件开头说明）' : null, timeout: const Timeout(Duration(minutes: 3)));
}
