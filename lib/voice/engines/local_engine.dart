import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../assistant/voice_engine.dart' show sherpaLibraryDir;
import '../tts_types.dart';
import '../voice_library.dart';
import '../wav.dart';

/// 一个本地离线声音模型：sherpa-onnx 官方发布的压缩包（按 SHA-256 校验）与模型类型。
class LocalVoiceModel {
  const LocalVoiceModel(this.id, this.archive, this.sha256, this.sizeMb, {this.matcha = false, this.languages = const {VoiceLanguage.zh}});

  final String id;

  /// 发布页中的文件名（tts-models 下）。
  final String archive;
  final String sha256;
  final int sizeMb;

  /// Matcha 声学模型（还需要声码器）；否则为 VITS / Piper。
  final bool matcha;
  final Set<VoiceLanguage> languages;

  String get folder => archive.replaceAll('.tar.bz2', '');
}

/// 本地离线声音模型目录：每个音色对应一个独立的中文声音模型。
abstract final class LocalVoiceModels {
  static const all = [
    LocalVoiceModel(LocalVoiceIds.xiaoya, 'vits-piper-zh_CN-xiao_ya-medium-int8.tar.bz2', 'eab027e194e70289233cf12308373611fa4e2e96ef2d97354ef433ab663d831f', 14),
    LocalVoiceModel(LocalVoiceIds.chaowen, 'vits-piper-zh_CN-chaowen-medium-int8.tar.bz2', 'f5f7c8628427fbb259ea4b7ec1a9a822a0c04e3f267071f0abfa0610371d9e0c', 14),
    LocalVoiceModel(LocalVoiceIds.huayan, 'vits-piper-zh_CN-huayan-medium.tar.bz2', 'dbdfec42b91d9cee31cce9ff4b3e9c305eb6fbf60546d071f7e46273554cce6b', 64),
    LocalVoiceModel(LocalVoiceIds.baker, 'matcha-icefall-zh-baker.tar.bz2', '8da2e113b85dfea37b11bcdc994506aa86b584ee3348c2065271fb6f75cb83b8', 72, matcha: true),
    LocalVoiceModel(LocalVoiceIds.laozhe, 'vits-zh-hf-fanchen-ZhiHuiLaoZhe_new.tar.bz2', 'fa6b767c979846f1af3141666158ce91fdad116a15a29654d7e4a071d819af4c', 114),
  ];

  /// Matcha 模型使用的声码器。
  static const vocoder = ('vocos-22khz-univ.onnx', '0574a135aa1db2de6e181050db2ec528496cacd4a4701fc5d7faf9f9804c0081');

  static LocalVoiceModel? byId(String id) => all.where((m) => m.id == id).firstOrNull;
}

/// 本地离线引擎（sherpa-onnx）：声音模型按需下载，在后台 isolate 中合成，每句约 0.1–0.5 秒。
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
    if (!File('$root/${m.folder}/.ok').existsSync()) return false;
    if (m.matcha && !File('$root/${LocalVoiceModels.vocoder.$1}').existsSync()) return false;
    return true;
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

    if (m.matcha && !File('$root/${LocalVoiceModels.vocoder.$1}').existsSync()) {
      await fetch('vocoder-models', LocalVoiceModels.vocoder.$1, LocalVoiceModels.vocoder.$2, '$root/${LocalVoiceModels.vocoder.$1}', 0, 0.4);
    }
    final archive = '$tmp/${m.archive}';
    await fetch('tts-models', m.archive, m.sha256, archive, m.matcha ? 0.4 : 0, 0.92);
    await compute(_extract, (archive, root));
    File(archive).deleteSync();
    File('$root/${m.folder}/.ok').writeAsStringSync(m.sha256);
    onProgress?.call(1);
  }

  /// 删除已下载的声音模型。
  static Future<void> remove(LocalVoiceModel m) async {
    final d = Directory('${await _defaultRoot()}/${m.folder}');
    if (d.existsSync()) d.deleteSync(recursive: true);
  }

  _TtsWorker? _worker;

  @override
  Stream<TtsAudio> synthesize(EngineVoice voice, TtsRequest request, {CancelToken? cancel}) async* {
    final m = LocalVoiceModels.byId(voice.voices[request.language] ?? '');
    if (m == null) throw TtsException('这个音色没有${request.language.label}的离线声音', engine: name, retryable: false);
    if (!await installed(m)) throw TtsException('离线声音模型还没有下载', engine: name, retryable: false);
    final root = await _root();
    final worker = _worker ??= await _TtsWorker.start(libraryDir ?? sherpaLibraryDir());
    // 本地模型只能调整语速（不改音调，保持音色身份），情绪通过语速与停顿体现。
    final speed = (request.prosody.rate * _emotionRate(request.prosody)).clamp(0.6, 1.6);
    final wav = await worker.generate(root: root, model: m, text: request.text, speed: speed, pauseMs: request.prosody.pauseMs);
    if (cancel?.isCancelled ?? false) return;
    yield TtsAudio(wav, format: 'wav');
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

/// 解压整个压缩包（跳过测试音频与脚本）。
void _extract((String, String) args) {
  final (archive, root) = args;
  final tar = TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(File(archive).readAsBytesSync()));
  for (final f in tar.files) {
    if (!f.isFile || f.name.contains('/test_wavs/') || f.name.endsWith('.py') || f.name.endsWith('.sh')) continue;
    final out = File('$root/${f.name}');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(f.content as List<int>);
  }
}

