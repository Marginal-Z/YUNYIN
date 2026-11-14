import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 问题诊断：把应用日志（debugPrint）、未捕获的错误和卡顿写进本机的日志文件，反馈问题时由用户导出。
///
/// 日志只保存在本机（应用数据目录 logs/，当前与上一个文件各最多 1 MB），不会自动上传。导出时去掉 Cookie、
/// 密钥等登录凭据。卡顿只统计帧耗时（系统每批回调一次，开销可以忽略），每 10 秒汇总写一行。
class Diagnostics {
  Diagnostics._();

  static final instance = Diagnostics._();

  static const _channel = MethodChannel('yunyin/diagnostics');
  static const _maxBytes = 1 << 20;
  static const _keepLines = 400;

  final DateTime started = DateTime.now();

  /// 最近的日志（页面上显示）。
  final List<String> recent = [];

  /// 本次运行的帧统计：总帧数、超出一帧预算 1.5 倍的慢帧数、最慢一帧（毫秒）。
  int frames = 0, slowFrames = 0;
  double worstFrameMs = 0;
  int errors = 0;

  String? _dir;
  IOSink? _sink;
  int _size = 0;
  bool _installed = false;

  // 当前 10 秒窗口内的慢帧。
  int _windowSlow = 0;
  double _windowWorst = 0;
  String _windowWorstDetail = '';

  Future<void> install() async {
    if (_installed) return;
    _installed = true;
    try {
      _dir = '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}logs';
      await Directory(_dir!).create(recursive: true);
      final file = File(_path(0));
      _size = file.existsSync() ? file.lengthSync() : 0;
      _sink = file.openWrite(mode: FileMode.append);
    } catch (e) {
      _dir = null;
    }
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
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    Timer.periodic(const Duration(seconds: 10), (_) => _flushWindow());
    final info = await PackageInfo.fromPlatform().then((i) => 'v${i.version}+${i.buildNumber}', onError: (_) => '');
    log('—— 云音启动 $info · ${_platform()} ——');
  }

  String _path(int i) => '$_dir${Platform.pathSeparator}${i == 0 ? 'yunyin.log' : 'yunyin.$i.log'}';

  static String _platform() => kIsWeb ? 'web' : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

