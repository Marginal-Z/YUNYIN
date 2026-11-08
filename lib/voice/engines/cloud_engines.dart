import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../tts_types.dart';
import '../voice_settings.dart';

/// 云端引擎的公共部分：读取用户配置的密钥 / 自建代理，没有配置时不可用。
abstract class CloudTtsEngine extends TtsEngine {
  CloudTtsEngine(this.settings, {Dio? dio})
    : dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 30)));

  final VoiceSettings settings;
  final Dio dio;

  EngineConfig get config => settings.engine(id);

  @override
  bool get offline => false;

  @override
  bool get configured => config.usable;

  @override
  Future<bool> ready(EngineVoice voice, VoiceLanguage lang) async => configured && (voice.voices[lang]?.isNotEmpty ?? false) && languages.contains(lang);

  /// 官方接口地址或用户的自建代理地址。
  String base(String official) => config.proxy.trim().isEmpty ? official : config.proxy.trim().replaceFirst(RegExp(r'/+$'), '');

  String model(EngineVoice voice, String fallback) => config.model.trim().isNotEmpty ? config.model.trim() : (voice.model ?? fallback);

  String voiceId(EngineVoice voice, VoiceLanguage lang) {
    final v = voice.voices[lang];
    if (v == null || v.isEmpty) throw TtsException('这个音色在$name上没有${lang.label}声音', engine: name, retryable: false);
    return v;
  }

  /// HTTP 错误转为可读的原因；密钥与参数问题不再重试这个引擎。
  TtsException httpError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final detail = body is List<int> ? utf8.decode(body, allowMalformed: true) : '${body ?? e.message ?? e.type.name}';
      final short = detail.length > 160 ? detail.substring(0, 160) : detail;
      return switch (code) {
        401 || 403 => TtsException('密钥无效或没有权限（$short）', engine: name, retryable: false),
        400 || 404 || 422 => TtsException('音色或参数不被接受（$short）', engine: name, retryable: false),
        402 || 429 => TtsException('额度不足或请求太频繁（$short）', engine: name),
        _ => TtsException('请求失败（${code ?? e.type.name}）', engine: name),
      };
    }
    return e is TtsException ? e : TtsException('$e', engine: name);
  }
}

/// ElevenLabs：官方预置音色或用户自己的音色 ID，流式接口边生成边返回 MP3。
///
/// 情绪通过 voice_settings 体现：情绪越强，stability 越低、style 越高（表现力更强），音色 ID 不变。
class ElevenLabsEngine extends CloudTtsEngine {
  ElevenLabsEngine(super.settings, {super.dio});

  @override
  String get id => 'elevenlabs';

  @override
  String get name => 'ElevenLabs';

  @override
  Set<VoiceLanguage> get languages => VoiceLanguage.values.toSet();

  /// 多语言 v2 支持中文与英语；泰语使用 v3 模型（eleven_v3）。
  static String modelFor(VoiceLanguage lang, String configured) => lang == VoiceLanguage.th ? 'eleven_v3' : configured;

  /// 把韵律换算为 ElevenLabs 的 voice_settings（各值都在接口允许的范围内）。
  @visibleForTesting
  static Map<String, Object> voiceSettings(Prosody p) {
    final expressive = switch (p.emotion) {
      Emotion.excited || Emotion.happy => 0.35 + 0.35 * p.intensity,
      Emotion.sad || Emotion.serious => 0.2 + 0.25 * p.intensity,
      Emotion.calm || Emotion.gentle => 0.1 + 0.1 * p.intensity,
      Emotion.neutral => 0.1,
    };
    return {
      'stability': (0.6 - expressive * 0.45).clamp(0.2, 0.85),
      'similarity_boost': 0.8,
      'style': expressive.clamp(0.0, 0.8),
      'use_speaker_boost': true,
      'speed': p.rate.clamp(0.7, 1.2),
    };
  }

