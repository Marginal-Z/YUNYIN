import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 默认唤醒词：拼音按模型的声母、韵母切分（见唤醒模型的 tokens.txt），@ 后为显示名称。
const kWakeWords = [
  'n ǐ h ǎo y ún y īn @你好云音',
  'h āi y ún y īn @嗨云音',
  'y ún y īn y ún y īn @云音云音',
];

/// 语音识别模型：高精度（SenseVoice，中英粤日韩）或标准（Paraformer 小模型，中文）。
enum AsrModel {
  senseVoice('高精度', 227),
  paraformer('标准', 79);

  const AsrModel(this.label, this.sizeMb);
  final String label;
  final int sizeMb;
}

/// 离线语音模型所在的位置（下载并解压后的结构见 [VoiceModelStore]）。
class VoiceModelPaths {
  const VoiceModelPaths({required this.kwsDir, required this.asrDir, required this.vad, this.asr = AsrModel.senseVoice});

  final String kwsDir;
  final String asrDir;
  final String vad;
  final AsrModel asr;

  String get kwsEncoder => '$kwsDir/encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  String get kwsDecoder => '$kwsDir/decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  String get kwsJoiner => '$kwsDir/joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  String get kwsTokens => '$kwsDir/tokens.txt';
  String get asrModel => '$asrDir/model.int8.onnx';
  String get asrTokens => '$asrDir/tokens.txt';
}

/// 语音识别过程中的事件。
sealed class VoiceEvent {
  const VoiceEvent();
}

/// 听到了唤醒词。
class VoiceWake extends VoiceEvent {
  const VoiceWake(this.word);
  final String word;
}

/// 正在说的话（识别中间结果）。
class VoicePartial extends VoiceEvent {
  const VoicePartial(this.text);
  final String text;
}

/// 一句话说完了（为空表示没听清或超时）。
class VoiceFinal extends VoiceEvent {
  const VoiceFinal(this.text);
  final String text;
}

/// 助手说话时用户开口了（打断）：随后进入识别。
class VoiceBargeIn extends VoiceEvent {
  const VoiceBargeIn();
}

/// 识别引擎出错（模型损坏、动态库加载失败等）。
class VoiceError extends VoiceEvent {
  const VoiceError(this.message);
  final String message;
}

