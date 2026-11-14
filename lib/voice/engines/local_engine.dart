import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../assistant/voice_engine.dart' show sherpaLibraryDir;
import '../tts_types.dart';
import '../voice_library.dart';
import '../wav.dart';

/// 一个本地离线声音：ZipVoice 模型加一段真人参考录音（THCHS-30，见 assets/voices/NOTICE.txt）。
///
/// ZipVoice 在约十万小时真实语音上训练，按参考录音的音色说话，声调、变调与停顿接近真人；
/// 此前每个音色各用一个小型 VITS / Piper / Matcha 模型，词典外的短语没有变调，听起来像逐字念。
/// 五个音色共用一个模型（一次下载），各自的参考录音随应用附带。
class LocalVoiceModel {
  const LocalVoiceModel(this.id, {required this.prompt, required this.promptText, this.languages = const {VoiceLanguage.zh}});

  final String id;

  /// 参考录音（应用资源，16 kHz 单声道 WAV）与录音的文字。
  final String prompt;
  final String promptText;
  final Set<VoiceLanguage> languages;

  /// 发布页中的模型压缩包（tts-models 下）。
  String get archive => LocalVoiceModels.archive.$1;
  String get sha256 => LocalVoiceModels.archive.$2;
  int get sizeMb => LocalVoiceModels.sizeMb;

  String get folder => archive.replaceAll('.tar.bz2', '');
}

/// 本地离线声音目录。
abstract final class LocalVoiceModels {
  static const all = [
    LocalVoiceModel(LocalVoiceIds.yunxi, prompt: 'assets/voices/yunxi.wav', promptText: '单位不是我老爹开的，凭什么要一次'),
    LocalVoiceModel(LocalVoiceIds.xiaoyou, prompt: 'assets/voices/xiaoyou.wav', promptText: '一位专家谈到大家感兴趣的减肥时说，减肥'),
    LocalVoiceModel(LocalVoiceIds.wanxing, prompt: 'assets/voices/wanxing.wav', promptText: '此外还有麻辣味盐、海鲜味盐、五香盐'),
    LocalVoiceModel(LocalVoiceIds.qingchuan, prompt: 'assets/voices/qingchuan.wav', promptText: '英雄曾昭刚无愧于这光荣的称号'),
    LocalVoiceModel(LocalVoiceIds.muyan, prompt: 'assets/voices/muyan.wav', promptText: '嫌疑犯眼看逃脱无望，窜上屋顶，纵身跳下，畏罪自杀'),
  ];

  /// ZipVoice 蒸馏版（int8）：CPU 上比完整精度版更快，回识准确率相同。
  static const archive = ('sherpa-onnx-zipvoice-distill-int8-zh-en-emilia.tar.bz2', '77219c8b40f4ee8d73a7f902305ff6c1128ef9b54461c41b4ca6ed890b6c2803');
  static const sizeMb = 155;

  /// ZipVoice 使用的声码器。
  static const vocoder = ('vocos_24khz.onnx', 'bcb3b970e384161c4d634f0bb9e999ff1c471b34c9bc0b1049a5014065ed3cc0');

  /// 之前用过的小模型，装好 ZipVoice 后删除。
  static const legacy = [
    'vits-piper-zh_CN-xiao_ya-medium-int8',
    'vits-piper-zh_CN-chaowen-medium-int8',
    'vits-piper-zh_CN-xiao_ya-medium',
    'vits-piper-zh_CN-chaowen-medium',
    'vits-piper-zh_CN-huayan-medium',
    'matcha-icefall-zh-baker',
    'vits-zh-hf-fanchen-ZhiHuiLaoZhe_new',
    'vocos-22khz-univ.onnx',
  ];

  static LocalVoiceModel? byId(String id) => all.where((m) => m.id == id).firstOrNull;
}

