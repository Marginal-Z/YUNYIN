import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 移动布局按设计稿宽度 390 排版；桌面布局在窗口小于设计尺寸时等比缩小。
const _mobileDesignWidth = 390.0;
const _desktopDesignSize = Size(1180, 760);

/// 界面随设备等比缩放：先按设计尺寸排版，再整体缩放到屏幕上，
/// 窄屏不会挤压、宽屏不会拉散，系统字体放大也限制在不会撑破布局的范围内。
class AdaptiveScale extends StatefulWidget {
  const AdaptiveScale({super.key, required this.desktopBreakpoint, required this.child});

  /// 宽度达到该值使用桌面布局（按缩放前的宽度判断，避免缩放后布局来回切换）。
  final double desktopBreakpoint;
  final Widget child;

  /// 当前缩放倍数（界面逻辑像素 × 倍数 = 屏幕逻辑像素）。
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ScaleScope>()?.scale ?? 1;

  /// 是否使用桌面布局（按缩放前的宽度判断）。
  static bool? desktopOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ScaleScope>()?.desktop;

  /// 是否使用桌面布局：Android / iOS 的手机与平板始终使用移动布局（横屏时为横屏极简布局）；电脑按窗口宽度判断。
  static bool isDesktopLayout(Size size, double desktopBreakpoint) {
    final mobileOs = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (mobileOs) return false;
    return size.width >= desktopBreakpoint;
  }

  static double scaleFor(Size size, double desktopBreakpoint) {
    if (size.isEmpty) return 1;
    // 比设计尺寸小时按比例缩小；比设计尺寸大时只放大一半（大屏既让卡片与文字变大，也多显示一些内容）。
    double damp(double raw, double min, double max) => (raw <= 1 ? raw : 1 + (raw - 1) * 0.5).clamp(min, max);
    if (isDesktopLayout(size, desktopBreakpoint)) {
      // 桌面窗口不放大：窗口大于设计尺寸时按 1:1 渲染、显示更多内容。此前大窗口（例如 2560 宽的屏幕上最大化）
      // 整体放大到 1.3 倍，所有文字、细线与圆角都落在半个像素上，看起来发虚、有锯齿；界面大小应由系统的缩放比例决定，
      // 系统缩放会按真实的像素密度渲染，始终清晰。窗口小于设计尺寸时按 0.05 一档缩小，接近设计尺寸时正好 1 倍。
      final raw = math.min(size.width / _desktopDesignSize.width, size.height / _desktopDesignSize.height).clamp(0.8, 1.0);
      if (1 - raw < 0.06) return 1;
      return (raw * 20).floorToDouble() / 20;
    }
    // 按短边缩放：竖屏即宽度；横屏时不会因为宽度大而把高度压得过矮。平板竖屏最多放大 1.4 倍。
    // 接近设计宽度（±6%）时按 1:1 渲染：例如三星 S23 Ultra 宽 384 时原来缩小到 0.985 倍，整个界面的文字、
    // 细线与图标都落在物理像素之间，看起来发虚，滚动时边缘闪烁。这个范围内布局本身就放得下。
    final raw = damp(size.shortestSide / _mobileDesignWidth, 0.82, 1.4);
    return (raw - 1).abs() < 0.06 ? 1 : raw;
  }

  @override
  State<AdaptiveScale> createState() => _AdaptiveScaleState();
}

class _AdaptiveScaleState extends State<AdaptiveScale> {
  /// 正在使用的缩放倍数，与等待生效的倍数。
  double? _scale;
  double? _pending;
  Timer? _settle;
  bool? _layoutDesktop;

  static bool get _desktopOs =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final textScaler = mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15);
    var target = AdaptiveScale.scaleFor(mq.size, widget.desktopBreakpoint);
    if ((target - 1).abs() < 0.01) target = 1;
    // 电脑上拖动窗口边缘改变大小时，倍数按 0.05 一档变化，每跨一档整个界面突然放大或缩小 5%，看起来像窗口边缘在抖。
    // 改为拖动过程中保持原来的倍数（只是多显示或少显示一些内容），停下 0.2 秒后再换成新的倍数，整个过程只变一次。
    final layoutDesktop = AdaptiveScale.isDesktopLayout(mq.size, widget.desktopBreakpoint);
    final layoutChanged = _layoutDesktop != null && _layoutDesktop != layoutDesktop;
    _layoutDesktop = layoutDesktop;
    // 跨过桌面 / 手机布局的分界时立即换倍数：否则新布局会按旧倍数画 0.2 秒（挤压或溢出）。
    if (_scale == null || !_desktopOs || layoutChanged) {
      _scale = target;
      _pending = null;
      _settle?.cancel();
    } else if (target != _scale) {
      if (target != _pending) {
        _pending = target;
        _settle?.cancel();
        _settle = Timer(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _scale = _pending);
        });
      }
    } else {
      _pending = null;
      _settle?.cancel();
    }
    final s = _scale!;
    final desktop = AdaptiveScale.isDesktopLayout(mq.size, widget.desktopBreakpoint);
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
          child: MediaQuery(data: data, child: widget.child),
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