/// 离线唤醒与识别：持续送入 16kHz 单声道采样。
///
/// - 平时只做唤醒词检测（模型很小，耗电低）。
/// - 听到唤醒词或手动开始后，用语音活动检测（Silero VAD）判断开口与说完，说话期间每 0.7 秒用离线识别模型
///   识别一次已说的部分作为实时字幕，说完（静音 0.7 秒）后识别整句。一直不开口 6 秒或说满 15 秒时结束。
/// - 助手说话时可以开启“打断检测”：检测到用户持续开口 0.5 秒，发出 [VoiceBargeIn] 并直接开始识别；
///   这期间唤醒词检测照常进行，说唤醒词也能打断。
///
/// 只在后台 isolate 中使用（见 [VoiceWorker]），也可以在测试中直接使用。
class VoiceRecognizer {
  VoiceRecognizer(VoiceModelPaths paths, {List<String> wakeWords = kWakeWords, int threads = 2}) {
    _kws = sherpa.KeywordSpotter(
      sherpa.KeywordSpotterConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(encoder: paths.kwsEncoder, decoder: paths.kwsDecoder, joiner: paths.kwsJoiner),
          tokens: paths.kwsTokens,
          numThreads: 1,
          debug: false,
        ),
        keywordsBuf: wakeWords.join('\n'),
        keywordsBufSize: wakeWords.join('\n').length,
        keywordsThreshold: 0.2,
        keywordsScore: 1.5,
      ),
    );
    _kwsStream = _kws.createStream();
    _asr = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          senseVoice: paths.asr == AsrModel.senseVoice ? sherpa.OfflineSenseVoiceModelConfig(model: paths.asrModel, useInverseTextNormalization: true) : const sherpa.OfflineSenseVoiceModelConfig(),
          paraformer: paths.asr == AsrModel.paraformer ? sherpa.OfflineParaformerModelConfig(model: paths.asrModel) : const sherpa.OfflineParaformerModelConfig(),
          tokens: paths.asrTokens,
          numThreads: threads,
          debug: false,
        ),
      ),
    );
    _vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(model: paths.vad, threshold: 0.5, minSilenceDuration: 0.25, minSpeechDuration: 0.15, maxSpeechDuration: 20),
        sampleRate: sampleRate,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 30,
    );
  }

  static const sampleRate = 16000;

  late final sherpa.KeywordSpotter _kws;
  late final sherpa.OnlineStream _kwsStream;
  late final sherpa.OfflineRecognizer _asr;
  late final sherpa.VoiceActivityDetector _vad;

  /// 正在识别的一句话的全部采样。
  final List<Float32List> _utterance = [];
  int _utteranceSamples = 0;
  bool _listening = false;
  bool _heard = false;
  int _silence = 0;
  int _sinceDecode = 0;
  String _partial = '';

  /// 打断检测：助手说话期间连续检测到人声的采样数。
  bool monitor = false;
  int _voiced = 0;

  /// 是否正在识别一句话（否则在检测唤醒词）。
  bool get listening => _listening;

  /// 是否检测唤醒词（关闭语音唤醒时只在手动开始后识别）。
  bool wakeEnabled = true;

  /// 开始识别一句话（点按麦克风、唤醒或打断）。
  void listen() {
    _listening = true;
    _heard = false;
    _silence = 0;
    _sinceDecode = 0;
    _partial = '';
    _utterance.clear();
    _utteranceSamples = 0;
    _vad.reset();
  }

  /// 取消正在识别的一句话。
  void cancel() {
    _listening = false;
    _utterance.clear();
    _utteranceSamples = 0;
    _partial = '';
  }

  String _decode() {
    if (_utterance.isEmpty) return '';
    final all = Float32List(_utteranceSamples);
    var o = 0;
    for (final c in _utterance) {
      all.setAll(o, c);
      o += c.length;
    }
    final s = _asr.createStream();
    s.acceptWaveform(samples: all, sampleRate: sampleRate);
    _asr.decode(s);
    final text = _asr.getResult(s).text.trim();
    s.free();
    return text;
  }

  /// 送入一段采样（-1..1 的浮点数），返回期间产生的事件。
  List<VoiceEvent> accept(Float32List samples) {
    final events = <VoiceEvent>[];
    if (_listening) {
      _utterance.add(samples);
      _utteranceSamples += samples.length;
      _vad.acceptWaveform(samples);
      final speaking = _vad.isDetected();
      while (!_vad.isEmpty()) {
        _vad.pop();
      }
      if (speaking) {
        _heard = true;
        _silence = 0;
      } else {
        _silence += samples.length;
      }
      _sinceDecode += samples.length;
      // 实时字幕。
      if (_heard && _sinceDecode >= sampleRate * 7 ~/ 10) {
        _sinceDecode = 0;
        final t = _decode();
        if (t != _partial && t.isNotEmpty) {
          _partial = t;
          events.add(VoicePartial(t));
        }
      }
      final ended = _heard && _silence >= sampleRate * 7 ~/ 10;
      final idle = !_heard && _utteranceSamples > sampleRate * 6;
      final tooLong = _utteranceSamples > sampleRate * 15;
      if (ended || idle || tooLong) {
        final text = _heard ? _decode() : '';
        events.add(VoiceFinal(text));
        cancel();
        _kws.reset(_kwsStream);
      }
      return events;
    }
    if (monitor) {
      _vad.acceptWaveform(samples);
      final speaking = _vad.isDetected();
      while (!_vad.isEmpty()) {
        _vad.pop();
      }
      _voiced = speaking ? _voiced + samples.length : 0;
      if (_voiced >= sampleRate ~/ 2) {
        _voiced = 0;
        monitor = false;
        events.add(const VoiceBargeIn());
        listen();
        _heard = true;
        _utterance.add(samples);
        _utteranceSamples += samples.length;
        return events;
      }
      // 没有检测到持续说话时继续检测唤醒词：说唤醒词总能打断。
    }
    if (!wakeEnabled) return events;
    _kwsStream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    while (_kws.isReady(_kwsStream)) {
      _kws.decode(_kwsStream);
      final word = _kws.getResult(_kwsStream).keyword;
      if (word.isNotEmpty) {
        _kws.reset(_kwsStream);
        events.add(VoiceWake(word));
        listen();
        break;
      }
    }
    return events;
  }

  void free() {
    _kwsStream.free();
    _kws.free();
    _asr.free();
    _vad.free();
  }

  /// 16 位小端 PCM 转为 -1..1 的浮点采样。
  static Float32List pcm16ToFloat(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final out = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt16(i * 2, Endian.little) / 32768;
    }
    return out;
  }
}

