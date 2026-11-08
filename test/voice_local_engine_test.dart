import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/voice/engines/local_engine.dart';
import 'package:yunyin/voice/tts_types.dart';
import 'package:yunyin/voice/voice_library.dart';

/// 需要已下载的声音模型与 sherpa-onnx 动态库，默认跳过：
/// `YUNYIN_VOICE_ROOT=声音模型目录 SHERPA_LIB=动态库目录 flutter test test/voice_local_engine_test.dart`
final _root = Platform.environment['YUNYIN_VOICE_ROOT'];
final _lib = Platform.environment['SHERPA_LIB'];

void main() {
  test('本地引擎：按目录中的文件组装配置，在后台 isolate 中合成出 WAV（词典、espeak 数据与 jieba 词典三种模型）', () async {
    final engine = LocalTtsEngine(libraryDir: _lib, rootOverride: _root);
    for (final (voice, id) in [
      (VoicePresets.xiaoyou, LocalVoiceIds.xiaoya),
      (VoicePresets.yunxi, LocalVoiceIds.huayan),
      (VoicePresets.muyan, LocalVoiceIds.laozhe),
    ]) {
      final b = voice.binding('local')!;
      expect(b.voices[VoiceLanguage.zh], id);
      expect(await engine.ready(b, VoiceLanguage.zh), isTrue, reason: id);
      final sw = Stopwatch()..start();
      final audio = await engine.synthesize(b, const TtsRequest('你好，我是云音助手，今天想听点什么？', language: VoiceLanguage.zh, prosody: Prosody(emotion: Emotion.happy))).toList();
      // ignore: avoid_print
      print('$id ${sw.elapsedMilliseconds}ms ${audio.single.bytes.length} bytes');
      expect(String.fromCharCodes(audio.single.bytes.sublist(0, 4)), 'RIFF');
      expect(audio.single.bytes.length, greaterThan(20000));
    }
    engine.dispose();
  }, skip: _root == null || _lib == null ? '需要声音模型（见文件开头说明）' : null, timeout: const Timeout(Duration(minutes: 3)));
}
