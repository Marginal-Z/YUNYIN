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
    // 比设计尺寸小时按比例缩小；比设计尺寸大时只放大一半（大屏既让卡片与文字变大，也多显示一些内容）。
    double damp(double raw, double min, double max) => (raw <= 1 ? raw : 1 + (raw - 1) * 0.5).clamp(min, max);
    if (size.width >= desktopBreakpoint) {
      return damp(math.min(size.width / _desktopDesignSize.width, size.height / _desktopDesignSize.height), 0.8, 1.3);
    }
    // 按短边缩放：竖屏即宽度；横屏时不会因为宽度大而把高度压得过矮。平板竖屏最多放大 1.4 倍。
    return damp(size.shortestSide / _mobileDesignWidth, 0.82, 1.4);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final textScaler = mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15);
    var s = scaleFor(mq.size, desktopBreakpoint);
    if ((s - 1).abs() < 0.01) s = 1;
    final desktop = mq.size.width >= desktopBreakpoint;
    // 无论是否缩放都使用同一组件结构：调整窗口大小跨过设计尺寸时，整个应用不会被重新挂载。
    // 倍数为 1 时 FittedBox 的变换是单位矩阵，不会产生额外的图层。
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
