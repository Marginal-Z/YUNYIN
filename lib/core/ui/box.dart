import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../settings.dart';
import '../theme/palette.dart';
import 'cover.dart';
import 'liquid_glass_filter.dart';

/// 桌面端（Linux 的 OpenGL、Windows 的 ANGLE）渲染时没有多重采样，圆角裁剪的边缘是锯齿；
/// 画出的圆角矩形本身是抗锯齿的。这两个平台上圆角裁剪改用画出来的圆角遮罩（见 [SoftClipRRect]）。
final bool kSoftClip = !kIsWeb && (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows);

/// 抗锯齿的圆角裁剪：把内容按一张画好的圆角遮罩（屏幕分辨率，抗锯齿）合成，而不是用会产生锯齿的裁剪。
/// 遮罩按尺寸缓存。不能包含背景滤镜（遮罩图层里的背景滤镜取不到页面内容）。
class SoftClipRRect extends StatelessWidget {
  const SoftClipRRect({super.key, required this.radius, required this.child});

  final BorderRadius radius;
  final Widget child;

  static final _masks = <String, ui.Image>{};

  static ui.Image _mask(Size size, BorderRadius radius, double dpr) {
    final w = (size.width * dpr).ceil().clamp(1, 8192), h = (size.height * dpr).ceil().clamp(1, 8192);
    final key = '$w×$h|${radius.topLeft.x}|${radius.topRight.x}|${radius.bottomRight.x}|${radius.bottomLeft.x}|$dpr';
    final hit = _masks.remove(key);
    if (hit != null) return _masks[key] = hit;
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
        .drawRRect(radius.toRRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())).scaleRadii().multiply(dpr), Paint()..color = const Color(0xFFFFFFFF));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    _masks[key] = image;
    while (_masks.length > 48) {
      _masks.remove(_masks.keys.first)!.dispose();
    }
    return image;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // 遮罩只作用在自身矩形内：超出矩形的内容（例如放大后模糊的背景图）先用矩形裁掉（水平垂直的边没有锯齿）。
    // 外面再包一层几乎不透明的 Opacity，让遮罩在独立图层里合成：否则 Impeller 上遮罩的 dstIn 会把卡片下面
    // 已经画好的阴影也一并擦掉（圆角外露出窗口底色）。
    return Opacity(
      opacity: 0.999,
      child: ClipRect(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) {
            final mask = _mask(rect.size, radius, dpr);
            return ImageShader(mask, TileMode.clamp, TileMode.clamp, Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1).storage);
          },
          child: child,
        ),
      ),
    );
  }
}

extension on RRect {
  /// 圆角半径按倍数缩放（矩形本身已是物理像素）。
  RRect multiply(double k) =>
      RRect.fromLTRBAndCorners(left, top, right, bottom, topLeft: tlRadius * k, topRight: trRadius * k, bottomRight: brRadius * k, bottomLeft: blRadius * k);
}

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

/// 是否启用毛玻璃（设置项“窗口毛玻璃效果”）与液态玻璃材质。
class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.enabled, this.material = GlassMaterial.clear, required super.child});

  final bool enabled;
  final GlassMaterial material;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassScope>()?.enabled ?? true;

  static GlassMaterial materialOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassScope>()?.material ?? GlassMaterial.clear;

  @override
  bool updateShouldNotify(GlassScope old) => old.enabled != enabled || old.material != material;
}

