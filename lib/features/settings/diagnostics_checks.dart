import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/widgets.dart';

import '../../assistant/assistant_settings.dart';
import '../../assistant/voice_models.dart';
import '../../core/diagnostics.dart';
import '../../core/settings.dart';
import '../../core/ui/adaptive_scale.dart';
import '../../data/sources/source_manager.dart';
import '../../player/player_controller.dart';
import '../../voice/engines/local_engine.dart';
import '../../voice/tts_types.dart';
import '../../voice/voice_library.dart';
import '../../voice/voice_settings.dart';
import '../../voice/wav.dart';

enum CheckStatus { ok, warn, fail, info }

/// 一项检查的结果：一句结论加若干行细节。
class CheckResult {
  const CheckResult(this.status, this.summary, [this.details = const []]);

  final CheckStatus status;
  final String summary;
  final List<String> details;
}

/// 一项检查。[run] 只在用户点“开始诊断”时执行。
class DiagnosticCheck {
  const DiagnosticCheck(this.title, this.run);

  final String title;
  final Future<CheckResult> Function(BuildContext context, DiagnosticsHooks hooks) run;
}

/// 检查需要页面配合的地方：流畅度测试期间页面播放一段动画。
class DiagnosticsHooks {
  DiagnosticsHooks({required this.setAnimating});

  final void Function(bool on) setAnimating;
}

String _mb(num bytes) => bytes >= 1 << 30 ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB' : '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';

