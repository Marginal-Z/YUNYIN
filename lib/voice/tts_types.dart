import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 语音支持的语言。
enum VoiceLanguage {
  zh('中文'),
  en('English'),
  th('ไทย');

  const VoiceLanguage(this.label);
  final String label;

  /// 按文字内容判断语言：含泰文字母为泰语，含汉字为中文，否则英语。
  static VoiceLanguage detect(String text) {
    if (RegExp(r'[฀-๿]').hasMatch(text)) return th;
    if (RegExp(r'[一-鿿]').hasMatch(text)) return zh;
    return en;
  }
}

/// 情绪。只调整语气、语速与停顿，音色（声音模型 / 供应商音色 ID）始终不变。
enum Emotion { neutral, happy, excited, gentle, calm, sad, serious }

/// 一次合成的韵律：语速、情绪（强度 0–1）与句间停顿。各引擎的适配层把它换算成引擎支持的参数，不支持的忽略。
class Prosody {
  const Prosody({this.rate = 1, this.emotion = Emotion.neutral, this.intensity = 0.5, this.pauseMs = 220});

  /// 语速倍数（0.6–1.6）。
  final double rate;
  final Emotion emotion;
  final double intensity;

  /// 这一句之后的停顿（毫秒）。
  final int pauseMs;

  static const neutral = Prosody();

  Prosody copyWith({double? rate, Emotion? emotion, double? intensity, int? pauseMs}) =>
      Prosody(rate: rate ?? this.rate, emotion: emotion ?? this.emotion, intensity: intensity ?? this.intensity, pauseMs: pauseMs ?? this.pauseMs);
}

/// 一次合成请求（通常是一句话）。
class TtsRequest {
  const TtsRequest(this.text, {required this.language, this.prosody = Prosody.neutral});

  final String text;
  final VoiceLanguage language;
  final Prosody prosody;
}

/// 合成出的一段音频。[format] 为 wav / mp3 / pcm16（pcm16 为单声道 16 位小端）。
class TtsAudio {
  const TtsAudio(this.bytes, {required this.format, this.sampleRate = 0});

  final Uint8List bytes;
  final String format;
  final int sampleRate;
}

/// 一个音色在某个引擎上的配置：各语言对应的声音模型或供应商音色 ID，以及引擎的模型名称。
class EngineVoice {
  const EngineVoice(this.engine, this.voices, {this.model, this.note});

  /// 引擎标识（见 [TtsEngine.id]）。
  final String engine;

  /// 语言 → 声音模型 / 音色 ID。没有的语言表示这个音色在该引擎上不支持这种语言。
  final Map<VoiceLanguage, String> voices;

  /// 引擎的合成模型（例如 cosyvoice-v2、eleven_multilingual_v2、s1）。
  final String? model;

  /// 说明（例如“泰语离线只有一个声音”）。
  final String? note;

  EngineVoice withVoice(VoiceLanguage lang, String id) => EngineVoice(engine, {...voices, lang: id}, model: model, note: note);
}

/// 合成失败（附带原因，供降级与提示使用）。
class TtsException implements Exception {
  TtsException(this.message, {this.engine, this.retryable = true});

  final String message;
  final String? engine;

  /// 网络等临时问题可以换引擎或稍后重试；密钥错误、不支持的语言则不重试这个引擎。
  final bool retryable;

  @override
  String toString() => engine == null ? message : '$engine：$message';
}

/// 语音合成引擎的统一接口。新增引擎只需实现这个接口并在 [VoiceEngines] 中注册。
abstract class TtsEngine {
  /// 唯一标识（local / system / cosyvoice / fish / elevenlabs）。
  String get id;

  String get name;

  /// 是否在本机离线运行。
  bool get offline;

  /// 是否已配置（云端引擎需要密钥或自建代理地址；本地引擎始终为 true）。
  bool get configured;

  /// 引擎能说的语言（不同音色可能更少，见 [EngineVoice.voices]）。
  Set<VoiceLanguage> get languages;

  /// 这个音色能否立即用于这种语言（本地引擎还要求声音模型已经下载）。
  Future<bool> ready(EngineVoice voice, VoiceLanguage lang);

  /// 准备音色（本地引擎下载声音模型；云端引擎无需准备）。
  Future<void> prepare(EngineVoice voice, VoiceLanguage lang, {void Function(double progress)? onProgress, CancelToken? cancel}) async {}

  /// 合成一句话。返回的流可以分多段输出（流式合成），每段可以单独播放。
  Stream<TtsAudio> synthesize(EngineVoice voice, TtsRequest request, {CancelToken? cancel});
}
