import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 问题诊断的日志与报告。
///
/// 只在内存中保留最近 400 行应用日志与未捕获的错误，不写文件、不在后台监测流畅度或做任何自动诊断；
/// 用户在“问题诊断”页面点“开始诊断”时才逐项检查（见 diagnostics_page.dart），结果连同这些日志可以导出。
class Diagnostics {
  Diagnostics._();

  static final instance = Diagnostics._();

  static const _channel = MethodChannel('yunyin/diagnostics');
  static const _keepLines = 400;

  final DateTime started = DateTime.now();

  /// 最近的日志。
  final List<String> recent = [];
  int errors = 0;
  bool _installed = false;

  void install() {
    if (_installed) return;
    _installed = true;
    final print = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      print(message, wrapWidth: wrapWidth);
      if (message != null) log(message);
    };
    final onFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      onFlutterError?.call(details);
      error(details.exception, details.stack, context: details.context?.toDescription());
    };
    final dispatcher = ui.PlatformDispatcher.instance;
    final onPlatformError = dispatcher.onError;
    dispatcher.onError = (e, stack) {
      error(e, stack);
      return onPlatformError?.call(e, stack) ?? false;
    };
  }

  static String _platform() => kIsWeb ? 'web' : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

  static String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }

  /// 记一行日志（I 普通，E 错误）。
  void log(String message, {String level = 'I'}) {
    recent.add('${_time(DateTime.now())} $level $message');
    if (recent.length > _keepLines) recent.removeRange(0, recent.length - _keepLines);
  }

  void error(Object e, StackTrace? stack, {String? context}) {
    errors++;
    final trace = stack == null ? '' : '\n${stack.toString().split('\n').take(12).join('\n')}';
    log('${context == null ? '' : '$context：'}$e$trace', level: 'E');
  }

  /// Android 原生信息：设备、存储空间、权限（其他平台返回空）。
  static Future<Map<String, Object?>> native(String method) async {
    if (kIsWeb || !Platform.isAndroid) return const {};
    try {
      return await _channel.invokeMapMethod<String, Object?>(method) ?? const {};
    } catch (_) {
      return const {};
    }
  }

  /// 设备、系统与运行状态摘要（不含账号信息）。
  Future<String> summary() async {
    final b = StringBuffer();
    final info = await PackageInfo.fromPlatform().then<PackageInfo?>((i) => i, onError: (_) => null);
    b.writeln('云音 ${info == null ? '' : 'v${info.version}+${info.buildNumber}'}');
    b.writeln('系统：${_platform()}');
    if (!kIsWeb && Platform.isAndroid) {
      final d = await native('device');
      if (d.isNotEmpty) b.writeln('设备：${d['manufacturer']} ${d['model']}（${d['hardware']}，Android ${d['release']} / API ${d['sdk']}）');
    }
    final view = ui.PlatformDispatcher.instance.views.firstOrNull;
    if (view != null) {
      final size = view.physicalSize;
      b.writeln('屏幕：${size.width.toInt()}×${size.height.toInt()}，${view.devicePixelRatio.toStringAsFixed(2)}x，${view.display.refreshRate.toStringAsFixed(0)} Hz');
    }
    final up = DateTime.now().difference(started);
    b.writeln('本次运行：${up.inMinutes} 分 ${up.inSeconds % 60} 秒');
    b.writeln('错误：$errors');
    return b.toString();
  }

  /// Android 11 起系统记录的最近几次退出原因（崩溃、无响应、被系统结束等）。
  static Future<List<Map<Object?, Object?>>> exitReasons() async {
    if (kIsWeb || !Platform.isAndroid) return const [];
    try {
      return await _channel.invokeListMethod<Map<Object?, Object?>>('exitReasons') ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static String describeExit(Map<Object?, Object?> r) {
    final time = DateTime.fromMillisecondsSinceEpoch((r['time'] as num?)?.toInt() ?? 0);
    return '${_time(time)} ${r['reason']}（${r['status']}，${r['importance']}）${r['description'] ?? ''}';
  }

  Future<String> _exitReasons() async {
    if (kIsWeb || !Platform.isAndroid) return '';
    final list = await exitReasons();
    if (list.isEmpty) return '';
    final b = StringBuffer('==== 最近的退出记录 ====\n');
    for (final r in list) {
      b.writeln(describeExit(r));
      final trace = r['trace'] as String?;
      if (trace != null && trace.isNotEmpty) b.writeln(trace);
    }
    return b.toString();
  }

  /// 本进程的系统日志（Android 应用只能读取自己的日志）。
  Future<String> _logcat() async {
    if (kIsWeb || !Platform.isAndroid) return '';
    try {
      final r = await Process.run('logcat', ['-d', '-t', '3000', '--pid=$pid']);
      final text = '${r.stdout}';
      return text.trim().isEmpty ? '' : '==== 系统日志（本进程）====\n$text';
    } catch (_) {
      return '';
    }
  }

  /// 去掉日志中的登录凭据与密钥。
  @visibleForTesting
  static String redact(String text) => text
      .replaceAllMapped(RegExp(r'(Bearer\s+)[\w.\-]+', caseSensitive: false), (m) => '${m[1]}***')
      .replaceAllMapped(_secretField, (m) => '${m[1]}${m[2]}***')
      .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_\-]{8,}'), 'sk-***');

  /// 名字里含有这些词的字段（csrf_token、kg_dfid、qqmusic_key…），以及几个容易误伤、必须完全一致的短字段名。
  static final _secretField = RegExp(
    r'(\b(?:[\w\-]*(?:cookie|token|secret|passw|pwd|key|csrf|music_[ua]|dfid|psrf|auth)[\w\-]*|t|uin|mid|sign|kugoo)\s*[=:]\s*)("?)[^\s"&;,]+',
    caseSensitive: false,
  );

  /// 完整的诊断报告：各项检查的结果（[results]）、设备摘要、退出记录、最近的应用日志与本进程系统日志，已去掉凭据。
  Future<String> report(String results) async {
    final b = StringBuffer('==== 云音问题诊断 ${_time(DateTime.now())} ====\n')
      ..writeln(await summary())
      ..writeln('==== 检查结果 ====')
      ..writeln(results.trim())
      ..writeln();
    b.write(await _exitReasons());
    b.writeln('==== 云音日志（最近 ${recent.length} 行）====');
    b.writeln(recent.join('\n'));
    b.write(await _logcat());
    return redact(b.toString());
  }

  /// 导出报告：Android 打开系统分享面板，桌面端保存到下载目录。返回给用户的提示（分享成功时为空）。
  Future<String> export(String results) async {
    final text = await report(results);
    final stamp = _time(DateTime.now()).replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final name = 'yunyin-diagnostics-$stamp.txt';
    if (!kIsWeb && Platform.isAndroid) {
      // Android 的 FileProvider 只开放缓存目录中的 yunyin-share。
      final dir = Directory('${(await getTemporaryDirectory()).path}/yunyin-share');
      await dir.create(recursive: true);
      final file = File('${dir.path}/$name');
      await file.writeAsString(text, flush: true);
      final ok = await _channel.invokeMethod<bool>('shareFile', {'path': file.path});
      if (ok == true) return '';
      throw Exception('没有可以分享文件的应用');
    }
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(text, flush: true);
    return '已保存到 ${file.path}';
  }
}