/// 本地离线引擎（sherpa-onnx ZipVoice）：模型按需下载，在后台 isolate 中合成。
class LocalTtsEngine extends TtsEngine {
  LocalTtsEngine({Dio? dio, this.libraryDir, this.rootOverride})
    : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 60)));

  final Dio _dio;

  /// 测试用：sherpa-onnx 动态库目录与声音模型目录。
  final String? libraryDir;
  final String? rootOverride;

  @override
  String get id => 'local';

  @override
  String get name => '本地离线';

  @override
  bool get offline => true;

  @override
  bool get configured => true;

  @override
  Set<VoiceLanguage> get languages => VoiceLanguage.values.toSet();

  static const _github = 'https://github.com/k2-fsa/sherpa-onnx/releases/download';
  static const _proxy = 'https://ghfast.top/';

  static Future<String> _defaultRoot() async => '${(await getApplicationSupportDirectory()).path}/voices';

  Future<String> _root() async => rootOverride ?? await _defaultRoot();

  /// 模型已下载并通过校验（解压完成后写入标记文件）。
  static Future<bool> isInstalled(LocalVoiceModel m) async => _installedIn(await _defaultRoot(), m);

  Future<bool> installed(LocalVoiceModel m) async => _installedIn(await _root(), m);

  static bool _installedIn(String root, LocalVoiceModel m) {
    return File('$root/${m.folder}/.ok').existsSync() && File('$root/${LocalVoiceModels.vocoder.$1}').existsSync();
  }

  @override
  Future<bool> ready(EngineVoice voice, VoiceLanguage lang) async {
    final m = LocalVoiceModels.byId(voice.voices[lang] ?? '');
    return m != null && await installed(m);
  }

  @override
  Future<void> prepare(EngineVoice voice, VoiceLanguage lang, {void Function(double progress)? onProgress, CancelToken? cancel}) async {
    final m = LocalVoiceModels.byId(voice.voices[lang] ?? '');
    if (m == null) throw TtsException('这个音色没有${lang.label}的离线声音', engine: name, retryable: false);
    if (await installed(m)) return;
    final root = await _root();
    Directory(root).createSync(recursive: true);
    final tmp = (await getTemporaryDirectory()).path;
    Future<void> fetch(String tag, String file, String sha, String dest, double from, double to) async {
      Object? last;
      for (final url in ['$_github/$tag/$file', '$_proxy$_github/$tag/$file']) {
        try {
          await _dio.download(url, '$dest.part', cancelToken: cancel, onReceiveProgress: (r, t) => t > 0 ? onProgress?.call(from + (to - from) * r / t) : null);
          if (await compute(_sha256File, '$dest.part') != sha) throw TtsException('声音模型校验失败', engine: name);
          File('$dest.part').renameSync(dest);
          return;
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) rethrow;
          last = e;
        }
      }
      throw TtsException('声音模型下载失败，请检查网络后重试（$last）', engine: name);
    }

    if (!File('$root/${LocalVoiceModels.vocoder.$1}').existsSync()) {
      await fetch('vocoder-models', LocalVoiceModels.vocoder.$1, LocalVoiceModels.vocoder.$2, '$root/${LocalVoiceModels.vocoder.$1}', 0, 0.25);
    }
    if (!File('$root/${m.folder}/.ok').existsSync()) {
      final archive = '$tmp/${m.archive}';
      await fetch('tts-models', m.archive, m.sha256, archive, 0.25, 0.92);
      await compute(_extract, (archive, root));
      File(archive).deleteSync();
      File('$root/${m.folder}/.ok').writeAsStringSync(m.sha256);
    }
    for (final old in LocalVoiceModels.legacy) {
      final type = FileSystemEntity.typeSync('$root/$old');
      if (type == FileSystemEntityType.directory) Directory('$root/$old').deleteSync(recursive: true);
      if (type == FileSystemEntityType.file) File('$root/$old').deleteSync();
    }
    onProgress?.call(1);
  }

  /// 删除已下载的声音模型。
  static Future<void> remove(LocalVoiceModel m) async {
    final d = Directory('${await _defaultRoot()}/${m.folder}');
    if (d.existsSync()) d.deleteSync(recursive: true);
  }

  _TtsWorker? _worker;

  /// 解码后的参考录音（16 位 PCM 转成 -1..1 的浮点数）。
  static final _prompts = <String, (Float32List, int)>{};

  static Future<(Float32List, int)> _prompt(LocalVoiceModel m) async {
    final cached = _prompts[m.id];
    if (cached != null) return cached;
    final wav = (await rootBundle.load(m.prompt)).buffer.asUint8List();
    return _prompts[m.id] = decodeWav16(wav);
  }

  @override
  Stream<TtsAudio> synthesize(EngineVoice voice, TtsRequest request, {CancelToken? cancel}) async* {
    final m = LocalVoiceModels.byId(voice.voices[request.language] ?? '');
    if (m == null) throw TtsException('这个音色没有${request.language.label}的离线声音', engine: name, retryable: false);
    if (!await installed(m)) throw TtsException('离线声音模型还没有下载', engine: name, retryable: false);
    final root = await _root();
    final (prompt, promptRate) = await _prompt(m);
    final worker = _worker ??= await _TtsWorker.start(libraryDir ?? sherpaLibraryDir());
    // 本地模型只能调整语速（不改音调，保持音色身份），情绪通过语速与停顿体现。
    final speed = (request.prosody.rate * _emotionRate(request.prosody)).clamp(0.6, 1.6);
    final r = await worker.generate(
      root: root,
      folder: m.folder,
      voice: m.id,
      prompt: prompt,
      promptRate: promptRate,
      promptText: m.promptText,
      text: request.text,
      speed: speed,
      pauseMs: request.prosody.pauseMs,
    );
    debugPrint('tts local: ${m.id} ${r.steps} 步，合成 ${r.ms} ms，RTF ${r.rtf.toStringAsFixed(2)}');
    if (cancel?.isCancelled ?? false) return;
    yield TtsAudio(r.wav, format: 'wav');
  }

  static double _emotionRate(Prosody p) => switch (p.emotion) {
    Emotion.excited => 1 + 0.12 * p.intensity,
    Emotion.happy => 1 + 0.06 * p.intensity,
    Emotion.calm || Emotion.gentle => 1 - 0.06 * p.intensity,
    Emotion.sad => 1 - 0.1 * p.intensity,
    Emotion.serious => 1 - 0.03 * p.intensity,
    Emotion.neutral => 1.0,
  };

  void dispose() => _worker?.stop();
}

