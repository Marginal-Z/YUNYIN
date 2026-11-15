import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// MOSS-TTS-Nano 的模型文件（OpenMOSS 官方发布，Apache-2.0）：语音模型约 670 MB、声音解码器约 45 MB。
///
/// 不随安装包分发：在音色中心确认后下载到应用数据目录。优先从魔搭社区（ModelScope，国内直连）下载，
/// 失败时依次换 Hugging Face 镜像与 Hugging Face；断点续传，每个文件按官方公布的 SHA-256 校验，一致才使用。
abstract final class MossModels {
  static const tts = 'MOSS-TTS-Nano-100M-ONNX';
  static const codec = 'MOSS-Audio-Tokenizer-Nano-ONNX';

  /// (仓库, 文件, 大小, SHA-256)。只下载推理用到的文件（不含参考音频编码器与另外两种本地解码图）。
  static const files = [
    (tts, 'browser_poc_manifest.json', 470720, '803716e58b71fe2a770af1495ca74797d38c181b41cfeeaf9e524adc15910a20'),
    (tts, 'tts_browser_onnx_meta.json', 4302, '1dacbf4d59732ae1fb1253139b70a4ca07415246fb6473919c9947d489a59e04'),
    (tts, 'tokenizer.model', 470897, 'c353ee1479b536bf414c1b247f5542b6607fb8ae91320e5af1781fee200fddff'),
    (tts, 'moss_tts_prefill.onnx', 283305, 'd56126dcd0574c2f15d98fc6b35eda68d0386b5bd9c5e38e28548d6f2ea8f3db'),
    (tts, 'moss_tts_decode_step.onnx', 291483, '698cbc2fc1c2feca16e5895614ed52bbb32ded10f236c076f477b2e69abf32d8'),
    (tts, 'moss_tts_local_fixed_sampled_frame.onnx', 471262, '40cdb00efc171c450cf91468e01429caa41b0252222cd308e978f58fe354afa8'),
    (tts, 'moss_tts_global_shared.data', 440813568, 'bce8312c3df6a44545302cae229b61054fe0672e0b252ba59cba47adeed831dc'),
    (tts, 'moss_tts_local_shared.data', 229678080, 'bae7782032c0fb12490ab42afe009f87ae6c75a0f0596fc7b5c08e4d5ee93916'),
    (codec, 'codec_browser_onnx_meta.json', 16461, 'c40eb144a4f50453ac0437944cbdeee1467845b886e90197ff1eada1353303db'),
    (codec, 'moss_audio_tokenizer_decode_full.onnx', 681902, '0fbbafe3fd4afa2a019af5c5ced204af6e2d1db044fa40f021525d2aee95b4ac'),
    (codec, 'moss_audio_tokenizer_decode_shared.data', 44198912, 'e69d52e0f4e84ca27850557ee54face46632d3a5a16c89bd246c7c408466dcad'),
  ];

  static int get totalBytes => files.fold(0, (s, f) => s + f.$3);

  /// 下载地址（按顺序尝试）。
  static List<String> _urls(String repo, String file) => [
    'https://modelscope.cn/models/openmoss/$repo/resolve/master/$file',
    'https://hf-mirror.com/OpenMOSS-Team/$repo/resolve/main/$file',
    'https://huggingface.co/OpenMOSS-Team/$repo/resolve/main/$file',
  ];

  static Future<String> dir() async => '${(await getApplicationSupportDirectory()).path}/moss';