  @override
  Stream<TtsAudio> synthesize(EngineVoice voice, TtsRequest request, {CancelToken? cancel}) async* {
    final vid = voiceId(voice, request.language);
    final Response<ResponseBody> res;
    try {
      res = await dio.post<ResponseBody>(
        '${base('https://api.elevenlabs.io')}/v1/text-to-speech/$vid/stream',
        queryParameters: {'output_format': 'mp3_44100_128'},
        data: jsonEncode({
          'text': request.text,
          'model_id': modelFor(request.language, model(voice, 'eleven_multilingual_v2')),
          'voice_settings': voiceSettings(request.prosody),
        }),
        options: Options(
          responseType: ResponseType.stream,
          contentType: 'application/json',
          headers: {if (config.apiKey.isNotEmpty) 'xi-api-key': config.apiKey, 'accept': 'audio/mpeg'},
        ),
        cancelToken: cancel,
      );
    } catch (e) {
      throw httpError(e);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in res.data!.stream) {
      bytes.add(chunk);
    }
    if (bytes.isEmpty) throw TtsException('没有返回音频', engine: name);
    yield TtsAudio(bytes.takeBytes(), format: 'mp3');
  }
}

/// Fish Audio：声音由 reference_id 指定（在 Fish Audio 选择或克隆的声音），流式返回 MP3。
///
/// s1 模型支持在文本前加情绪标记（例如 “(happy)”），适配层按情绪添加；其他模型不加。
class FishAudioEngine extends CloudTtsEngine {
  FishAudioEngine(super.settings, {super.dio});

  @override
  String get id => 'fish';

  @override
  String get name => 'Fish Audio';

  @override
  Set<VoiceLanguage> get languages => {VoiceLanguage.zh, VoiceLanguage.en};

  @visibleForTesting
  static String withEmotion(String text, Prosody p, String model) {
    if (!model.startsWith('s1') || p.emotion == Emotion.neutral || p.intensity < 0.3) return text;
    final tag = switch (p.emotion) {
      Emotion.happy => 'happy',
      Emotion.excited => 'excited',
      Emotion.gentle || Emotion.calm => 'relaxed',
      Emotion.sad => 'sad',
      Emotion.serious => 'serious',
      Emotion.neutral => '',
    };
    return '($tag) $text';
  }

  @override
  Stream<TtsAudio> synthesize(EngineVoice voice, TtsRequest request, {CancelToken? cancel}) async* {
    final ref = voiceId(voice, request.language);
    final m = model(voice, 's1');
    final Response<ResponseBody> res;
    try {
      res = await dio.post<ResponseBody>(
        '${base('https://api.fish.audio')}/v1/tts',
        data: jsonEncode({
          'text': withEmotion(request.text, request.prosody, m),
          'reference_id': ref,
          'format': 'mp3',
          'mp3_bitrate': 128,
          'latency': 'balanced',
          'prosody': {'speed': request.prosody.rate.clamp(0.5, 2.0), 'volume': 0},
        }),
        options: Options(
          responseType: ResponseType.stream,
          contentType: 'application/json',
          headers: {if (config.apiKey.isNotEmpty) 'Authorization': 'Bearer ${config.apiKey}', 'model': m},
        ),
        cancelToken: cancel,
      );
    } catch (e) {
      throw httpError(e);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in res.data!.stream) {
      bytes.add(chunk);
    }
    if (bytes.isEmpty) throw TtsException('没有返回音频', engine: name);
    yield TtsAudio(bytes.takeBytes(), format: 'mp3');
  }
}

/// CosyVoice（阿里云百炼 DashScope）：WebSocket 流式合成，音频以二进制帧边生成边返回（PCM 22.05kHz）。
///
/// 协议：发送 run-task（模型、音色、格式、语速），收到 task-started 后发送 continue-task（文本）与 finish-task，
/// 期间收到的二进制帧即音频，task-finished 结束，task-failed 为错误。语速 rate 0.5–2；情绪通过语速体现
/// （cosyvoice-v2 的系统音色不支持情绪参数，适配层不发送）。
class CosyVoiceEngine extends CloudTtsEngine {
  CosyVoiceEngine(super.settings, {super.dio, this.connect});

  /// 测试用：替换 WebSocket 连接。
  final Future<WebSocket> Function(String url, Map<String, String> headers)? connect;

  @override
  String get id => 'cosyvoice';

  @override
  String get name => 'CosyVoice';

  @override
  Set<VoiceLanguage> get languages => {VoiceLanguage.zh, VoiceLanguage.en};

  static const sampleRate = 22050;

