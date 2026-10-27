import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 从底部滑入的全屏页面（正在播放）。
///
/// 打开时带轻微回弹的减速曲线；[dismissible] 时可以按住页面向下拖动，页面跟随手指，
/// 松手后按位置与速度决定收起或弹回（与系统音乐 App 的播放页相同）。拖动时顶部出现圆角。
class SheetRoute<T> extends PageRoute<T> {
  SheetRoute({required this.builder, this.dismissible = false});

  final WidgetBuilder builder;
  final bool dismissible;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 480);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 340);

  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  bool _dragging = false;

  @override
  // 单独一组背景截取：滑入时下方页面仍在绘制，本页的玻璃应读取本页的背景。
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => BackdropGroup(child: builder(context));

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final page = dismissible ? _SheetDrag(route: this, child: child) : child;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final v = animation.value;
        // 拖动与松手后的动画由手势直接控制位置，不再套曲线，避免跳变。
        final t = _dragging || navigator?.userGestureInProgress == true
            ? v
            : (animation.status == AnimationStatus.reverse ? Curves.easeInCubic.transform(v) : math.min(1.0, const _OpenCurve().transform(v)));
        final radius = (1 - v).clamp(0.0, 1.0) * 120;
        return FractionalTranslation(
          translation: Offset(0, 1 - t),
          child: ClipRRect(
            clipBehavior: v < 1 ? Clip.antiAlias : Clip.none,
            borderRadius: BorderRadius.vertical(top: Radius.circular(math.min(radius, 28))),
            child: child,
          ),
        );
      },
      child: page,
    );
  }

  void _dragStart() {
    _dragging = true;
    navigator?.didStartUserGesture();
  }

  void _dragUpdate(double fraction) {
    controller!.value = (controller!.value - fraction).clamp(0.0, 1.0);
  }

  /// [velocity] 以页面高度每秒计，向下为正。
  void _dragEnd(double velocity) {
    final c = controller!;
    final close = velocity > 1.2 || (velocity > -0.6 && c.value < 0.72);
    const curve = Curves.easeOutCubic;
    if (close) {
      navigator?.pop();
      if (c.isAnimating) {
        c.animateBack(
          0,
          duration: Duration(milliseconds: (300 * c.value).round().clamp(120, 300)),
          curve: curve,
        );
      }
    } else {
      c.animateTo(
        1,
        duration: Duration(milliseconds: (420 * (1 - c.value)).round().clamp(160, 420)),
        curve: curve,
      );
    }
    void done() {
      _dragging = false;
      navigator?.didStopUserGesture();
    }

    if (c.isAnimating) {
      late final AnimationStatusListener l;
      l = (s) {
        if (s == AnimationStatus.forward || s == AnimationStatus.reverse) return;
        c.removeStatusListener(l);
        done();
      };
      c.addStatusListener(l);
    } else {
      done();
    }
  }
}

class _SheetDrag extends StatelessWidget {
  const _SheetDrag({required this.route, required this.child});

  final SheetRoute route;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        return GestureDetector(
          onVerticalDragStart: (_) => route._dragStart(),
          onVerticalDragUpdate: (d) => route._dragUpdate(d.delta.dy / h),
          onVerticalDragEnd: (d) => route._dragEnd(d.velocity.pixelsPerSecond.dy / h),
          onVerticalDragCancel: () => route._dragEnd(0),
          child: child,
        );
      },
    );
  }
}

/// 打开曲线：快速滑入后柔和减速（弹簧阻尼曲线，超出部分被截掉，页面不会越过顶部）。
class _OpenCurve extends Curve {
  const _OpenCurve();

  @override
  double transformInternal(double t) {
    // 阻尼振动 1 - e^(-ζωt)·cos(ω_d t)，参数取为在 t = 1 时完全停稳。
    const zeta = 0.78, omega = 11.0;
    final wd = omega * math.sqrt(1 - zeta * zeta);
    final x = 1 - math.exp(-zeta * omega * t) * (math.cos(wd * t) + zeta * omega / wd * math.sin(wd * t));
    // 归一化，保证 t = 1 时恰好为 1。
    final end = 1 - math.exp(-zeta * omega) * (math.cos(wd) + zeta * omega / wd * math.sin(wd));
    return x / end;
  }
}
