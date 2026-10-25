import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// CSS 的 blur 半径对应高斯 sigma = blur / 2。
double cssSigma(double blur) => blur / 2;

/// 按 CSS `linear-gradient(<angle>deg, ...)` 语义计算渐变线的线性渐变。
class CssGradient extends LinearGradient {
  const CssGradient(this.angle, {required super.colors, super.stops});

  /// 角度，0deg 指向上方，顺时针。
  final double angle;

  @override
  Shader createShader(Rect rect, {TextDirection? textDirection}) {
    final rad = angle * math.pi / 180;
    final dir = Offset(math.sin(rad), -math.cos(rad));
    final len = (rect.width * math.sin(rad)).abs() + (rect.height * math.cos(rad)).abs();
    final c = rect.center;
    return ui.Gradient.linear(c - dir * (len / 2), c + dir * (len / 2), colors, stops);
  }

  static CssGradient vertical(List<Color> colors) => CssGradient(180, colors: colors);
}

/// CSS 外阴影。
///
/// 半透明的玻璃需要把阴影裁到盒子外侧（CSS 外阴影不会透过半透明背景显示）；
/// 其余（不透明卡片、封面等）直接绘制模糊圆角矩形，Impeller 对此有解析式快速通道，几乎没有开销。
class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter(this.radius, this.shadows, {required this.clipInside});

  final BorderRadius radius;
  final List<Shadow2> shadows;
  final bool clipInside;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final rrect = radius.toRRect(Offset.zero & size);
    if (clipInside) {
      canvas.save();
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect((Offset.zero & size).inflate(200))
          ..addRRect(rrect),
      );
    }
    for (final s in shadows) {
      final p = Paint()..color = s.color;
      if (s.blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, cssSigma(s.blur));
      canvas.drawRRect(rrect.shift(s.offset).inflate(s.spread), p);
    }
    if (clipInside) canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) => old.radius != radius || !identical(old.shadows, shadows) || old.clipInside != clipInside;
}

/// CSS `inset` 阴影的低开销近似：只用渐变描边，不做任何模糊（模糊的路径在 Impeller 上每帧都要离屏渲染）。
/// - `inset 0 1px 1px` 顶部高光 / `inset 0 -1px 1px` 底部阴影：沿边缘的渐隐描边；
/// - `inset 0 0 0 1px` 内描边：实线描边；
/// - `inset 0 0 14px` 内发光：较宽的半透明描边。
class InsetShadowPainter extends CustomPainter {
  InsetShadowPainter(this.radius, this.shadows, {this.border});

  final BorderRadius radius;
  final List<Shadow2> shadows;
  final Color? border;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    for (final s in shadows) {
      final paint = Paint()..style = PaintingStyle.stroke;
      if (s.blur == 0 && s.dx == 0 && s.dy == 0) {
        final w = math.max(s.spread, 0.5);
        canvas.drawRRect(
          rrect.deflate(w / 2),
          paint
            ..strokeWidth = w
            ..color = s.color,
        );
      } else if (s.dy != 0) {
        final reach = math.min(size.height / 2, (s.dy.abs() + s.blur) * 3 + 2);
        final top = s.dy > 0;
        paint
          ..strokeWidth = 1.2 + s.blur * 0.4
          ..shader = ui.Gradient.linear(Offset(0, top ? 0 : size.height), Offset(0, top ? reach : size.height - reach), [
            s.color,
            s.color.withValues(alpha: 0),
          ]);
        canvas.drawRRect(rrect.deflate(paint.strokeWidth / 2), paint);
      } else {
        final w = s.blur * 0.5;
        canvas.drawRRect(
          rrect.deflate(w / 2),
          paint
            ..strokeWidth = w
            ..color = s.color.withValues(alpha: s.color.a * 0.45),
        );
      }
    }
    if (border != null) {
      canvas.drawRRect(
        rrect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = border!,
      );
    }
  }

  @override
  bool shouldRepaint(InsetShadowPainter old) => old.radius != radius || !identical(old.shadows, shadows) || old.border != border;
}

