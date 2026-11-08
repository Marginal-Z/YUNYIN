import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 流畅度检测：右上角显示最近一秒的帧率与最慢一帧，并把超出帧预算的帧（构建 / 渲染各用多少毫秒）
/// 写进日志（标签 perf），用来定位“页面切换掉帧”是界面线程还是渲染线程慢。
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
      _listening = true;
    } else if (!widget.enabled && _listening) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _listening = false;
      _window.clear();
    }
  }

  /// 一帧的预算（毫秒），按屏幕刷新率计算。
  double get _budget {
    final rate = ui.PlatformDispatcher.instance.views.firstOrNull?.display.refreshRate ?? 60;
    return 1000 / (rate <= 0 ? 60 : rate);
  }

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
    // 只保留最近一秒。
    final end = _window.last.timestampInMicroseconds(ui.FramePhase.rasterFinish);
    _window.removeWhere((t) => end - t.timestampInMicroseconds(ui.FramePhase.rasterFinish) > 1000000);
    final worst = _window.fold<ui.FrameTiming?>(null, (a, b) => a == null || b.totalSpan > a.totalSpan ? b : a);
    if (worst == null) return;
    _stats.value = '${_window.length} fps · 最慢 ${(worst.totalSpan.inMicroseconds / 1000).toStringAsFixed(0)}ms'
        '（构建 ${(worst.buildDuration.inMicroseconds / 1000).toStringAsFixed(0)} / 渲染 ${(worst.rasterDuration.inMicroseconds / 1000).toStringAsFixed(0)}）';
  }

  @override
  void dispose() {
    if (_listening) SchedulerBinding.instance.removeTimingsCallback(_onTimings);
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
