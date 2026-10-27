import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/palette.dart';

/// 页面光晕背景：三团椭圆 radial-gradient 叠在底色上。
class GlowBackground extends StatelessWidget {
  const GlowBackground({super.key, required this.color, required this.glows, this.scale = 1, this.flow = false, this.child});

  /// 页面通用背景（蓝 / 桃 / 薄荷）。
  factory GlowBackground.page(BuildContext context, {double scale = 1, Widget? child}) {
    final p = Palette.of(context);
    return GlowBackground(color: p.bg, glows: p.glows, scale: scale, child: child);
  }

  /// 播放页背景（薄荷 / 金 / 天蓝）。
  ///
  /// [flow] 时光晕缓慢漂移、呼吸（歌词页，与系统音乐 App 的流动背景类似）；只应在播放时开启。
  factory GlowBackground.player(BuildContext context, {double scale = 1, bool flow = false, Widget? child}) {
    final p = Palette.of(context);
    return GlowBackground(color: p.playerBg, glows: p.playerGlows, scale: scale, flow: flow, child: child);
  }

  final Color color;
  final List<Glow> glows;

  /// 桌面端使用放大的光晕（设计稿中桌面端为移动端的 2.4 倍）。
  final double scale;
  final bool flow;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final bg = RepaintBoundary(
      child: _FlowingGlow(color: color, glows: glows, scale: scale, flow: flow),
    );
    if (child == null) return bg;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: bg),
        child!,
      ],
    );
  }
}

/// 光晕层。流动时由自身的 Ticker 驱动相位，只重绘这一层；停止时保持在当前位置。
class _FlowingGlow extends StatefulWidget {
  const _FlowingGlow({required this.color, required this.glows, required this.scale, required this.flow});

  final Color color;
  final List<Glow> glows;
  final double scale;
  final bool flow;

  @override
  State<_FlowingGlow> createState() => _FlowingGlowState();
}

class _FlowingGlowState extends State<_FlowingGlow> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _phase = ValueNotifier(0);
  Duration _offset = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.flow) _ticker.start();
  }

  @override
  void didUpdateWidget(_FlowingGlow old) {
    super.didUpdateWidget(old);
    if (widget.flow && !_ticker.isActive) {
      _offset = Duration(microseconds: (_phase.value * 1e6).round());
      _ticker.start();
    } else if (!widget.flow && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) => _phase.value = (elapsed + _offset).inMicroseconds / 1e6;

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flowing = widget.flow || _phase.value > 0;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return CustomPaint(
      // 静止时按屏幕原始分辨率生成一次；流动时每帧重新生成，用一半分辨率。
      painter: _GlowPainter(widget.color, widget.glows, widget.scale, phase: flowing ? _phase : null, resolution: flowing ? dpr / 2 : dpr),
      child: const SizedBox.expand(),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.color, this.source, this.scale, {this.phase, this.resolution = 1})
    : glows = [for (final g in source) g.scaled(scale)],
      super(repaint: phase);

  final Color color;
  final List<Glow> source;
  final double scale;
  final List<Glow> glows;

  /// 流动相位（秒）；null 时静止。
  final ValueListenable<double>? phase;

  /// 生成图片的分辨率（每逻辑像素的像素数）。
  ///
  /// Impeller 每帧都会重新光栅化整个画面：直接绘制意味着每帧重新计算几块铺满窗口的径向渐变
  /// （桌面端放大 2.4 倍后尤其昂贵）。这里先把光晕画成图片，之后每帧只是一次整屏贴图。
  /// 图片分辨率不能太低：渐变自带的抖动纹理被放大后会呈现块状。
  final double resolution;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = (size.width * resolution).ceil(), h = (size.height * resolution).ceil();
    final recorder = ui.PictureRecorder();
    _draw(Canvas(recorder)..scale(w / size.width, h / size.height), size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Offset.zero & size, Paint()..filterQuality = FilterQuality.low);
    image.dispose();
  }

  void _draw(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = color);
    canvas.save();
    canvas.clipRect(rect);
    // CSS 中后声明的渐变在下层。
    final t = phase?.value ?? 0;
    for (var i = glows.length - 1; i >= 0; i--) {
      final g = glows[i];
      var center = Offset(size.width * g.cx, size.height * g.cy);
      var rx = g.rx;
      if (t > 0) {
        // 每团光晕沿各自周期（19 / 26 / 33 秒…）的李萨如轨迹漂移，并轻微呼吸。
        final period = 19.0 + i * 7;
        final a = t * 2 * math.pi / period + i * 2.1;
        center += Offset(math.sin(a) * size.shortestSide * 0.12, math.cos(a * 0.8 + i) * size.shortestSide * 0.09);
        rx *= 1 + 0.1 * math.sin(a * 1.3 + i);
      }
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(1, g.ry / g.rx);
      final shader = RadialGradient(
        colors: [g.color, g.color.withValues(alpha: 0)],
        stops: const [0, 0.72],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: rx));
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: rx * 2), Paint()..shader = shader);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.color != color || !identical(old.source, source) || old.scale != scale || old.phase != phase || old.resolution != resolution;
}
