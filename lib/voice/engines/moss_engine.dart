import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../moss/moss_models.dart';
import '../moss/moss_text.dart';
import '../moss/sentencepiece.dart';
import '../tts_types.dart';

/// 本机语音：MOSS-TTS-Nano（OpenMOSS，Apache-2.0）在手机 CPU 上离线合成，48 kHz。
/// 分词与文字整理在 Dart 端，推理在原生端（android/.../MossTts.kt，ONNX Runtime）。
/// 模型没有下载时不可用，助手自动用系统朗读。
class MossTtsEngine extends TtsEngine {
  static const _channel = MethodChannel('yunyin/moss');

  @override
  String get id => 'moss';

  @override
  String get name => '本机语音';

  @override
  bool get offline => true;

  @override
  bool get configured => true;

  @override
  Set<VoiceLanguage> get languages => const {VoiceLanguage.zh};

  @override
  Future<bool> ready(EngineVoice voice, VoiceLanguage lang) async =>
      !kIsWeb && Platform.isAndroid && voice.voices[lang] != null && await MossModels.ready();

  static SentencePieceBpe? _tokenizer;

  static Future<SentencePieceBpe> _tok() async {
    final t = _tokenizer;
    if (t != null) return t;
    final path = '${await MossModels.dir()}/${MossModels.tts}/tokenizer.model';
    final bytes = await File(path).readAsBytes();
    final tok = await compute(SentencePieceBpe.fromBytes, bytes);
    _tokenizer = tok;
    return tok;
  }

  /// 这句话最多生成的帧数（12.5 帧 / 秒）：按字数估计时长再留出余量，避免模型偶尔不停时一直生成下去。
  static int maxFrames(String text) {
    final chars = text.replaceAll(RegExp(r'\s'), '').length;
    final seconds = chars * 0.3 + 2;
    return (seconds * 12.5 * 1.5).round().clamp(30, 375);
  }

  @override
  Stream<TtsAudio> synthesize(EngineVoice voice, TtsRequest request, {CancelToken? cancel}) async* {
    final speaker = voice.voices[request.language];
    if (speaker == null) throw TtsException('这个声音不支持${request.language.label}', engine: name, retryable: false);
    final text = mossText(request.text);
    if (text.isEmpty) return;
    final ids = (await _tok()).encode(text);
    final path = '${(await getTemporaryDirectory()).path}/yunyin_moss_${DateTime.now().microsecondsSinceEpoch}.wav';
    cancel?.whenCancel.then((_) => _channel.invokeMethod<void>('cancel').catchError((_) {}));
    final Map<String, Object?>? r;
    try {
      r = await _channel.invokeMapMethod<String, Object?>('synthesize', {
        'dir': await MossModels.dir(),
        'ids': Int32List.fromList(ids),
        'voice': speaker,
        'path': path,
        'maxFrames': maxFrames(text),
        'seed': text.hashCode & 0x7fffffff,
      });
    } on PlatformException catch (e) {
      throw TtsException('本机语音不可用（${e.message}）', engine: name);
    }
    if (cancel?.isCancelled ?? false) return;
    if (r?['ok'] != true) {
      if (r?['cancelled'] == true) return;
      throw TtsException('本机语音合成失败（${r?['error'] ?? '未知原因'}）', engine: name);
    }
    debugPrint('moss: ${ids.length} 个字词 → ${r!['frames']} 帧，音频 ${r['durationMs']} ms，用时 ${r['elapsedMs']} ms，峰值 ${r['peak']}');
    final f = File(path);
    final bytes = await f.readAsBytes();
    f.deleteSync();
    yield TtsAudio(bytes, format: 'wav');
  }
}