String _sha256File(String path) => sha256.convert(File(path).readAsBytesSync()).toString();

/// 边解压边写入磁盘（模型约 300 MB，不能整个读进内存），然后删掉测试音频与脚本。
Future<void> _extract((String, String) args) async {
  final (archive, root) = args;
  await extractFileToDisk(archive, root);
  final folder = Directory('$root/${archive.split('/').last.replaceAll('.tar.bz2', '')}');
  if (!folder.existsSync()) return;
  for (final e in folder.listSync(recursive: true)) {
    final name = e.path.split('/').last;
    if (e is Directory && name == 'test_wavs') e.deleteSync(recursive: true);
    if (e is File && (name.endsWith('.py') || name.endsWith('.sh')) && e.existsSync()) e.deleteSync();
  }
}

/// 下一句用几步：合成太慢（RTF > 0.7）时减一步，很快（RTF < 0.35）时加一步，在 2–4 步之间。
@visibleForTesting
int zipVoiceSteps(int steps, double rtf) => rtf > 0.7 ? math.max(2, steps - 1) : (rtf < 0.35 ? math.min(4, steps + 1) : steps);

/// 一次合成的结果：WAV、用了几步、耗时与实时率。
typedef _Generated = ({Uint8List wav, int steps, int ms, double rtf});

