import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 平滑鼠标滚轮。
///
/// Flutter 桌面端每格滚轮直接跳动几十像素，在 Linux / Windows 的普通鼠标上看起来一顿一顿的。
/// 这里在指针事件进入框架之前，把每格滚轮的位移按指数衰减分摊到接下来的若干帧（约 0.2 秒），
/// 所有可滚动区域因此都获得平滑滚动，不需要逐个修改。
///
/// 只处理鼠标滚轮（触控板的连续滚动、触屏与 macOS 不受影响）；连续快速滚动时位移累加，
/// 不会丢失距离。
abstract final class SmoothWheel {
  static ui.PointerDataPacketCallback? _next;
  static final Map<int, _Pending> _pending = {};
  static int? _frame;
  static Duration? _last;

  /// 衰减时间常数（秒）：越小越跟手。
  static const _tau = 0.055;

  static bool get _supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows);

  /// 在 [WidgetsFlutterBinding.ensureInitialized] 之后调用。
  static void install() {
    if (!_supported || _next != null) return;
    final dispatcher = ui.PlatformDispatcher.instance;
    _next = dispatcher.onPointerDataPacket;
    dispatcher.onPointerDataPacket = _onPacket;
  }

  static void _onPacket(ui.PointerDataPacket packet) {
    final pass = <ui.PointerData>[];
    for (final d in packet.data) {
      if (d.signalKind == ui.PointerSignalKind.scroll && d.kind == ui.PointerDeviceKind.mouse && (d.scrollDeltaX != 0 || d.scrollDeltaY != 0)) {
        final p = _pending.putIfAbsent(d.device, () => _Pending());
        // 反向滚动时丢弃尚未滚完的部分，立即响应新方向。
        if (p.dy * d.scrollDeltaY < 0) p.dy = 0;
        if (p.dx * d.scrollDeltaX < 0) p.dx = 0;
        p
          ..template = d
          ..dx += d.scrollDeltaX
          ..dy += d.scrollDeltaY;
        _schedule();
      } else {
        pass.add(d);
      }
    }
    if (pass.isNotEmpty) _next!(pass.length == packet.data.length ? packet : ui.PointerDataPacket(data: pass));
  }

  static void _schedule() {
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback(_tick);
  }

  static void _tick(Duration now) {
    _frame = null;
    final dt = _last == null ? 1 / 60 : ((now - _last!).inMicroseconds / 1e6).clamp(0.001, 0.05);
    _last = now;
    final out = <ui.PointerData>[];
    final done = <int>[];
    // 每帧滚动剩余位移的 (1 - e^(-dt/τ))；不足 1 像素时一次滚完。
    final f = 1 - math.exp(-dt / _tau);
    _pending.forEach((device, p) {
      var sx = p.dx * f, sy = p.dy * f;
      if (p.dx.abs() < 1) sx = p.dx;
      if (p.dy.abs() < 1) sy = p.dy;
      p
        ..dx -= sx
        ..dy -= sy;
      if (sx != 0 || sy != 0) {
        final t = p.template!;
        out.add(
          ui.PointerData(
            viewId: t.viewId,
            timeStamp: t.timeStamp,
            change: t.change,
            kind: t.kind,
            signalKind: ui.PointerSignalKind.scroll,
            device: t.device,
            physicalX: t.physicalX,
            physicalY: t.physicalY,
            buttons: t.buttons,
            scrollDeltaX: sx,
            scrollDeltaY: sy,
            embedderId: t.embedderId,
          ),
        );
      }
      if (p.dx == 0 && p.dy == 0) done.add(device);
    });
    done.forEach(_pending.remove);
    if (out.isNotEmpty) _next!(ui.PointerDataPacket(data: out));
    if (_pending.isNotEmpty) {
      _schedule();
    } else {
      _last = null;
    }
  }
}

class _Pending {
  double dx = 0;
  double dy = 0;
  ui.PointerData? template;
}