  /// 这台设备能否运行：只支持 Android（64 位），并且内存不少于 6 GB（模型加载后约占 1 GB 内存）。
  static Future<bool> supported() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final m = await const MethodChannel('yunyin/moss').invokeMapMethod<String, Object?>('memory');
      final total = (m?['total'] as num?)?.toInt() ?? 0;
      return total >= 5500 << 20;
    } catch (_) {
      return false;
    }
  }

  /// 是否已经下载完整（下载完成后写入的标记文件，记录各文件的 SHA-256）。
  static Future<bool> ready() async {
    if (kIsWeb) return false;
    final d = await dir();
    final ok = File('$d/.ok');
    if (!ok.existsSync() || ok.readAsStringSync() != _stamp) return false;
    return files.every((f) => File('$d/${f.$1}/${f.$2}').existsSync() && File('$d/${f.$1}/${f.$2}').lengthSync() == f.$3);
  }

  static String get _stamp => files.map((f) => f.$4).join(',');

  /// 已下载（含未完成）的大小。
  static Future<int> downloadedBytes() async {
    final d = await dir();
    var n = 0;
    for (final f in files) {
      for (final p in ['$d/${f.$1}/${f.$2}', '$d/${f.$1}/${f.$2}.part']) {
        final file = File(p);
        if (file.existsSync()) n += file.lengthSync();
      }
    }
    return n;
  }

  /// 分块读取计算 SHA-256（文件有几百 MB，不整个读进内存）。
  static Future<String> _sha(String path) async => (await sha256.bind(File(path).openRead()).first).toString();

  /// 下载全部文件。[onProgress] 为 0..1；可以通过 [cancel] 取消，下次从断点继续。
  static Future<void> download({void Function(double progress)? onProgress, CancelToken? cancel}) async {
    final d = await dir();
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 60)));
    final total = totalBytes;
    var done = 0;
    for (final (repo, file, size, sha) in files) {
      final dest = File('$d/$repo/$file');
      dest.parent.createSync(recursive: true);
      if (dest.existsSync() && dest.lengthSync() == size) {
        done += size;
        onProgress?.call(done / total);
        continue;
      }
      Object? last;
      var ok = false;
      for (final url in _urls(repo, file)) {
        final part = File('${dest.path}.part');
        try {
          for (var attempt = 0; attempt < 3 && !ok; attempt++) {
            final have = part.existsSync() ? part.lengthSync() : 0;
            if (have > size) part.deleteSync();
            if (have < size) await fetch(dio, url, part, have, cancel, (r) => onProgress?.call((done + r) / total));
            if (part.lengthSync() != size) {
              // 连接中断：下一次从断点继续；比应有的大（不应出现）就删掉重下。
              if (part.lengthSync() > size) part.deleteSync();
              continue;
            }
            if (await compute(_sha, part.path) != sha) {
              part.deleteSync();
              throw Exception('$file 校验失败');
            }
            part.renameSync(dest.path);
            ok = true;
          }
          if (ok) break;
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) rethrow;
          last = e;
          debugPrint('moss model $file ($url): $e');
        }
      }
      if (!ok) throw Exception('语音模型下载失败，请检查网络后重试（$last）');
      done += size;
      onProgress?.call(done / total);
    }
    File('$d/.ok').writeAsStringSync(_stamp);
  }

  /// 下载一个文件到 [part]：已有 [have] 字节时请求从断点继续。服务器不支持续传（返回 200 与完整文件）时从头写入，
  /// 不会把整个文件接在已下载的部分后面。[onBytes] 为这个文件已写入的总字节数。
  @visibleForTesting
  static Future<void> fetch(Dio dio, String url, File part, int have, CancelToken? cancel, void Function(int bytes) onBytes) async {
    final res = await dio.get<ResponseBody>(
      url,
      cancelToken: cancel,
      options: Options(responseType: ResponseType.stream, headers: {if (have > 0) 'range': 'bytes=$have-'}),
    );
    final resumed = have > 0 && res.statusCode == 206;
    final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    var written = resumed ? have : 0;
    try {
      await for (final chunk in res.data!.stream) {
        if (cancel?.isCancelled ?? false) break;
        sink.add(chunk);
        written += chunk.length;
        onBytes(written);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (cancel?.isCancelled ?? false) throw DioException.requestCancelled(requestOptions: res.requestOptions, reason: 'cancelled');
  }

  /// 删除模型（释放约 720 MB）。
  static Future<void> delete() async {
    try {
      await const MethodChannel('yunyin/moss').invokeMethod<void>('release');
    } catch (_) {}
    final d = Directory(await dir());
    if (d.existsSync()) await d.delete(recursive: true);
  }
}

/// 模型下载的进度（离开音色中心后继续在后台下载）。
class MossDownload extends ChangeNotifier {
  MossDownload._();

  static final instance = MossDownload._();

  /// 下载中时为 0..1。
  double? progress;
  String? error;
  CancelToken? _cancel;

  bool get running => progress != null;

  Future<void> start() async {
    if (running) return;
    error = null;
    progress = 0;
    final cancel = _cancel = CancelToken();
    notifyListeners();
    try {
      await MossModels.download(cancel: cancel, onProgress: (p) {
        // 进度变化 0.5% 以上才刷新界面。
        if ((p - (progress ?? 0)).abs() >= 0.005 || p >= 1) {
          progress = p;
          notifyListeners();
        }
      });
    } catch (e) {
      if (!(e is DioException && CancelToken.isCancel(e))) error = '$e'.replaceFirst('Exception: ', '');
    } finally {
      progress = null;
      _cancel = null;
      notifyListeners();
    }
  }

  void cancel() => _cancel?.cancel();
}
