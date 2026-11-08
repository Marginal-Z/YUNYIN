import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:yunyin/assistant/voice_engine.dart';

/// 需要下载好的模型与 sherpa-onnx 动态库，默认跳过：
/// `YUNYIN_VOICE_MODELS=模型目录（含 kws 与 asr） SHERPA_LIB=动态库目录 flutter test test/voice_engine_test.dart`
final _models = Platform.environment['YUNYIN_VOICE_MODELS'];
final _lib = Platform.environment['SHERPA_LIB'];

Float32List _wav(String path) {
  final b = File(path).readAsBytesSync();
  final d = ByteData.sublistView(b);
  var pos = 12;
  while (pos + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(pos, pos + 4));
    final size = d.getUint32(pos + 4, Endian.little);
    if (id == 'data') return VoiceRecognizer.pcm16ToFloat(Uint8List.sublistView(b, pos + 8, pos + 8 + size));
    pos += 8 + size;
  }
  throw StateError('no data');
}

/// 按 100ms 一段送入，模拟麦克风。
List<VoiceEvent> _feed(VoiceRecognizer r, Float32List s) {
  final events = <VoiceEvent>[];
  for (var i = 0; i < s.length; i += 1600) {
    events.addAll(r.accept(Float32List.sublistView(s, i, (i + 1600).clamp(0, s.length))));
  }
  // 末尾补 1.5 秒静音，让端点检测结束这句话。
  events.addAll(r.accept(Float32List(24000)));
  return events;
}

void main() {
  final skip = _models == null || _lib == null ? '需要语音模型（见文件开头说明）' : null;

  test('唤醒词检测后自动开始识别；识别一句话后回到唤醒检测', () {
    sherpa.initBindings(_lib);
    final kws = Directory('$_models/kws').listSync().whereType<Directory>().first.path;
    final asr = Directory('$_models/asr').listSync().whereType<Directory>().first.path;
    final paths = VoiceModelPaths(kwsDir: kws, asrDir: asr);
    // 模型自带的测试音频中的关键词。
    final words = File('$kws/test_wavs/test_keywords.txt').readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
    final r = VoiceRecognizer(paths, wakeWords: words);
    var wakes = 0;
    for (final f in Directory('$kws/test_wavs').listSync().whereType<File>().where((f) => f.path.endsWith('.wav'))) {
      final events = _feed(r, _wav(f.path));
      final w = events.whereType<VoiceWake>().map((e) => e.word).toList();
      // ignore: avoid_print
      print('${f.path.split('/').last}: wake=$w final=${events.whereType<VoiceFinal>().map((e) => e.text).toList()}');
      wakes += w.length;
      r.cancel();
    }
    expect(wakes, greaterThan(0));

    // 手动开始识别：模型自带的测试句子能识别出文字。
    for (final f in Directory('$asr/test_wavs').listSync().whereType<File>().where((f) => f.path.endsWith('0.wav') || f.path.endsWith('1.wav'))) {
      r.listen();
      final events = _feed(r, _wav(f.path));
      final text = events.whereType<VoiceFinal>().map((e) => e.text).join();
      // ignore: avoid_print
      print('${f.path.split('/').last}: $text');
      expect(text, isNotEmpty);
      expect(r.listening, isFalse);
    }
    r.free();
  }, skip: skip);
}
