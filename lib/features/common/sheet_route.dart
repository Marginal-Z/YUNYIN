import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 从底部弹出的全屏页面（正在播放）。
///
/// 打开时页面从下方略微升起、由 88% 放大到全屏并淡入，圆角随之收起，下方页面逐渐变暗，
/// 配合弹簧阻尼曲线（封面从迷你播放条飞入由 Hero 完成）；收起时反向滑回。
/// [dismissible] 时可以按住页面向下拖动，页面跟随手指，松手后按位置与速度决定收起或弹回。
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
  Color? get barrierColor => const Color(0x59000000);

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
        final gesture = _dragging || navigator?.userGestureInProgress == true;
        if (gesture || animation.status == AnimationStatus.reverse) {
          // 拖动时页面跟随手指；收起时整页滑回下方。
          final t = gesture ? v : Curves.easeInCubic.transform(v);
          final radius = (1 - v).clamp(0.0, 1.0) * 120;
          return FractionalTranslation(
            translation: Offset(0, 1 - t),
            child: ClipRRect(
              clipBehavior: v < 1 ? Clip.antiAlias : Clip.none,
              borderRadius: BorderRadius.vertical(top: Radius.circular(math.min(radius, 28))),
              child: child,
            ),
          );
        }
        // 弹出：升起 + 放大 + 淡入，圆角从 36 收到 0。
        final t = const _OpenCurve().transform(v);
        final scale = 0.88 + 0.12 * math.min(t, 1.006);
        final radius = (1 - t).clamp(0.0, 1.0) * 36;
        return Opacity(
          opacity: (v * 3).clamp(0.0, 1.0),
          child: FractionalTranslation(
            // 位移不越过终点（回弹只体现在缩放上），页面底部不会露出缝隙。
            translation: Offset(0, (1 - math.min(t, 1.0)) * 0.3),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: ClipRRect(
                clipBehavior: v < 1 ? Clip.antiAlias : Clip.none,
                borderRadius: BorderRadius.circular(radius),
                child: child,
              ),
            ),
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
