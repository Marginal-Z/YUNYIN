import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/motion.dart';
import 'assistant_page.dart';

/// 云音助手悬浮球：浮在页面上，按住可以拖到任意位置，松手后吸附到最近的左右边缘并记住位置。
/// 点按打开助手，长按打开并立即开始听。
///
/// 外观是主题色的光泽球体，中间是声波标志；听、思考时声波跳动、外圈有一道流光转动。
/// 平时不播放任何动画（不会让页面滚动时多画一层动画）。
class AssistantBall extends StatefulWidget {
  const AssistantBall({super.key, required this.top, required this.bottom});

  /// 可停靠范围的上下边界（离屏幕顶部、底部的距离，避开状态栏、底部导航栏与迷你播放条）。
  final double top;
  final double bottom;

  static const size = 50.0;

  @override
  State<AssistantBall> createState() => _AssistantBallState();
}

class _AssistantBallState extends State<AssistantBall> with SingleTickerProviderStateMixin {
  /// 拖动中的位置（左上角）；为 null 时按保存的停靠位置显示。
  Offset? _drag;
  bool _pressed = false;
  late final AnimationController _live = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  static const _margin = 10.0;

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  void _sync(bool active) {
    if (active && !_live.isAnimating) _live.repeat();
    if (!active && _live.isAnimating) _live.stop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AssistantSettings>();
    final status = context.select<AssistantController, AssistantStatus>((a) => a.status);
    final active = status != AssistantStatus.idle;
    _sync(active);
    final accent = Palette.of(context).accent;
    return LayoutBuilder(
      builder: (context, c) {
        const d = AssistantBall.size;
        final minY = widget.top;
        final maxY = (c.maxHeight - widget.bottom - d).clamp(minY, double.infinity);
        final docked = Offset(s.ballLeft ? _margin : c.maxWidth - d - _margin, minY + (maxY - minY) * s.ballY);
        final pos = _drag ?? docked;
        return Stack(
          children: [
            AnimatedPositioned(
              // 拖动时跟手，松手后弹到边缘。
              duration: _drag == null ? const Duration(milliseconds: 320) : Duration.zero,
              curve: Motion.spring,
              left: pos.dx,
              top: pos.dy,
              child: GestureDetector(
                onTap: () => openAssistant(context),
                onLongPress: () => openAssistant(context, listen: true),
                onTapDown: (_) => setState(() => _pressed = true),
                onTapUp: (_) => setState(() => _pressed = false),
                onTapCancel: () => setState(() => _pressed = false),
                onPanStart: (_) => setState(() {
                  _pressed = false;
                  _drag = pos;
                }),
                onPanUpdate: (e) => setState(() {
                  final o = (_drag ?? pos) + e.delta;
                  _drag = Offset(o.dx.clamp(0.0, c.maxWidth - d), o.dy.clamp(minY, maxY));
                }),
                onPanEnd: (_) {
                  final o = _drag ?? pos;
                  setState(() => _drag = null);
                  s.setBall(left: o.dx + d / 2 < c.maxWidth / 2, y: maxY > minY ? (o.dy - minY) / (maxY - minY) : 0);
                },
                child: Semantics(
                  button: true,
                  label: '云音助手',
                  child: AnimatedScale(
                    scale: _pressed ? 0.9 : (_drag != null ? 1.08 : 1),
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: RepaintBoundary(
                      child: SizedBox.square(
                        dimension: d,
                        child: active
                            ? AnimatedBuilder(
                                animation: _live,
                                builder: (context, _) => CustomPaint(painter: AssistantOrbPainter(base: accent.base, top: accent.buttonTop, t: _live.value, active: true)),
                              )
                            : CustomPaint(painter: AssistantOrbPainter(base: accent.base, top: accent.buttonTop, t: 0, active: false)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 光泽球体：径向渐变的主体、左上角的高光、柔和的投影，中间是四根声波竖条；
/// [active] 时竖条随 [t] 起伏，外圈一道主题色流光旋转。
@visibleForTesting
class AssistantOrbPainter extends CustomPainter {
  AssistantOrbPainter({required this.base, required this.top, required this.t, required this.active});

  final Color base;
  final Color top;
  final double t;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final body = r - (active ? 3 : 1);

    // 投影。
    canvas.drawCircle(
      c + const Offset(0, 3),
      body,
      Paint()
        ..color = base.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 外圈流光（只在听、思考时）。
    if (active) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = SweepGradient(
          colors: [base.withValues(alpha: 0), Color.lerp(top, Colors.white, 0.5)!, base, base.withValues(alpha: 0)],
          stops: const [0, 0.35, 0.7, 1],
          transform: GradientRotation(t * 2 * math.pi),
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r - 1.2, ring);
    }

    // 主体：左上偏亮、右下偏深的径向渐变。
    final rect = Rect.fromCircle(center: c, radius: body);
    canvas.drawCircle(
      c,
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [Color.lerp(top, Colors.white, 0.35)!, base, Color.lerp(base, Colors.black, 0.28)!],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
    // 细边：一圈半透明的亮边，球体在深浅背景上都清楚。
    canvas.drawCircle(
      c,
      body - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    // 高光：顶部一片椭圆形的柔光。
    final gloss = Rect.fromCenter(center: c + Offset(-body * 0.12, -body * 0.42), width: body * 1.25, height: body * 0.7);
    canvas.drawOval(
      gloss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0)],
        ).createShader(gloss),
    );

    // 声波：四根圆头竖条，中间两根高。
    const heights = [0.42, 0.78, 1.0, 0.6];
    final bar = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = body * 0.13;
    final gap = body * 0.25;
    for (var i = 0; i < 4; i++) {
      final wave = active ? 0.55 + 0.45 * math.sin(2 * math.pi * (t * 2 + i * 0.23)).abs() : 1.0;
      final h = body * 0.62 * heights[i] * wave;
      final x = c.dx + (i - 1.5) * gap;
      canvas.drawLine(Offset(x, c.dy + body * 0.06 - h / 2), Offset(x, c.dy + body * 0.06 + h / 2), bar);
    }
  }

  @override
  bool shouldRepaint(AssistantOrbPainter old) => old.t != t || old.active != active || old.base != base || old.top != top;
}
