import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 流畅度检测：右上角显示最近一秒的帧率与最慢一帧，并把超出帧预算的帧（构建 / 渲染各用多少毫秒）
/// 写进日志（标签 perf），用来定位“页面切换掉帧”是界面线程还是渲染线程慢。
///
/// 另有几个对照实验开关（[PerfLab]），只在打开流畅度检测时显示，用来找出绘制开销大的部分。
abstract final class PerfLab {
  /// 不绘制卡片的外阴影。
  static bool noShadow = false;

  /// 隐藏底部导航栏与迷你播放条。
  static bool noChrome = false;
}

class PerfOverlay extends StatefulWidget {
  const PerfOverlay({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends State<PerfOverlay> {
  final _stats = ValueNotifier<String>('');
  final _window = <ui.FrameTiming>[];
  bool _listening = false;

  /// 每 0.5 秒更新一次显示：如果每批帧数据都更新文字，更新本身又会产生新的帧，安静时也一直在出帧。
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PerfOverlay old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.enabled && !_listening) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _refresh = Timer.periodic(const Duration(milliseconds: 500), (_) => _show());
      _listening = true;
    } else if (!widget.enabled && _listening) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _refresh?.cancel();
      _listening = false;
      _window.clear();
    }
  }

  /// 一帧的预算（毫秒），按屏幕刷新率计算。
  double get _budget {
    final rate = ui.PlatformDispatcher.instance.views.firstOrNull?.display.refreshRate ?? 60;
    return 1000 / (rate <= 0 ? 60 : rate);
  }

  /// 帧完成时的墙上时间（FrameTiming 用的是单调时钟，换算成墙上时间方便按“最近一秒”筛选）。
  final _clockOffset = DateTime.now().microsecondsSinceEpoch - Timeline.now;
  int _wall(ui.FrameTiming t) => t.timestampInMicroseconds(ui.FramePhase.rasterFinish) + _clockOffset;

  void _onTimings(List<ui.FrameTiming> timings) {
    final budget = _budget;
    for (final t in timings) {
      _window.add(t);
      final total = t.totalSpan.inMicroseconds / 1000;
      if (total > budget * 1.5) {
        debugPrint('perf: 慢帧 ${total.toStringAsFixed(1)}ms（构建 ${(t.buildDuration.inMicroseconds / 1000).toStringAsFixed(1)}ms，'
            '渲染 ${(t.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1)}ms，排队 ${(t.vsyncOverhead.inMicroseconds / 1000).toStringAsFixed(1)}ms）');
      }
    }
  }

  void _show() {
    // 只统计最近一秒。
    final now = DateTime.now().microsecondsSinceEpoch;
    _window.removeWhere((t) => now - _wall(t) > 1000000);
    final worst = _window.fold<ui.FrameTiming?>(null, (a, b) => a == null || b.totalSpan > a.totalSpan ? b : a);
    if (worst == null) {
      _stats.value = '0 fps';
      return;
    }
    _stats.value = '${_window.length} fps · 最慢 ${(worst.totalSpan.inMicroseconds / 1000).toStringAsFixed(0)}ms'
        '（构建 ${(worst.buildDuration.inMicroseconds / 1000).toStringAsFixed(0)} / 渲染 ${(worst.rasterDuration.inMicroseconds / 1000).toStringAsFixed(0)}）';
  }

  @override
  void dispose() {
    if (_listening) SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _refresh?.cancel();
    _stats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 4,
          right: 8,
          child: IgnorePointer(
            child: ValueListenableBuilder<String>(
              valueListenable: _stats,
              builder: (context, s, _) => s.isEmpty
                  ? const SizedBox.shrink()
                  : DecoratedBox(
                      decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(s, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11, color: Color(0xFFFFFFFF), decoration: TextDecoration.none)),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