  @visibleForTesting
  static double rateFor(Prosody p) {
    final e = switch (p.emotion) {
      Emotion.excited => 1 + 0.1 * p.intensity,
      Emotion.happy => 1 + 0.05 * p.intensity,
      Emotion.calm || Emotion.gentle || Emotion.sad => 1 - 0.08 * p.intensity,
      _ => 1.0,
    };
    return (p.rate * e).clamp(0.5, 2.0);
  }

  @override
  Stream<TtsAudio> synthesize(EngineVoice voice, TtsRequest request, {CancelToken? cancel}) async* {
    final v = voiceId(voice, request.language);
    final url = config.proxy.trim().isEmpty ? 'wss://dashscope.aliyuncs.com/api-ws/v1/inference' : config.proxy.trim();
    final headers = {if (config.apiKey.isNotEmpty) 'Authorization': 'bearer ${config.apiKey}', 'X-DashScope-DataInspection': 'enable'};
    WebSocket ws;
    try {
      ws = await (connect ?? (u, h) => WebSocket.connect(u, headers: h))(url, headers).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw TtsException('连接不到 CosyVoice（$e）', engine: name);
    }
    final task = '${DateTime.now().microsecondsSinceEpoch}${math.Random().nextInt(1 << 30)}';
    Map<String, Object> header(String action) => {'action': action, 'task_id': task, 'streaming': 'duplex'};
    // 收到的 PCM 每满约 0.4 秒就交出一段，第一段音频不必等整句合成完。
    const chunk = sampleRate * 2 * 2 ~/ 5;
    final out = StreamController<TtsAudio>();
    var pending = BytesBuilder(copy: false);
    var received = 0;
    void flush({bool force = false}) {
      if (pending.length < chunk && !(force && pending.isNotEmpty)) return;
      final bytes = pending.takeBytes();
      // 16 位采样按偶数字节切分，余下的一个字节留到下一段。
      final even = bytes.length & ~1;
      out.add(TtsAudio(Uint8List.sublistView(bytes, 0, even), format: 'pcm16', sampleRate: sampleRate));
      pending = BytesBuilder(copy: false);
      if (even < bytes.length) pending.add(bytes.sublist(even));
    }

    void fail(TtsException e) {
      if (out.isClosed) return;
      out.addError(e);
      out.close();
    }

    cancel?.whenCancel.then((_) {
      ws.close();
      if (!out.isClosed) out.close();
    });
    ws.listen(
      (m) {
        if (out.isClosed) return;
        if (m is List<int>) {
          received += m.length;
          pending.add(m);
          flush();
          return;
        }
        final event = ((jsonDecode('$m') as Map)['header'] as Map? ?? const {});
        switch (event['event']) {
          case 'task-started':
            ws.add(jsonEncode({'header': header('continue-task'), 'payload': {'input': {'text': request.text}}}));
            ws.add(jsonEncode({'header': header('finish-task'), 'payload': {'input': {}}}));
          case 'task-finished':
            flush(force: true);
            if (received == 0) {
              fail(TtsException('没有返回音频', engine: name));
            } else {
              out.close();
            }
            ws.close();
          case 'task-failed':
            final code = '${event['error_code'] ?? ''}';
            fail(TtsException('${event['error_message'] ?? '合成失败'}（$code）', engine: name, retryable: !code.contains('Invalid')));
            ws.close();
        }
      },
      onError: (Object e) => fail(TtsException('$e', engine: name)),
      onDone: () => fail(TtsException('连接已断开', engine: name)),
    );
    ws.add(
      jsonEncode({
        'header': header('run-task'),
        'payload': {
          'task_group': 'audio',
          'task': 'tts',
          'function': 'SpeechSynthesizer',
          'model': model(voice, 'cosyvoice-v2'),
          'parameters': {'text_type': 'PlainText', 'voice': v, 'format': 'pcm', 'sample_rate': sampleRate, 'volume': 50, 'rate': rateFor(request.prosody), 'pitch': 1},
          'input': {},
        },
      }),
    );
    yield* out.stream.timeout(const Duration(seconds: 30), onTimeout: (sink) {
      ws.close();
      sink.addError(TtsException('合成超时', engine: name));
      sink.close();
    });
  }
}
