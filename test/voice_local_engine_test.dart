import 'dart:io';
import 'dart:math' as math;
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

  test('五个音色各用一段不同的真人参考录音：24 kHz 录音棚录音、2.5–6 秒，能解码', () async {
    final ids = <String>{};
    for (final preset in VoicePresets.all) {
      final id = preset.binding('local')!.voices[VoiceLanguage.zh]!;
      ids.add(id);
      final m = LocalVoiceModels.byId(id)!;
      final (samples, rate) = decodeWav16((await rootBundle.load(m.prompt)).buffer.asUint8List());
      expect(rate, 24000, reason: preset.name);
      expect(samples.length / rate, inInclusiveRange(2.5, 6), reason: preset.name);
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

  test('采样步数随设备速度调整：慢了减一步，快了加一步，在 3–4 步之间', () {
    expect(zipVoiceSteps(4, 0.9), 3);
    expect(zipVoiceSteps(3, 1.5), 3);
    expect(zipVoiceSteps(3, 0.5), 3);
    expect(zipVoiceSteps(3, 0.2), 4);
    expect(zipVoiceSteps(4, 0.1), 4);
  });

  test('合成语音的后期处理：句首句尾淡入淡出，停顿里的底噪压低，说话部分不变', () {
    const sr = 24000;
    // 0.3 秒 0.5 振幅的声音（从非零处开始），接 0.3 秒 -60 dB 的底噪，再接 0.3 秒声音。
    final x = Float32List(sr * 9 ~/ 10);
    for (var i = 0; i < x.length; i++) {
      final loud = i < sr * 3 ~/ 10 || i >= sr * 6 ~/ 10;
      x[i] = loud ? 0.5 * math.sin(i * 0.07 + 1) : 0.0005 * (i.isEven ? 1 : -1);
    }
    final y = cleanSpeech(x, sr);
    expect(y.first.abs(), lessThan(0.01), reason: '句首淡入');
    expect(y.last.abs(), lessThan(0.01), reason: '句尾淡出');
    double rms(Float32List v, int from, int to) => math.sqrt(v.sublist(from, to).fold<double>(0, (a, b) => a + b * b) / (to - from));
    expect(rms(y, sr * 4 ~/ 10, sr * 5 ~/ 10), lessThan(rms(x, sr * 4 ~/ 10, sr * 5 ~/ 10) * 0.2), reason: '停顿底噪压低');
    expect(rms(y, sr ~/ 10, sr * 2 ~/ 10), closeTo(rms(x, sr ~/ 10, sr * 2 ~/ 10), 1e-6), reason: '说话部分不变');
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