/// 在后台 isolate 中加载声音模型并合成（模型加载一次后保留）。
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

  Future<Uint8List> generate({required String root, required LocalVoiceModel model, required String text, required double speed, required int pauseMs}) async {
    final id = ++_seq;
    _send.send((id, root, model.folder, model.matcha, text, speed, pauseMs));
    final reply = await _replies.firstWhere((m) => m is (int, Object?) && m.$1 == id) as (int, Object?);
    final r = reply.$2;
    if (r is TransferableTypedData) return r.materialize().asUint8List();
    throw TtsException('$r', engine: '本地离线');
  }

  void stop() => _isolate.kill(priority: Isolate.beforeNextEvent);

  static void _main((SendPort, String?) args) {
    final (out, lib) = args;
    sherpa.initBindings(lib);
    final loaded = <String, sherpa.OfflineTts>{};
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    inbox.listen((m) {
      final (id, root, folder, matcha, text, speed, pauseMs) = m as (int, String, String, bool, String, double, int);
      try {
        final tts = loaded[folder] ??= _load('$root/$folder', root, matcha);
        final audio = tts.generate(text: text, speed: speed);
        out.send((id, TransferableTypedData.fromList([encodeWav(audio.samples, audio.sampleRate, trailingSilenceMs: pauseMs)])));
      } catch (e) {
        out.send((id, '$e'));
      }
    });
  }

  /// 按目录中的文件组装配置：模型、tokens、词典、espeak 数据、jieba 词典与文本规整规则。
  static sherpa.OfflineTts _load(String dir, String root, bool matcha) {
    final files = Directory(dir).listSync().map((e) => e.path).toList();
    String? find(bool Function(String) test) => files.where((f) => test(f.split('/').last)).firstOrNull;
    // Matcha 包里有不同步数的声学模型，用 3 步的（质量与速度的平衡）。
    final model = find((n) => n.endsWith('steps-3.onnx')) ?? find((n) => n.endsWith('.onnx')) ?? '';
    final tokens = find((n) => n == 'tokens.txt') ?? '';
    final lexicon = find((n) => n == 'lexicon.txt') ?? '';
    final espeak = Directory('$dir/espeak-ng-data').existsSync() ? '$dir/espeak-ng-data' : '';
    final dict = Directory('$dir/dict').existsSync() ? '$dir/dict' : '';
    final fsts = files.where((f) => f.endsWith('.fst')).join(',');
    final config = matcha
        ? sherpa.OfflineTtsModelConfig(
            matcha: sherpa.OfflineTtsMatchaModelConfig(acousticModel: model, vocoder: '$root/${LocalVoiceModels.vocoder.$1}', lexicon: lexicon, tokens: tokens, dataDir: espeak, dictDir: dict),
            numThreads: 2,
            debug: false,
          )
        : sherpa.OfflineTtsModelConfig(
            vits: sherpa.OfflineTtsVitsModelConfig(model: model, tokens: tokens, lexicon: lexicon, dataDir: espeak, dictDir: dict),
            numThreads: 2,
            debug: false,
          );
    return sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: config, ruleFsts: fsts));
  }
}