/// CSS `saturate(200%)` 对应的颜色矩阵。
List<double> saturateMatrix(double s) => [
  0.213 + 0.787 * s,
  0.715 - 0.715 * s,
  0.072 - 0.072 * s,
  0,
  0,
  0.213 - 0.213 * s,
  0.715 + 0.285 * s,
  0.072 - 0.072 * s,
  0,
  0,
  0.213 - 0.213 * s,
  0.715 - 0.715 * s,
  0.072 + 0.928 * s,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

/// 玻璃滤镜：模糊 + 饱和度 200%。模糊半径取 24（视觉上与设计稿的 30px 基本一致，开销明显更低）。
final ui.ImageFilter _glassFilter = ui.ImageFilter.compose(
  outer: ui.ColorFilter.matrix(saturateMatrix(2)),
  inner: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24, tileMode: TileMode.clamp),
);

/// 是否启用毛玻璃（设置项“窗口毛玻璃效果”）。
class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassScope>()?.enabled ?? true;

  @override
  bool updateShouldNotify(GlassScope old) => old.enabled != enabled;
}

/// 通用盒子：背景色/渐变、圆角、外阴影、内阴影、描边、可选背景模糊。
class YBox extends StatelessWidget {
  const YBox({
    super.key,
    this.width,
    this.height,
    this.radius = BorderRadius.zero,
    this.color,
    this.gradient,
    this.shadows = const [],
    this.insets = const [],
    this.border,
    this.blur = false,
    this.padding,
    this.alignment,
    this.clip = false,
    this.child,
  });

  final double? width;
  final double? height;
  final BorderRadius radius;
  final Color? color;
  final Gradient? gradient;
  final List<Shadow2> shadows;
  final List<Shadow2> insets;
  final Color? border;
  final bool blur;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry? alignment;
  final bool clip;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    // 未指定宽 / 高时，对齐不应撑满父级（与 CSS 中 inline-flex 的行为一致）。
    final aligned = alignment == null || child == null
        ? child
        : Align(alignment: alignment!, widthFactor: width == null ? 1 : null, heightFactor: height == null ? 1 : null, child: child);
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(color: color, gradient: gradient, borderRadius: radius),
      child: aligned,
    );
    if (insets.isNotEmpty || border != null) {
      content = CustomPaint(
        foregroundPainter: InsetShadowPainter(radius, insets, border: border),
        child: content,
      );
    }
    if (blur && GlassScope.of(context)) {
      content = ClipRRect(
        borderRadius: radius,
        // 同一页面的多块玻璃共享一次背景采样（需要祖先 BackdropGroup）。
        child: BackdropGroup.of(context) != null
            ? BackdropFilter.grouped(filter: _glassFilter, child: content)
            : BackdropFilter(filter: _glassFilter, child: content),
      );
    } else if (clip) {
      content = ClipRRect(borderRadius: radius, child: content);
    }
    if (shadows.isNotEmpty) {
      content = CustomPaint(
        painter: _OuterShadowPainter(radius, shadows, clipInside: blur),
        child: content,
      );
    }
    if (width != null || height != null) {
      content = SizedBox(width: width, height: height, child: content);
    }
    return content;
  }
}

/// Liquid Glass 材质。
class Glass extends StatelessWidget {
  const Glass({super.key, required this.radius, this.width, this.height, this.padding, this.color, this.shadows, this.insets, this.alignment, this.child});

  final double radius;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final List<Shadow2>? shadows;
  final List<Shadow2>? insets;
  final AlignmentGeometry? alignment;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = GlassScope.of(context);
    var bg = color ?? p.glass;
    if (!enabled) bg = Color.alphaBlend(bg, p.isDark ? const Color(0xFF26272C) : const Color(0xFFF2F3F7));
    return YBox(
      width: width,
      height: height,
      radius: BorderRadius.circular(radius),
      color: bg,
      blur: true,
      shadows: shadows ?? p.glassShadow,
      insets: insets ?? p.glassInset,
      border: p.glassBorder,
      padding: padding,
      alignment: alignment,
      child: child,
    );
  }
}