/// 在后台 isolate 中加载 ZipVoice 并合成（模型加载一次后保留）。
///
/// 采样步数按这台设备的速度自动调整：合成 1 秒语音要超过 0.7 秒（RTF > 0.7）时减少一步，
/// 低于 0.35 时加一步（最多 4 步、最少 2 步），保证边读上一句边合成下一句来得及。
class _TtsWorker {
  _TtsWorker(this._isolate, this._send, this._replies);

  final Isolate _isolate;
  final SendPort _send;
  final Stream<Object?> _replies;
  int _seq = 0;

  static Future<_TtsWorker> start(String? lib) async {
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(_main, (receive.sendPort, lib));
    final replies = receive.asBroadcastStream();
    final send = await replies.firstWhere((m) => m is SendPort) as SendPort;
    return _TtsWorker(isolate, send, replies);
  }

  Future<_Generated> generate({
    required String root,
    required String folder,
    required String voice,
    required Float32List prompt,
    required int promptRate,
    required String promptText,
    required String text,
    required double speed,
    required int pauseMs,
  }) async {
    final id = ++_seq;
    _send.send((id, root, folder, voice, TransferableTypedData.fromList([prompt]), promptRate, promptText, text, speed, pauseMs));
    final reply = await _replies.firstWhere((m) => m is (int, Object?) && m.$1 == id) as (int, Object?);
    final r = reply.$2;
    if (r is (TransferableTypedData, int, int, double)) return (wav: r.$1.materialize().asUint8List(), steps: r.$2, ms: r.$3, rtf: r.$4);
    throw TtsException('$r', engine: '本地离线');
  }

  void stop() => _isolate.kill(priority: Isolate.beforeNextEvent);

  static int steps = 4;

  static void _main((SendPort, String?) args) {
    final (out, lib) = args;
    sherpa.initBindings(lib);
    final loaded = <String, sherpa.OfflineTts>{};
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    inbox.listen((m) {
      final (id, root, folder, _, promptData, promptRate, promptText, text, speed, pauseMs) =
          m as (int, String, String, String, TransferableTypedData, int, String, String, double, int);
      try {
        final tts = loaded[folder] ??= _load('$root/$folder', root);
        final prompt = promptData.materialize().asFloat32List();
        final sw = Stopwatch()..start();
        final used = steps;
        final audio = tts.generateWithConfig(
          text: text,
          config: sherpa.OfflineTtsGenerationConfig(speed: speed, referenceAudio: prompt, referenceSampleRate: promptRate, referenceText: promptText, numSteps: used),
        );
        final ms = sw.elapsedMilliseconds;
        final seconds = audio.samples.length / audio.sampleRate;
        final rtf = seconds > 0 ? ms / 1000 / seconds : 0.0;
        steps = zipVoiceSteps(steps, rtf);
        out.send((id, (TransferableTypedData.fromList([encodeWav(audio.samples, audio.sampleRate, trailingSilenceMs: pauseMs)]), used, ms, rtf)));
      } catch (e) {
        out.send((id, '$e'));
      }
    });
  }

  static sherpa.OfflineTts _load(String dir, String root) {
    String find(String suffix) => Directory(dir).listSync().map((e) => e.path).firstWhere((p) => p.endsWith(suffix), orElse: () => '$dir/$suffix');
    final config = sherpa.OfflineTtsModelConfig(
      zipvoice: sherpa.OfflineTtsZipVoiceModelConfig(
        tokens: '$dir/tokens.txt',
        encoder: find('encoder.int8.onnx'),
        decoder: find('decoder.int8.onnx'),
        vocoder: '$root/${LocalVoiceModels.vocoder.$1}',
        dataDir: '$dir/espeak-ng-data',
        lexicon: '$dir/lexicon.txt',
      ),
      // 手机上 4 个线程（多为大核）合成最快，再多反而争抢。
      numThreads: 4,
      debug: false,
    );
    return sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: config, maxNumSenetences: 1));
  }
}