/// 液态玻璃（着色器版本，见 shaders/liquid_glass.frag）：玻璃本身没有填充色，
/// 只靠折射、色散、边缘高光与「柔和」材质的模糊和色调呈现，外加原版背景中的柔和投影。
Widget _shaderGlass({
  required double radius,
  required GlassMaterial material,
  required bool dark,
  double? width,
  double? height,
  EdgeInsetsGeometry? padding,
  AlignmentGeometry? alignment,
  bool legible = false,
  Widget? child,
}) {
  Widget content = Container(padding: padding, alignment: alignment, child: child);
  content = LiquidGlassBackdrop(radius: radius, material: material, legible: legible, child: content);
  // 投影：浅色模式下柔和、贴近（迷你播放条与导航栏上下相邻，投影不能落到另一块玻璃里再被折射成一圈暗边）；
  // 深色模式的黑色投影在深色背景上只会形成一圈脏边，不画。
  if (!dark) {
    content = CustomPaint(
      painter: _OuterShadowPainter(BorderRadius.circular(radius), const [Shadow2(0, 4, 18, Color.fromRGBO(0, 0, 0, 0.08))], clipInside: true),
      child: content,
    );
  }
  return width != null || height != null ? SizedBox(width: width, height: height, child: content) : content;
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
      final c = child;
      if (kSoftClip && c is CoverImage && padding == null && alignment == null && color == null && gradient == null && insets.isEmpty && border == null) {
        // 只有一张封面：直接把图片画成抗锯齿的圆角矩形，不需要裁剪或遮罩图层。
        content = CoverImage(c.url, imageSize: c.imageSize, radius: radius);
      } else if (kSoftClip && c is Cover && padding == null && alignment == null && color == null && gradient == null && insets.isEmpty && border == null) {
        // 封面自己已经画成圆角：不再套一层遮罩（旋转时遮罩图层的边缘会显出细线）。
      } else {
        content = kSoftClip ? SoftClipRRect(radius: radius, child: content) : ClipRRect(borderRadius: radius, child: content);
      }
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
  const Glass({
    super.key,
    required this.radius,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.shadows,
    this.insets,
    this.alignment,
    this.legible = false,
    this.child,
  });

  final double radius;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final List<Shadow2>? shadows;
  final List<Shadow2>? insets;
  final AlignmentGeometry? alignment;

  /// 承载文字的玻璃，见 [LiquidGlassBackdrop.legible]。
  final bool legible;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = GlassScope.of(context);
    if (enabled && LiquidGlassShader.available) {
      return _shaderGlass(
        radius: radius,
        material: GlassScope.materialOf(context),
        dark: p.isDark,
        width: width,
        height: height,
        padding: padding,
        alignment: alignment,
        legible: legible,
        child: child,
      );
    }
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

/// 播放页功能卡片、歌词页控制卡片使用的液态玻璃。不支持着色器时退回通透的毛玻璃加高光描边。
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({super.key, required this.radius, this.width, this.height, this.padding, this.child});

  final double radius;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = BorderRadius.circular(radius);
    final dark = p.isDark;
    // 关闭毛玻璃时退回半透明实色，保证内容可读。
    final blur = GlassScope.of(context);
    if (blur && LiquidGlassShader.available) {
      return _shaderGlass(
        radius: radius,
        material: GlassScope.materialOf(context),
        dark: p.isDark,
        width: width,
        height: height,
        padding: padding,
        child: child,
      );
    }
    final fill = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: blur
          ? (dark
                ? const [Color.fromRGBO(255, 255, 255, 0.16), Color.fromRGBO(255, 255, 255, 0.05)]
                : const [Color.fromRGBO(255, 255, 255, 0.42), Color.fromRGBO(255, 255, 255, 0.14)])
          : (dark ? const [Color(0xE62A2B30), Color(0xE6222327)] : const [Color(0xEBFFFFFF), Color(0xE6F4F5F8)]),
    );
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(gradient: fill, borderRadius: r),
      child: child,
    );
    content = CustomPaint(foregroundPainter: _SpecularRim(r, dark), child: content);
    if (blur) {
      content = ClipRRect(
        borderRadius: r,
        child: BackdropGroup.of(context) != null
            ? BackdropFilter.grouped(filter: _liquidFilter, child: content)
            : BackdropFilter(filter: _liquidFilter, child: content),
      );
    }
    content = CustomPaint(
      painter: _OuterShadowPainter(r, [
        Shadow2(0, 12, 32, Color.fromRGBO(0, 0, 0, dark ? 0.32 : 0.10)),
        Shadow2(0, 1, 2, Color.fromRGBO(0, 0, 0, dark ? 0.2 : 0.05)),
      ], clipInside: true),
      child: content,
    );
    return width != null || height != null ? SizedBox(width: width, height: height, child: content) : content;
  }
}

final ui.ImageFilter _liquidFilter = ui.ImageFilter.compose(
  outer: ui.ColorFilter.matrix(saturateMatrix(1.8)),
  inner: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.clamp),
);

/// 玻璃边缘的高光：左上亮、右下次亮、中段淡，模拟光线在弧面边缘的折射；内侧再加一道顶部柔光。
class _SpecularRim extends CustomPainter {
  _SpecularRim(this.radius, this.dark);

  final BorderRadius radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(0.6);
    final a = dark ? 0.55 : 0.95;
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromRGBO(255, 255, 255, a),
            Color.fromRGBO(255, 255, 255, a * 0.18),
            Color.fromRGBO(255, 255, 255, a * 0.12),
            Color.fromRGBO(255, 255, 255, a * 0.6),
          ],
          stops: const [0, 0.35, 0.65, 1],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRRect(radius.toRRect(rect));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.5),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.fromRGBO(255, 255, 255, dark ? 0.08 : 0.22), const Color.fromRGBO(255, 255, 255, 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.5)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpecularRim old) => old.dark != dark || old.radius != radius;
}