/// sherpa-onnx 动态库所在目录：Linux 的插件库放在可执行文件旁的 lib 中（按名称加载找不到），其他平台按默认方式加载。
String? sherpaLibraryDir() {
  if (kIsWeb || !Platform.isLinux) return null;
  return '${File(Platform.resolvedExecutable).parent.path}/lib';
}

/// 在后台 isolate 中运行 [VoiceRecognizer]：解码很耗 CPU，放在界面线程会让动画掉帧。
class VoiceWorker {
  VoiceWorker._(this._isolate, this._send, this.events);

  final Isolate _isolate;
  final SendPort _send;

  /// 识别事件（在主 isolate 上收到）。
  final Stream<VoiceEvent> events;

  static Future<VoiceWorker> start(VoiceModelPaths paths, {required bool wake, List<String> wakeWords = kWakeWords}) async {
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(_main, (receive.sendPort, paths.kwsDir, paths.asrDir, paths.vad, paths.asr.index, sherpaLibraryDir(), wake, wakeWords));
    final ready = Completer<SendPort>();
    final controller = StreamController<VoiceEvent>.broadcast();
    receive.listen((m) {
      switch (m) {
        case SendPort p:
          ready.complete(p);
        case ('wake', String w):
          controller.add(VoiceWake(w));
        case ('partial', String t):
          controller.add(VoicePartial(t));
        case ('final', String t):
          controller.add(VoiceFinal(t));
        case ('barge', _):
          controller.add(const VoiceBargeIn());
        case ('error', String e):
          if (!ready.isCompleted) ready.completeError(Exception(e));
          controller.add(VoiceError(e));
      }
    });
    final send = await ready.future;
    return VoiceWorker._(isolate, send, controller.stream);
  }

  /// 送入 16 位小端 PCM（16kHz 单声道）。
  void feed(Uint8List pcm) => _send.send(('pcm', TransferableTypedData.fromList([pcm])));

  void listen() => _send.send(('listen', null));
  void cancel() => _send.send(('cancel', null));
  void setWake(bool on) => _send.send(('wake', on));

  /// 助手说话期间检测用户是否开口（打断）。
  void setMonitor(bool on) => _send.send(('monitor', on));

  void stop() {
    _send.send(('stop', null));
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  static void _main((SendPort, String, String, String, int, String?, bool, List<String>) args) {
    final (out, kws, asr, vad, kind, lib, wake, words) = args;
    VoiceRecognizer recognizer;
    try {
      sherpa.initBindings(lib);
      recognizer = VoiceRecognizer(VoiceModelPaths(kwsDir: kws, asrDir: asr, vad: vad, asr: AsrModel.values[kind]), wakeWords: words)..wakeEnabled = wake;
    } catch (e) {
      out.send(('error', '$e'));
      return;
    }
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    inbox.listen((m) {
      switch (m) {
        case ('pcm', TransferableTypedData data):
          final samples = VoiceRecognizer.pcm16ToFloat(data.materialize().asUint8List());
          for (final e in recognizer.accept(samples)) {
            out.send(switch (e) {
              VoiceWake(:final word) => ('wake', word),
              VoicePartial(:final text) => ('partial', text),
              VoiceFinal(:final text) => ('final', text),
              VoiceBargeIn() => ('barge', null),
              VoiceError(:final message) => ('error', message),
            });
          }
        case ('listen', _):
          recognizer.listen();
        case ('cancel', _):
          recognizer.cancel();
        case ('wake', bool on):
          recognizer.wakeEnabled = on;
        case ('monitor', bool on):
          recognizer.monitor = on;
        case ('stop', _):
          recognizer.free();
          inbox.close();
      }
    });
  }
}
