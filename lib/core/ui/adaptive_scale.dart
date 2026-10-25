import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 移动布局按设计稿宽度 390 排版；桌面布局在窗口小于设计尺寸时等比缩小。
const _mobileDesignWidth = 390.0;
const _desktopDesignSize = Size(1180, 760);

/// 界面随设备等比缩放：先按设计尺寸排版，再整体缩放到屏幕上，
/// 窄屏不会挤压、宽屏不会拉散，系统字体放大也限制在不会撑破布局的范围内。
class AdaptiveScale extends StatelessWidget {
  const AdaptiveScale({super.key, required this.desktopBreakpoint, required this.child});

  /// 宽度达到该值使用桌面布局（按缩放前的宽度判断，避免缩放后布局来回切换）。
  final double desktopBreakpoint;
  final Widget child;

  /// 当前缩放倍数（界面逻辑像素 × 倍数 = 屏幕逻辑像素）。
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ScaleScope>()?.scale ?? 1;

  /// 是否使用桌面布局（按缩放前的宽度判断）。
  static bool? desktopOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ScaleScope>()?.desktop;

  static double scaleFor(Size size, double desktopBreakpoint) {
    if (size.isEmpty) return 1;
    if (size.width >= desktopBreakpoint) {
      final s = math.min(size.width / _desktopDesignSize.width, size.height / _desktopDesignSize.height);
      return s.clamp(0.8, 1.0);
    }
    // 按短边缩放：竖屏即宽度；横屏时不会因为宽度大而把高度压得过矮。
    return (size.shortestSide / _mobileDesignWidth).clamp(0.82, 1.18);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final textScaler = mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15);
    final s = scaleFor(mq.size, desktopBreakpoint);
    final desktop = mq.size.width >= desktopBreakpoint;
    if ((s - 1).abs() < 0.01) {
      return _ScaleScope(
        scale: 1,
        desktop: desktop,
        child: MediaQuery(data: mq.copyWith(textScaler: textScaler), child: child),
      );
    }
    final logical = mq.size / s;
    final data = mq.copyWith(
      size: logical,
      devicePixelRatio: mq.devicePixelRatio * s,
      padding: mq.padding / s,
      viewPadding: mq.viewPadding / s,
      viewInsets: mq.viewInsets / s,
      systemGestureInsets: mq.systemGestureInsets / s,
      textScaler: textScaler,
    );
    return _ScaleScope(
      scale: s,
      desktop: desktop,
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: logical.width,
          height: logical.height,
          child: MediaQuery(data: data, child: child),
        ),
      ),
    );
  }
}

class _ScaleScope extends InheritedWidget {
  const _ScaleScope({required this.scale, required this.desktop, required super.child});

  final double scale;
  final bool desktop;

  @override
  bool updateShouldNotify(_ScaleScope old) => old.scale != scale || old.desktop != desktop;
}
