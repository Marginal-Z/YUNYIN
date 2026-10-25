import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// 页面光晕背景：三团椭圆 radial-gradient 叠在底色上。
class GlowBackground extends StatelessWidget {
  const GlowBackground({
    super.key,
    required this.color,
    required this.glows,
    this.scale = 1,
    this.child,
  });

  /// 页面通用背景（蓝 / 桃 / 薄荷）。
  factory GlowBackground.page(BuildContext context, {double scale = 1, Widget? child}) {
    final p = Palette.of(context);
    return GlowBackground(color: p.bg, glows: p.glows, scale: scale, child: child);
  }

  /// 播放页背景（薄荷 / 金 / 天蓝）。
  factory GlowBackground.player(BuildContext context, {double scale = 1, Widget? child}) {
    final p = Palette.of(context);
    return GlowBackground(color: p.playerBg, glows: p.playerGlows, scale: scale, child: child);
  }

  final Color color;
  final List<Glow> glows;

  /// 桌面端使用放大的光晕（设计稿中桌面端为移动端的 2.4 倍）。
  final double scale;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final bg = RepaintBoundary(
      child: CustomPaint(painter: _GlowPainter(color, glows, scale), child: const SizedBox.expand()),
    );
    if (child == null) return bg;
    return Stack(fit: StackFit.passthrough, children: [Positioned.fill(child: bg), child!]);
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.color, this.source, this.scale) : glows = [for (final g in source) g.scaled(scale)];

  final Color color;
  final List<Glow> source;
  final double scale;
  final List<Glow> glows;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = color);
    canvas.save();
    canvas.clipRect(rect);
    // CSS 中后声明的渐变在下层。
    for (final g in glows.reversed) {
      final center = Offset(size.width * g.cx, size.height * g.cy);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(1, g.ry / g.rx);
      final shader = RadialGradient(
        colors: [g.color, g.color.withValues(alpha: 0)],
        stops: const [0, 0.72],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: g.rx));
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: g.rx * 2, height: g.rx * 2),
        Paint()..shader = shader,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.color != color || !identical(old.source, source) || old.scale != scale;
}