  static String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }

  /// 写一行日志（I 普通，W 卡顿，E 错误）。
  void log(String message, {String level = 'I'}) {
    final line = '${_time(DateTime.now())} $level $message';
    recent.add(line);
    if (recent.length > _keepLines) recent.removeRange(0, recent.length - _keepLines);
    final sink = _sink;
    if (sink != null) {
      sink.writeln(line);
      _size += line.length + 1;
      if (_size > _maxBytes) _rotate();
    }
  }

  void error(Object e, StackTrace? stack, {String? context}) {
    errors++;
    final trace = stack == null ? '' : '\n${stack.toString().split('\n').take(12).join('\n')}';
    log('${context == null ? '' : '$context：'}$e$trace', level: 'E');
  }

  /// 当前文件写满后改名为 yunyin.1.log，重新开一个文件。
  void _rotate() {
    final old = _sink;
    _sink = null;
    _size = 0;
    unawaited(() async {
      try {
        await old?.flush();
        await old?.close();
        final prev = File(_path(1));
        if (prev.existsSync()) await prev.delete();
        await File(_path(0)).rename(_path(1));
        _sink = File(_path(0)).openWrite(mode: FileMode.append);
      } catch (_) {}
    }());
  }

  double get _budget {
    final rate = ui.PlatformDispatcher.instance.views.firstOrNull?.display.refreshRate ?? 60;
    return 1000 / (rate <= 0 ? 60 : rate);
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    final budget = _budget;
    for (final t in timings) {
      frames++;
      final total = t.totalSpan.inMicroseconds / 1000;
      if (total <= budget * 1.5) continue;
      slowFrames++;
      _windowSlow++;
      if (total > worstFrameMs) worstFrameMs = total;
      if (total > _windowWorst) {
        _windowWorst = total;
        String ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1);
        _windowWorstDetail = '构建 ${ms(t.buildDuration)}ms，渲染 ${ms(t.rasterDuration)}ms，排队 ${ms(t.vsyncOverhead)}ms';
      }
    }
  }

  void _flushWindow() {
    if (_windowSlow > 0) {
      log('卡顿：10 秒内 $_windowSlow 个慢帧，最慢 ${_windowWorst.toStringAsFixed(1)}ms（$_windowWorstDetail）', level: 'W');
    }
    _windowSlow = 0;
    _windowWorst = 0;
    unawaited(_sink?.flush().catchError((_) {}));
  }

  /// 设备、系统与运行状态摘要（不含账号信息）。
  Future<String> summary() async {
    final b = StringBuffer();
    final info = await PackageInfo.fromPlatform().then<PackageInfo?>((i) => i, onError: (_) => null);
    b.writeln('云音 ${info == null ? '' : 'v${info.version}+${info.buildNumber}'}');
    b.writeln('系统：${_platform()}');
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final d = await _channel.invokeMapMethod<String, Object?>('device');
        if (d != null) b.writeln('设备：${d['manufacturer']} ${d['model']}（${d['hardware']}，Android ${d['release']} / API ${d['sdk']}）');
      } catch (_) {}
    }
    final view = ui.PlatformDispatcher.instance.views.firstOrNull;
    if (view != null) {
      final size = view.physicalSize;
      b.writeln('屏幕：${size.width.toInt()}×${size.height.toInt()}，${view.devicePixelRatio.toStringAsFixed(2)}x，${view.display.refreshRate.toStringAsFixed(0)} Hz');
    }
    final up = DateTime.now().difference(started);
    b.writeln('本次运行：${up.inMinutes} 分 ${up.inSeconds % 60} 秒');
    b.writeln('帧：$frames，慢帧 $slowFrames（${frames == 0 ? 0 : (slowFrames * 100 / frames).toStringAsFixed(1)}%），最慢 ${worstFrameMs.toStringAsFixed(1)}ms');
    b.writeln('错误：$errors');
    return b.toString();
  }

  /// Android 11 起系统记录的最近几次退出原因（崩溃、无响应、被系统结束等）。
  Future<String> _exitReasons() async {
    if (kIsWeb || !Platform.isAndroid) return '';
    try {
      final list = await _channel.invokeListMethod<Map<Object?, Object?>>('exitReasons') ?? const [];
      if (list.isEmpty) return '';
      final b = StringBuffer('==== 最近的退出记录 ====\n');
      for (final r in list) {
        final time = DateTime.fromMillisecondsSinceEpoch((r['time'] as num?)?.toInt() ?? 0);
        b.writeln('${_time(time)} ${r['reason']}（${r['status']}，${r['importance']}）${r['description'] ?? ''}');
        final trace = r['trace'] as String?;
        if (trace != null && trace.isNotEmpty) b.writeln(trace);
      }
      return b.toString();
    } catch (e) {
      return '';
    }
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

  /// 完整的诊断报告：摘要、退出记录、云音日志（上一个与当前文件）、本进程系统日志，已去掉凭据。
  Future<String> report() async {
    await _sink?.flush().catchError((_) {});
    final b = StringBuffer('==== 云音问题诊断 ${_time(DateTime.now())} ====\n')..writeln(await summary());
    b.write(await _exitReasons());
    b.writeln('==== 云音日志 ====');
    var wrote = false;
    if (_dir != null) {
      for (final i in [1, 0]) {
        final f = File(_path(i));
        if (f.existsSync()) {
          b.write(await f.readAsString().catchError((_) => ''));
          wrote = true;
        }
      }
    }
    if (!wrote) b.writeln(recent.join('\n'));
    b.write(await _logcat());
    return redact(b.toString());
  }

  /// 导出报告：Android 打开系统分享面板，桌面端保存到下载目录。返回给用户的提示（分享成功时为空）。
  Future<String> export() async {
    final text = await report();
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

  /// 清空日志文件与本次的统计。
  Future<void> clear() async {
    recent.clear();
    frames = slowFrames = errors = 0;
    worstFrameMs = 0;
    if (_dir != null) {
      final old = _sink;
      _sink = null;
      await old?.close().catchError((_) {});
      for (final i in [0, 1]) {
        final f = File(_path(i));
        if (f.existsSync()) await f.delete().catchError((_) => f);
      }
      _size = 0;
      _sink = File(_path(0)).openWrite(mode: FileMode.append);
    }
  }
}