/// 全部检查，按顺序执行。
final List<DiagnosticCheck> diagnosticChecks = [
  DiagnosticCheck('设备与系统', (context, _) async {
    final view = ui.PlatformDispatcher.instance.views.firstOrNull;
    final scale = AdaptiveScale.of(context);
    final device = await Diagnostics.native('device');
    return CheckResult(CheckStatus.info, device.isEmpty ? (kIsWeb ? 'Web' : Platform.operatingSystem) : '${device['manufacturer']} ${device['model']}', [
      if (!kIsWeb) '系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      if (device.isNotEmpty) '芯片：${device['hardware']}，Android ${device['release']}（API ${device['sdk']}）',
      if (view != null) '屏幕：${view.physicalSize.width.toInt()}×${view.physicalSize.height.toInt()}，${view.devicePixelRatio.toStringAsFixed(2)} 倍，${view.display.refreshRate.toStringAsFixed(0)} Hz',
      '界面缩放：${scale.toStringAsFixed(3)}${scale == 1 ? '（按 1:1 渲染）' : ''}',
    ]);
  }),
  DiagnosticCheck('流畅度（3 秒渲染测试）', (context, hooks) async {
    final rate = ui.PlatformDispatcher.instance.views.firstOrNull?.display.refreshRate ?? 60;
    final budget = 1000 / (rate <= 0 ? 60 : rate);
    final timings = <ui.FrameTiming>[];
    void collect(List<ui.FrameTiming> t) => timings.addAll(t);
    hooks.setAnimating(true);
    // 先让动画跑起来再开始计时。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    SchedulerBinding.instance.addTimingsCallback(collect);
    final sw = Stopwatch()..start();
    await Future<void>.delayed(const Duration(seconds: 3));
    sw.stop();
    SchedulerBinding.instance.removeTimingsCallback(collect);
    hooks.setAnimating(false);
    if (timings.isEmpty) return const CheckResult(CheckStatus.warn, '没有收到帧数据');
    final fps = timings.length / (sw.elapsedMilliseconds / 1000);
    final ms = [for (final t in timings) t.totalSpan.inMicroseconds / 1000]..sort();
    double pct(double p) => ms[math.min(ms.length - 1, (ms.length * p).floor())];
    final slow = ms.where((v) => v > budget * 1.5).length;
    final build = timings.map((t) => t.buildDuration.inMicroseconds / 1000).reduce(math.max);
    final raster = timings.map((t) => t.rasterDuration.inMicroseconds / 1000).reduce(math.max);
    final linuxCap = !kIsWeb && Platform.isLinux && rate > 61;
    final status = fps >= rate * 0.9 && slow <= timings.length * 0.02
        ? CheckStatus.ok
        : (linuxCap && fps >= 57 ? CheckStatus.warn : (fps >= rate * 0.75 ? CheckStatus.warn : CheckStatus.fail));
    return CheckResult(status, '${fps.toStringAsFixed(0)} 帧/秒（屏幕 ${rate.toStringAsFixed(0)} Hz），慢帧 $slow / ${timings.length}', [
      '每帧耗时：中位 ${pct(0.5).toStringAsFixed(1)} ms，P90 ${pct(0.9).toStringAsFixed(1)} ms，最慢 ${ms.last.toStringAsFixed(1)} ms（一帧预算 ${budget.toStringAsFixed(1)} ms）',
      '最慢的构建 ${build.toStringAsFixed(1)} ms，最慢的渲染 ${raster.toStringAsFixed(1)} ms',
      if (linuxCap) 'Linux 版 Flutter 引擎固定按 60 Hz 出帧（没有接入显示器的垂直同步），高刷新率显示器上也只有 60 帧。',
    ]);
  }),
  DiagnosticCheck('网络', (context, _) async {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 6), validateStatus: (_) => true));
    final targets = const [
      ('网易云音乐', 'https://music.163.com/'),
      ('QQ 音乐', 'https://y.qq.com/'),
      ('酷狗音乐', 'https://www.kugou.com/'),
      ('模型下载（GitHub）', 'https://github.com/k2-fsa/sherpa-onnx/releases'),
    ];
    final results = await Future.wait([
      for (final (name, url) in targets)
        () async {
          final sw = Stopwatch()..start();
          try {
            final r = await dio.get<void>(url, options: Options(responseType: ResponseType.stream, followRedirects: true));
            return (name, true, '${sw.elapsedMilliseconds} ms（HTTP ${r.statusCode}）');
          } catch (e) {
            return (name, false, '连不上（${e is DioException ? e.type.name : e.runtimeType}）');
          }
        }(),
    ]);
    final bad = results.where((r) => !r.$2).length;
    return CheckResult(bad == 0 ? CheckStatus.ok : (bad == results.length ? CheckStatus.fail : CheckStatus.warn), bad == 0 ? '各服务都能连上' : '$bad 个服务连不上', [
      for (final (name, _, text) in results) '$name：$text',
    ]);
  }),
  DiagnosticCheck('账号', (context, _) async {
    final source = context.read<SourceManager>().current;
    final user = source.user;
    return CheckResult(CheckStatus.info, '${source.name}：${user == null ? '未登录' : '已登录（${user.nickname}）'}');
  }),
  DiagnosticCheck('播放引擎与音频输出', (context, _) async {
    final player = context.read<PlayerController>();
    final s = context.read<AppSettings>();
    if (player.engineError != null) return CheckResult(CheckStatus.fail, '播放引擎初始化失败', [player.engineError!]);
    final r = await player.audioReport();
    return CheckResult(CheckStatus.ok, player.current == null ? '正常（当前没有播放）' : '正常（正在播放：${player.current!.name}）', [
      for (final e in r.entries) '${e.key}：${e.value}',
      '音质：${s.quality.name}；音量均衡：${s.normalize ? '开' : '关'}；高保真引擎：${s.hifiEngine ? '开' : '关'}',
    ]);
  }),
  DiagnosticCheck('语音合成（本机声音）', (context, _) async {
    final voice = VoicePresets.byId(context.read<VoiceSettings>().voiceId);
    final cloud = const ['cosyvoice', 'elevenlabs', 'fish'].where((e) => context.read<VoiceSettings>().engine(e).usable).toList();
    final binding = voice.binding('local');
    final model = binding == null ? null : LocalVoiceModels.byId(binding.voices[VoiceLanguage.zh] ?? '');
    final extra = [if (cloud.isNotEmpty) '已配置的云端引擎：${cloud.join('、')}（优先使用）'];
    if (binding == null || model == null) return CheckResult(CheckStatus.info, '${voice.name}没有本机声音', extra);
    if (!await LocalTtsEngine.isInstalled(model)) {
      return CheckResult(CheckStatus.warn, '本机声音还没有下载', ['在“设置 → 云音助手 → 音色中心”下载（约 ${model.sizeMb} MB），之前朗读使用系统声音', ...extra]);
    }
    final engine = LocalTtsEngine();
    try {
      final sw = Stopwatch()..start();
      final audio = await engine.synthesize(binding, const TtsRequest('你好，这是一次声音测试，听听清不清楚。', language: VoiceLanguage.zh)).toList();
      final ms = sw.elapsedMilliseconds;
      final (samples, rate) = decodeWav16(audio.single.bytes);
      final seconds = samples.length / rate;
      final rtf = ms / 1000 / seconds;
      final peak = samples.fold<double>(0, (m, v) => math.max(m, v.abs()));
      var glitches = 0;
      for (var i = 1; i < samples.length; i++) {
        if ((samples[i] - samples[i - 1]).abs() > 0.35) glitches++;
      }
      final status = peak >= 0.99 || glitches >= 10 ? CheckStatus.fail : (rtf > 0.9 ? CheckStatus.warn : CheckStatus.ok);
      return CheckResult(status, '${voice.name}：合成 ${seconds.toStringAsFixed(1)} 秒语音用了 ${(ms / 1000).toStringAsFixed(1)} 秒', [
        '实时率 ${rtf.toStringAsFixed(2)}${rtf > 0.9 ? '（这台设备合成偏慢，句与句之间可能有停顿）' : ''}',
        '峰值 ${peak.toStringAsFixed(2)}${peak >= 0.99 ? '（削波）' : ''}，毛刺 $glitches 处',
        ...extra,
      ]);
    } catch (e) {
      return CheckResult(CheckStatus.fail, '合成失败', ['$e', ...extra]);
    } finally {
      engine.dispose();
    }
  }),
  DiagnosticCheck('语音识别与唤醒', (context, _) async {
    final s = context.read<AssistantSettings>();
    final ready = await VoiceModelStore.ready(s.asrModel);
    return CheckResult(ready ? CheckStatus.ok : (s.voiceWake ? CheckStatus.warn : CheckStatus.info), ready ? '离线模型完整（${s.asrModel.label}）' : '离线模型还没有下载', [
      '语音唤醒：${s.voiceWake ? '开' : '关'}；唤醒词：${s.wakeWord.isEmpty ? '你好云音' : s.wakeWord}',
      if (!ready) '第一次使用语音功能时自动下载',
    ]);
  }),
  DiagnosticCheck('存储与内存', (context, _) async {
    final info = await Diagnostics.native('storage');
    var voices = 0;
    if (!kIsWeb) {
      final root = (await getApplicationSupportDirectory()).path;
      for (final d in ['voices', 'voice']) {
        final dir = Directory('$root/$d');
        if (!dir.existsSync()) continue;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) voices += await e.length().catchError((_) => 0);
        }
      }
    }
    final free = (info['free'] as num?)?.toInt();
    final low = info['lowMemory'] == true || (free != null && free < 1 << 30);
    return CheckResult(low ? CheckStatus.warn : CheckStatus.ok, free == null ? '语音模型占用 ${_mb(voices)}' : '剩余空间 ${_mb(free)}', [
      if (info['total'] != null) '存储：共 ${_mb(info['total'] as num)}，剩余 ${_mb(free!)}${free < 1 << 30 ? '（不足 1 GB，下载与缓存可能失败）' : ''}',
      if (info['memTotal'] != null) '内存：共 ${_mb(info['memTotal'] as num)}，可用 ${_mb(info['memAvail'] as num)}${info['lowMemory'] == true ? '（系统处于低内存状态）' : ''}',
      '语音模型：${_mb(voices)}',
    ]);
  }),
  if (!kIsWeb && Platform.isAndroid)
    DiagnosticCheck('权限', (context, _) async {
      final a = context.read<AssistantSettings>();
      final s = context.read<AppSettings>();
      final p = await Diagnostics.native('permissions');
      final missing = <String>[
        if (a.voiceWake && p['microphone'] == false) '麦克风（语音唤醒需要）',
        if ((a.pet.isNotEmpty || s.statusBarLyrics) && p['overlay'] == false) '显示在其他应用上层（桌宠、状态栏歌词需要）',
        if (p['notifications'] == false) '通知（播放控制与语音唤醒的常驻通知需要）',
      ];
      String yes(Object? v) => v == true ? '已允许' : '未允许';
      return CheckResult(missing.isEmpty ? CheckStatus.ok : CheckStatus.warn, missing.isEmpty ? '需要的权限都已允许' : '缺少 ${missing.length} 项权限', [
        ...missing.map((m) => '缺少：$m'),
        '麦克风 ${yes(p['microphone'])}，悬浮窗 ${yes(p['overlay'])}，通知 ${yes(p['notifications'])}，不限制后台耗电 ${yes(p['batteryUnrestricted'])}',
      ]);
    }),
  if (!kIsWeb && Platform.isAndroid)
    DiagnosticCheck('最近的退出记录', (context, _) async {
      final list = await Diagnostics.exitReasons();
      final crashes = list.where((r) => '${r['reason']}'.contains('崩溃') || '${r['reason']}'.contains('无响应')).toList();
      return CheckResult(crashes.isEmpty ? CheckStatus.ok : CheckStatus.warn, crashes.isEmpty ? '最近没有崩溃或无响应' : '最近有 ${crashes.length} 次崩溃或无响应', [
        for (final r in list.take(5)) Diagnostics.describeExit(r),
      ]);
    }),
  DiagnosticCheck('本次运行的错误', (context, _) async {
    final d = Diagnostics.instance;
    final errors = d.recent.where((l) => l.length > 24 && l[24] == 'E').toList();
    return CheckResult(d.errors == 0 ? CheckStatus.ok : CheckStatus.warn, d.errors == 0 ? '没有错误' : '${d.errors} 个错误', [
      for (final l in errors.reversed.take(3)) l.split('\n').first,
    ]);
  }),
];
