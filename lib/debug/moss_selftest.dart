// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../voice/engines/moss_engine.dart';
import '../voice/moss/moss_models.dart';
import '../voice/tts_types.dart';
import '../voice/wav.dart';

/// 本机语音的真机测试：adb shell am start -S -n com.marginalz.yunyin/.MainActivity --ez yunyin_moss_test true
///
/// 没有模型时先下载（日志里每 5% 报一次进度），然后用四个声音各合成几句话，记录用时、实时率、峰值与毛刺，
/// 音频保存到外部存储的 moss_test/ 目录（adb pull /sdcard/Android/data/com.marginalz.yunyin/files/moss_test）。
/// 结果以 “moss|” 开头写进日志。正常启动不会触发。
Future<void> maybeRunMossSelfTest() async {
  if (kIsWeb || !Platform.isAndroid) return;
  await Future<void>.delayed(const Duration(seconds: 2));
  try {
    final want = await const MethodChannel('yunyin/diagnostics').invokeMethod<bool>('mossTestRequested');
    if (want == true) await _run();
  } catch (e) {
    print('moss|测试出错：$e');
  }
}

Future<void> _run() async {
  print('moss|设备支持：${await MossModels.supported()}');
  if (!await MossModels.ready()) {
    print('moss|开始下载模型（${(MossModels.totalBytes / (1 << 20)).round()} MB）');
    var last = -1;
    final sw = Stopwatch()..start();
    await MossModels.download(onProgress: (p) {
      final pct = (p * 20).floor() * 5;
      if (pct != last) {
        last = pct;
        print('moss|下载 $pct%（${sw.elapsed.inSeconds} 秒）');
      }
    });
    print('moss|下载完成，用时 ${sw.elapsed.inSeconds} 秒');
  }
  final out = Directory('${(await getExternalStorageDirectory())!.path}/moss_test');
  out.createSync(recursive: true);
  const texts = [
    '你好，我是云音助手。今天想听点什么？',
    '好的，已经为你播放周杰伦的《晴天》，音量调到百分之三十五。',
    '现在是晚上十点二十分，明天的天气不错，适合出门走走。我给你挑了几首轻松的歌，希望你喜欢。',
  ];
  final engine = MossTtsEngine();
  for (final speaker in const ['Lingyu', 'Yuewen', 'Junhao', 'Zhiming']) {
    for (var i = 0; i < texts.length; i++) {
      final sw = Stopwatch()..start();
      try {
        final audio = await engine.synthesize(EngineVoice('moss', {VoiceLanguage.zh: speaker}), TtsRequest(texts[i], language: VoiceLanguage.zh)).toList();
        final ms = sw.elapsedMilliseconds;
        final bytes = audio.single.bytes;
        final (samples, rate) = decodeWav16(bytes);
        final seconds = samples.length / rate;
        var peak = 0.0, glitches = 0;
        for (var k = 0; k < samples.length; k++) {
          peak = samples[k].abs() > peak ? samples[k].abs() : peak;
          if (k > 0 && (samples[k] - samples[k - 1]).abs() > 0.35) glitches++;
        }
        File('${out.path}/$speaker-$i.wav').writeAsBytesSync(bytes);
        print('moss|$speaker 第${i + 1}句：音频 ${seconds.toStringAsFixed(1)} 秒，用时 ${(ms / 1000).toStringAsFixed(1)} 秒，'
            '实时率 ${(ms / 1000 / seconds).toStringAsFixed(2)}，峰值 ${peak.toStringAsFixed(2)}，毛刺 $glitches');
      } catch (e) {
        print('moss|$speaker 第${i + 1}句失败：$e');
      }
    }
  }
  print('moss|===== 结束 =====');
}
