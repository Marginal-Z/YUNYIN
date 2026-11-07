import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'ui/text.dart';

/// 歌词字体样式。
///
/// 前五种使用各系统自带的字体（没有对应字体的系统自动退回默认字体）；霞鹜文楷在第一次选择时下载
/// （精简版，覆盖常用汉字，约 14 MB），各平台都能使用。
enum LyricFont {
  system('默认', '清晰的无衬线黑体'),
  light('纤细', '细笔画，安静克制'),
  heavy('粗黑', '更粗的笔画，远看也清楚'),
  serif('宋体', '衬线宋体，书卷气'),
  kai('楷体', '手写楷书（系统没有楷体时显示为默认字体）'),
  wenkai('霞鹜文楷', '开源楷体，温润耐看（首次使用需下载约 14 MB）');

  const LyricFont(this.label, this.description);
  final String label;
  final String description;
}

/// 各字体样式的字体族（按平台常见字体名依次回退）。
const _serif = ['Noto Serif CJK SC', 'Noto Serif SC', 'Source Han Serif SC', 'Songti SC', 'STSong', 'SimSun', 'NSimSun', 'serif'];
const _kai = ['Kaiti SC', 'STKaiti', 'KaiTi', 'KaiTi_GB2312', 'AR PL UKai CN', 'LXGW WenKai', LyricFonts.family, 'serif'];

/// 歌词文字样式：在 [ts] 的基础上按所选字体样式替换字体族与字重。[weight] 为默认样式下的字重。
TextStyle lyricTextStyle(LyricFont font, double size, {FontWeight weight = FontWeight.w700, double em = 0, double? height, Color? color}) {
  final base = ts(size, weight: weight, em: em, height: height, color: color);
  return switch (font) {
    LyricFont.system => base,
    LyricFont.light => base.copyWith(fontWeight: FontWeight.w300),
    LyricFont.heavy => base.copyWith(fontWeight: FontWeight.w900),
    LyricFont.serif => base.copyWith(fontFamily: _serif.first, fontFamilyFallback: [..._serif.skip(1), ...kFontFallback], fontWeight: FontWeight.w400),
    LyricFont.kai => base.copyWith(fontFamily: _kai.first, fontFamilyFallback: [..._kai.skip(1), ...kFontFallback], fontWeight: FontWeight.w400),
    LyricFont.wenkai => base.copyWith(fontFamily: LyricFonts.family, fontFamilyFallback: kFontFallback, fontWeight: _soften(weight)),
  };
}

/// 宋体、楷体在多数系统上只有常规字重，请求其他字重时可能匹配不到而退回黑体：固定用常规字重。
/// 霞鹜文楷下载的是 Medium 字重：较粗的字重统一用它，避免合成加粗让笔画糊在一起。
FontWeight _soften(FontWeight w) => w.value >= 600 ? FontWeight.w500 : w;

/// 霞鹜文楷的下载与载入。
class LyricFonts extends ChangeNotifier {
  LyricFonts._();

  static final instance = LyricFonts._();

  static const family = 'LXGW WenKai Lite';
  static const _file = 'LXGWWenKaiLite-Medium.ttf';

  /// 下载地址：霞鹜文楷精简版在 GitHub 上的官方发布文件。
  static const _urls = ['https://github.com/lxgw/LxgwWenKai-Lite/releases/download/v1.530/$_file'];

  bool loaded = false;

  /// 下载进度（0–1）；没有在下载时为 null。
  double? progress;
  String? error;

  Future<File> _path() async => File('${(await getApplicationSupportDirectory()).path}/fonts/$_file');

  /// 本机已下载的字体文件（桌面歌词窗口按路径自行载入）。
  String? filePath;

  /// 启动时载入已下载的字体。
  Future<void> init() async {
    if (kIsWeb) return;
    try {
      final f = await _path();
      if (await f.exists()) await _load(f);
    } catch (e) {
      debugPrint('lyric font: $e');
    }
  }

  Future<void> _load(File f) async {
    await loadFontFile(family, f.path);
    filePath = f.path;
    loaded = true;
    notifyListeners();
  }

  /// 下载并载入霞鹜文楷；已载入或正在下载时直接返回。
  Future<void> download() async {
    if (loaded || progress != null || kIsWeb) return;
    progress = 0;
    error = null;
    notifyListeners();
    final f = await _path();
    await f.parent.create(recursive: true);
    final part = File('${f.path}.part');
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(minutes: 3)));
    Object? last;
    try {
      for (final url in _urls) {
        try {
          await dio.download(url, part.path, onReceiveProgress: (r, t) {
            if (t > 0) {
              progress = r / t;
              notifyListeners();
            }
          });
          // 字体文件以 TrueType 标识开头，且大小合理：避免把错误页当成字体。
          final head = await part.openRead(0, 4).first;
          if (await part.length() < 1000000 || !(head[0] == 0 && head[1] == 1 && head[2] == 0 && head[3] == 0)) throw const FormatException('下载的文件不是字体');
          await part.rename(f.path);
          progress = null;
          await _load(f);
          return;
        } catch (e) {
          last = e;
          debugPrint('lyric font $url: $e');
        }
      }
      throw Exception('下载霞鹜文楷失败：$last');
    } catch (e) {
      error = '$e'.replaceFirst('Exception: ', '');
      progress = null;
      notifyListeners();
      rethrow;
    } finally {
      dio.close();
      if (await part.exists()) await part.delete().catchError((Object _) => part);
    }
  }
}

/// 从文件载入字体（同一字体族只载入一次）。
final _loadedFiles = <String>{};

Future<void> loadFontFile(String family, String path) async {
  if (!_loadedFiles.add('$family|$path')) return;
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}
