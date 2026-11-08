import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 唤醒词：拼音按模型的声母、韵母切分（见唤醒模型的 tokens.txt），@ 后为显示名称。
const kWakeWords = [
  'n ǐ h ǎo y ún y īn @你好云音',
  'h āi y ún y īn @嗨云音',
  'y ún y īn y ún y īn @云音云音',
];

/// 离线语音模型所在的目录（下载并解压后的结构见 [VoiceModelStore]）。
class VoiceModelPaths {
  const VoiceModelPaths({required this.kwsDir, required this.asrDir});

  final String kwsDir;
  final String asrDir;

  String get kwsEncoder => '$kwsDir/encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  String get kwsDecoder => '$kwsDir/decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  String get kwsJoiner => '$kwsDir/joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  String get kwsTokens => '$kwsDir/tokens.txt';
  String get asrModel => '$asrDir/model.int8.onnx';
  String get asrTokens => '$asrDir/tokens.txt';

  List<String> get files => [kwsEncoder, kwsDecoder, kwsJoiner, kwsTokens, asrModel, asrTokens];
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

/// 识别引擎出错（模型损坏、动态库加载失败等）。
class VoiceError extends VoiceEvent {
  const VoiceError(this.message);
  final String message;
}

/// 离线唤醒与识别：持续把 16kHz 单声道采样送进来；平时只做唤醒词检测（模型很小，耗电低），
/// 听到唤醒词或手动开始后切换到语音识别，说完一句话（端点检测）或超时后回到唤醒词检测。
///
/// 只在后台 isolate 中使用（见 [VoiceWorker]），也可以在测试中直接使用。
class VoiceRecognizer {
  VoiceRecognizer(VoiceModelPaths paths, {List<String> wakeWords = kWakeWords, int threads = 1}) {
    _kws = sherpa.KeywordSpotter(
      sherpa.KeywordSpotterConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(encoder: paths.kwsEncoder, decoder: paths.kwsDecoder, joiner: paths.kwsJoiner),
          tokens: paths.kwsTokens,
          numThreads: threads,
          debug: false,
        ),
        keywordsBuf: wakeWords.join('\n'),
        keywordsBufSize: wakeWords.join('\n').length,
        keywordsThreshold: 0.2,
        keywordsScore: 1.5,
      ),
    );
    _kwsStream = _kws.createStream();
    _asr = sherpa.OnlineRecognizer(
      sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(
          zipformer2Ctc: sherpa.OnlineZipformer2CtcModelConfig(model: paths.asrModel),
          tokens: paths.asrTokens,
          numThreads: threads,
          debug: false,
        ),
        // 说完后停顿 0.8 秒即认为一句话结束；一直没开口时 [_commandTimeout] 结束。
        rule1MinTrailingSilence: 2.0,
        rule2MinTrailingSilence: 0.8,
        rule3MinUtteranceLength: 12,
      ),
    );
  }

  static const sampleRate = 16000;

  /// 唤醒后最多等多久（一直没说话时结束）。
  static const _commandTimeout = 8 * sampleRate;

  late final sherpa.KeywordSpotter _kws;
  late final sherpa.OnlineStream _kwsStream;
  late final sherpa.OnlineRecognizer _asr;
  sherpa.OnlineStream? _asrStream;
  int _asrSamples = 0;
  String _partial = '';

  /// 是否正在识别一句话（否则在检测唤醒词）。
  bool get listening => _asrStream != null;

  /// 是否检测唤醒词（关闭语音唤醒时只在手动开始后识别）。
  bool wakeEnabled = true;

  /// 手动开始识别一句话（点按麦克风按钮）。
  void listen() {
    _asrStream?.free();
    _asrStream = _asr.createStream();
    _asrSamples = 0;
    _partial = '';
  }

  /// 取消正在识别的一句话。
  void cancel() {
    _asrStream?.free();
    _asrStream = null;
    _partial = '';
  }

  /// 送入一段采样（-1..1 的浮点数），返回期间产生的事件。
  List<VoiceEvent> accept(Float32List samples) {
    final events = <VoiceEvent>[];
    final asr = _asrStream;
    if (asr != null) {
      asr.acceptWaveform(samples: samples, sampleRate: sampleRate);
      _asrSamples += samples.length;
      while (_asr.isReady(asr)) {
        _asr.decode(asr);
      }
      final text = _asr.getResult(asr).text.trim();
      if (text != _partial) {
        _partial = text;
        events.add(VoicePartial(text));
      }
      final timeout = _asrSamples > _commandTimeout && text.isEmpty;
      if (_asr.isEndpoint(asr) && text.isNotEmpty || timeout || _asrSamples > 20 * sampleRate) {
        events.add(VoiceFinal(text));
        cancel();
        // 识别期间的声音不再送去检测唤醒词，回到唤醒检测时重新开始。
        _kws.reset(_kwsStream);
      }
      return events;
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
    _asrStream?.free();
    _kwsStream.free();
    _kws.free();
    _asr.free();
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

  static Future<VoiceWorker> start(VoiceModelPaths paths, {required bool wake}) async {
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(_main, (receive.sendPort, paths.kwsDir, paths.asrDir, sherpaLibraryDir(), wake));
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

  void stop() {
    _send.send(('stop', null));
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  static void _main((SendPort, String, String, String?, bool) args) {
    final (out, kws, asr, lib, wake) = args;
    VoiceRecognizer recognizer;
    try {
      sherpa.initBindings(lib);
      recognizer = VoiceRecognizer(VoiceModelPaths(kwsDir: kws, asrDir: asr))..wakeEnabled = wake;
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
              VoiceError(:final message) => ('error', message),
            });
          }
        case ('listen', _):
          recognizer.listen();
        case ('cancel', _):
          recognizer.cancel();
        case ('wake', bool on):
          recognizer.wakeEnabled = on;
        case ('stop', _):
          recognizer.free();
          inbox.close();
      }
    });
  }
}
