import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'voice_engine.dart';

/// 离线语音模型（sherpa-onnx 官方发布）：唤醒词检测约 5 MB，中文流式识别约 26 MB。
/// 第一次打开语音功能时下载并解压到应用数据目录，不随安装包分发（不用语音的用户不增加体积）。
class VoiceModelStore {
  static const _kws = 'sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01';
  static const _asr = 'sherpa-onnx-streaming-zipformer-small-ctc-zh-int8-2025-04-01';

  /// 下载地址：GitHub 发布页；国内网络访问 GitHub 很慢或失败时依次改用 GitHub 下载加速与 Hugging Face 镜像。
  /// 无论从哪里下载，每个文件都按下面的 SHA-256 校验，与官方发布的文件一致才使用。
  static const _github = 'https://github.com/k2-fsa/sherpa-onnx/releases/download';
  static const _proxy = 'https://ghfast.top/';
  static const _mirror = 'https://hf-mirror.com/csukuangfj';

  /// 官方发布文件的 SHA-256。
  static const _sha256 = {
    'encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx': 'dd784973fc9d2fabb3b800d6dcd20fc3b0ca84f8e2415afe54b032878e447f4d',
    'decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx': 'ed83454004d5bd16d831eaf00adcd181ed7734886aab6ef440f3ffa5aa3cfe3b',
    'joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx': 'f79760052b87239e325f0567c752ad3130b30d92effb847d4307743c20c59a24',
    '$_kws/tokens.txt': '72316508d9119696145abc6f1f8cdc46287535c34e5ce7e595f845cb1499cf2e',
    'model.int8.onnx': '68c9c943840f7d9cf3e8a4970ba50f404feb5277f611fa82b7e72267786fa84a',
    '$_asr/tokens.txt': '6fed8c6c248516f38e7faa19404b57413e8ce259f1cbc1fa4aebc86eac32fdfd',
  };

  static String _expected(String path) {
    final base = path.split('/').last;
    if (base == 'tokens.txt') return _sha256[path.contains(_kws) ? '$_kws/tokens.txt' : '$_asr/tokens.txt']!;
    return _sha256[base]!;
  }

  static bool _valid(String path) {
    final f = File(path);
    return f.existsSync() && sha256.convert(f.readAsBytesSync()).toString() == _expected(path);
  }

  /// 在后台 isolate 中校验（[compute] 只传静态函数与路径列表：用闭包时会连同所在作用域里的其他变量
  /// 一起发送，例如进度回调引用的播放器，无法发送到其他 isolate）。
  static Future<bool> _allValid(List<String> files) => compute(_checkAll, files);

  static bool _checkAll(List<String> files) => files.every(_valid);

  static Future<String> _root() async => '${(await getApplicationSupportDirectory()).path}/voice';

  static Future<VoiceModelPaths> paths() async {
    final root = await _root();
    return VoiceModelPaths(kwsDir: '$root/$_kws', asrDir: '$root/$_asr');
  }

  /// 模型是否已经下载完整（校验在后台 isolate 中进行）。
  static Future<bool> ready() async {
    final p = await paths();
    if (!p.files.every((f) => File(f).existsSync())) return false;
    return _allValid(p.files);
  }

  /// 下载并解压两个模型。[onProgress] 为 0..1。
  static Future<VoiceModelPaths> download({void Function(double)? onProgress, CancelToken? cancel}) async {
    final p = await paths();
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 60)));
    final parts = [
      (_kws, 'kws-models', p.kwsDir, [p.kwsEncoder, p.kwsDecoder, p.kwsJoiner, p.kwsTokens], 0.0, 0.25),
      (_asr, 'asr-models', p.asrDir, [p.asrModel, p.asrTokens], 0.25, 1.0),
    ];
    Object? lastError;
    for (final (name, tag, dir, files, from, to) in parts) {
      if (await _allValid(files)) continue;
      void progress(double f) => onProgress?.call(from + (to - from) * f);
      var done = false;
      // GitHub 发布页与下载加速：整个压缩包下载后只解出需要的文件。
      for (final base in ['$_github/$tag/$name.tar.bz2', '$_proxy$_github/$tag/$name.tar.bz2']) {
        try {
          final archive = '${(await getTemporaryDirectory()).path}/$name.tar.bz2';
          await dio.download(base, archive, cancelToken: cancel, onReceiveProgress: (r, t) => t > 0 ? progress(r / t * 0.9) : null);
          final wanted = files.map((f) => f.split('/').last).toSet();
          await compute(_extract, (archive, dir, wanted));
          File(archive).deleteSync();
          if (await _allValid(files)) {
            done = true;
            break;
          }
          lastError = Exception('模型文件校验失败');
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) rethrow;
          lastError = e;
          debugPrint('voice model $name ($base): $e');
        }
      }
      // Hugging Face 镜像（只有语音识别模型）：逐个下载需要的文件。
      if (!done && tag == 'asr-models') {
        try {
          Directory(dir).createSync(recursive: true);
          for (var i = 0; i < files.length; i++) {
            final f = files[i];
            await dio.download(
              '$_mirror/$name/resolve/main/${f.split('/').last}',
              '$f.part',
              cancelToken: cancel,
              onReceiveProgress: (r, t) => t > 0 ? progress((i + r / t) / files.length) : null,
            );
            File('$f.part').renameSync(f);
          }
          done = await _allValid(files);
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) rethrow;
          lastError = e;
        }
      }
      if (!done) throw Exception('语音模型下载失败，请检查网络后重试（$lastError）');
      progress(1);
    }
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
