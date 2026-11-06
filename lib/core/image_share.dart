import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 把界面上的一块区域（[RepaintBoundary]）导出为 PNG。[pixelRatio] 为 3 时 360 宽的海报导出为 1080 宽。
Future<Uint8List> captureBoundary(RenderRepaintBoundary boundary, {double pixelRatio = 3}) async {
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw Exception('生成图片失败');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

const _channel = MethodChannel('yunyin/share');

/// 写到缓存目录的 yunyin-share 中（Android 的 FileProvider 只开放这个目录）。
Future<File> _temp(Uint8List png, String name) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/yunyin-share');
  await dir.create(recursive: true);
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(png, flush: true);
  return file;
}

/// 分享图片。Android 打开系统分享面板；其他平台没有系统分享，保存到下载目录并返回提示文字。
Future<String> shareImage(Uint8List png, {required String name, String text = ''}) async {
  if (!kIsWeb && Platform.isAndroid) {
    final file = await _temp(png, name);
    final ok = await _channel.invokeMethod<bool>('shareImage', {'path': file.path, 'text': text});
    if (ok == true) return '';
    throw Exception('没有可以分享图片的应用');
  }
  return saveImage(png, name: name);
}

/// 保存图片：Android 保存到相册（Pictures/云音），桌面端保存到下载目录。返回给用户的提示。
Future<String> saveImage(Uint8List png, {required String name}) async {
  if (!kIsWeb && Platform.isAndroid) {
    final file = await _temp(png, name);
    final ok = await _channel.invokeMethod<bool>('saveImage', {'path': file.path, 'name': name});
    if (ok == true) return '已保存到相册（Pictures/云音）';
    throw Exception('保存到相册失败，请使用“分享”');
  }
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {}
  dir ??= await getApplicationDocumentsDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(png, flush: true);
  return '已保存到 ${file.path}';
}
