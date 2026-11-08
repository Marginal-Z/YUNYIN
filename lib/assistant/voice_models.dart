import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'voice_engine.dart';

/// 离线语音模型（sherpa-onnx 官方发布）：唤醒词检测约 5 MB；语音识别为 SenseVoice（高精度，约 227 MB）
/// 或 Paraformer 小模型（标准，约 79 MB）；语音活动检测（Silero VAD）不到 1 MB。
/// 第一次打开语音功能时下载并解压到应用数据目录，不随安装包分发（不用语音的用户不增加体积）。
class VoiceModelStore {
  static const _kws = 'sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01';

  /// 识别模型的压缩包与官方发布的 SHA-256。
  static const _asrArchives = {
    AsrModel.senseVoice: ('sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09', '7305f7905bfcf77fa0b39388a313f3da35c68d971661a65475b56fb2162c8e63'),
    AsrModel.paraformer: ('sherpa-onnx-paraformer-zh-small-2024-03-09', 'da92b3db5218c5be53aad53e57d1b6e63e7fc98a0e054fbdd6dbe18e9c6b1450'),
  };
  static const _vad = ('silero_vad.onnx', '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6');

  /// 下载地址：GitHub 发布页；国内网络访问 GitHub 很慢或失败时改用 GitHub 下载加速。
  /// 无论从哪里下载，都按官方文件的 SHA-256 校验，一致才使用。
  static const _github = 'https://github.com/k2-fsa/sherpa-onnx/releases/download';
  static const _proxy = 'https://ghfast.top/';

  /// 唤醒模型各文件的 SHA-256。
  static const _kwsSha = {
    'encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx': 'dd784973fc9d2fabb3b800d6dcd20fc3b0ca84f8e2415afe54b032878e447f4d',
    'decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx': 'ed83454004d5bd16d831eaf00adcd181ed7734886aab6ef440f3ffa5aa3cfe3b',
    'joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx': 'f79760052b87239e325f0567c752ad3130b30d92effb847d4307743c20c59a24',
    'tokens.txt': '72316508d9119696145abc6f1f8cdc46287535c34e5ce7e595f845cb1499cf2e',
  };

  static String _sha(String path) => sha256.convert(File(path).readAsBytesSync()).toString();

  static bool _kwsValid(List<String> files) => files.every((f) => File(f).existsSync() && _sha(f) == _kwsSha[f.split('/').last]);

  static Future<String> _root() async => '${(await getApplicationSupportDirectory()).path}/voice';

  static Future<VoiceModelPaths> paths(AsrModel asr) async {
    final root = await _root();
    return VoiceModelPaths(kwsDir: '$root/$_kws', asrDir: '$root/${_asrArchives[asr]!.$1}', vad: '$root/${_vad.$1}', asr: asr);
  }

  static List<String> _kwsFiles(VoiceModelPaths p) => [p.kwsEncoder, p.kwsDecoder, p.kwsJoiner, p.kwsTokens];

  /// 模型是否已经下载完整（识别模型解压完成后写入标记文件；唤醒模型在后台 isolate 中逐个校验）。
  static Future<bool> ready(AsrModel asr) async {
    final p = await paths(asr);
    if (!File('${p.asrDir}/.ok').existsSync() || !File(p.vad).existsSync()) return false;
    if (!_kwsFiles(p).every((f) => File(f).existsSync())) return false;
    return compute(_kwsValid, _kwsFiles(p));
  }

  /// 下载并解压需要的模型。[onProgress] 为 0..1。
  static Future<VoiceModelPaths> download(AsrModel asr, {void Function(double)? onProgress, CancelToken? cancel}) async {
    final p = await paths(asr);
    final root = await _root();
    Directory(root).createSync(recursive: true);
    final tmp = (await getTemporaryDirectory()).path;
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 60)));
    Future<void> fetch(String tag, String file, String dest, double from, double to, {String? sha}) async {
      Object? last;
      for (final url in ['$_github/$tag/$file', '$_proxy$_github/$tag/$file']) {
        try {
          await dio.download(url, '$dest.part', cancelToken: cancel, onReceiveProgress: (r, t) => t > 0 ? onProgress?.call(from + (to - from) * r / t) : null);
          if (sha != null && await compute(_sha, '$dest.part') != sha) throw Exception('模型文件校验失败');
          File('$dest.part').renameSync(dest);
          return;
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) rethrow;
          last = e;
          debugPrint('voice model $file ($url): $e');
        }
      }
      throw Exception('语音模型下载失败，请检查网络后重试（$last）');
    }

    final asrShare = asr == AsrModel.senseVoice ? 0.82 : 0.6;
    // 唤醒模型。
    if (!await compute(_kwsValid, _kwsFiles(p))) {
      final archive = '$tmp/$_kws.tar.bz2';
      await fetch('kws-models', '$_kws.tar.bz2', archive, 0, 0.98 - asrShare);
      await compute(_extract, (archive, p.kwsDir, _kwsSha.keys.toSet()));
      File(archive).deleteSync();
      if (!await compute(_kwsValid, _kwsFiles(p))) throw Exception('唤醒模型校验失败');
    }
    // 语音识别模型。
    if (!File('${p.asrDir}/.ok').existsSync()) {
      final (name, sha) = _asrArchives[asr]!;
      final archive = '$tmp/$name.tar.bz2';
      await fetch('asr-models', '$name.tar.bz2', archive, 0.98 - asrShare, 0.98, sha: sha);
      await compute(_extract, (archive, p.asrDir, const {'model.int8.onnx', 'tokens.txt'}));
      File(archive).deleteSync();
      File('${p.asrDir}/.ok').writeAsStringSync(sha);
    }
    // 语音活动检测。
    if (!File(p.vad).existsSync()) await fetch('asr-models', _vad.$1, p.vad, 0.98, 1, sha: _vad.$2);
    onProgress?.call(1);
    return p;
  }

  /// 从 tar.bz2 中只解出需要的文件（在后台 isolate 中运行）。
  static void _extract((String, String, Set<String>) args) {
    final (archive, dir, wanted) = args;
    final tar = TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(File(archive).readAsBytesSync()));
    Directory(dir).createSync(recursive: true);
    for (final f in tar.files) {
      final base = f.name.split('/').last;
      if (!f.isFile || !wanted.contains(base) || f.name.contains('/test_wavs/')) continue;
      File('$dir/$base').writeAsBytesSync(f.content as List<int>);
    }
  }

  /// 删除已下载的模型。
  static Future<void> delete() async {
    final d = Directory(await _root());
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}
