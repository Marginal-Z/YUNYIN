import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 启动动画（按《云音 · 启动页设计稿》的“启动动画”“桌面端启动窗口”“动效关键帧与参数”实现）。
///
/// 品牌红背景上，白色云朵 Logo 下落、挤压、二次弹跳，落地时扩散三圈波纹并弹出六个彩色碎片；
/// “云音”逐字弹入，标语淡入；云里的三根均衡条一直跳动。播完后整体向上淡出（0.3 秒）露出首页。
///
/// - 首次启动播完整版（约 2.4 秒）；之后冷启动只播缩短版（约 1 秒，只有落地与字标）；
/// - 移动端右上角可“跳过”，底部是跳动圆点；桌面端底部是进度条；
/// - 系统开启“减少动态效果”时不播放动画，直接显示最终画面后淡出。
///
/// 关键帧沿用设计稿中 5.2 秒循环的百分比，按 [_ms] 换算为毫秒。
class Splash extends StatefulWidget {
  const Splash({
    super.key,
    required this.full,
    required this.desktop,
    required this.version,
    required this.onDone,
    this.systemSplash = false,
    this.uiScale = 1,
  });

  /// 系统已显示过启动图（Android）：首帧与系统启动图衔接。
  final bool systemSplash;

  /// 界面整体缩放倍数，用于把系统启动图的尺寸换算为界面尺寸。
  final double uiScale;

  /// 完整版（首次启动）还是缩短版。
  final bool full;
  final bool desktop;
  final String version;
  final VoidCallback onDone;

  @override
  State<Splash> createState() => _SplashState();
}

/// 品牌红与碎片配色（设计稿“Logo 构成与色彩”）。
const _red = Color(0xFFDC1031);
const _yellow = Color(0xFFFFD45E);
const _cream = Color(0xFFFFF4E8);
const _teal = Color(0xFF3BB7A5);
const _sky = Color(0xFF5AA9F0);

class _SplashState extends State<Splash> with TickerProviderStateMixin {
  /// 设计稿 1% 对应的毫秒数：完整版让标语在 2.4 秒时落定（63%），缩短版让字标在约 1 秒时落定（49%）。
  late final double _ms = widget.full ? 2400 / 63 : 1000 / 49;

  /// 主时间轴（毫秒，持续增长；循环动效对它取模）。
  late final AnimationController _clock = AnimationController.unbounded(vsync: this);
  late final AnimationController _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  bool _leaving = false;

  double get _endMs => (widget.full ? 63 : 49) * _ms + 250;

  @override
  void initState() {
    super.initState();
    _exit.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_clock.isAnimating || _leaving) return;
    if (MediaQuery.of(context).disableAnimations) {
      // 减少动态效果：显示最终画面，稍候淡出。
      _clock.value = _endMs;
      _timer = Timer(const Duration(milliseconds: 700), _leave);
      return;
    }
    // 以真实时间推进：unbounded 控制器从 0 线性增长到很大的值，数值即毫秒。
    _clock.animateTo(600000, duration: const Duration(seconds: 600), curve: Curves.linear);
    _timer = Timer(Duration(milliseconds: _endMs.round()), _leave);
  }

  Timer? _timer;

  void _leave() {
    _timer?.cancel();
    if (_leaving || !mounted) return;
    _leaving = true;
    _exit.forward();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_clock, _exit]),
      builder: (context, _) {
        final e = Curves.easeInCubic.transform(_exit.value);
        return IgnorePointer(
          ignoring: _leaving,
          child: Opacity(
            opacity: 1 - e,
            child: Transform.translate(offset: Offset(0, -14 * e), child: _frame(size, pad, _clock.value)),
          ),
        );
      },
    );
  }

  Widget _frame(Size size, EdgeInsets pad, double t) {
    final desktop = widget.desktop;
    // 设计稿按 390 × 844（手机）与 1280 × 820（桌面）绘制；小屏、横屏等比缩小，内容始终居中。
    final k = desktop ? (size.height / 820).clamp(0.7, 1.0) : math.min(size.width / 390, size.height / 760).clamp(0.55, 1.0);
    final cx = size.width / 2;
    final logoTop = desktop ? size.height * 0.232 : math.min(size.height * 0.284, size.height - 520 * k);
    final logoW = 220 * k, logoH = 190 * k;
    final center = Offset(cx, logoTop + logoH / 2);
    final p = t / _ms; // 当前进度（设计稿百分比）
    final children = <Widget>[];

    // 两团缓慢漂移的白色圆（6 秒循环）。
    Offset drift(double phase) {
      final a = Curves.easeInOut.transform(_tri(((t / 1000 + phase) % 6) / 6));
      return Offset(18 * a, -26 * a);
    }

    final big = (desktop ? 608 : 320) * k, small = (desktop ? 513 : 270) * k;
    children.add(Positioned(left: -big * 0.34 + drift(0).dx, bottom: -big * 0.11 - drift(0).dy, child: _circle(big, const Color(0x12FFFFFF))));
    children.add(Positioned(right: -small * 0.44 - drift(3).dx, top: (desktop ? 76 : 40) * k + drift(3).dy, child: _circle(small, const Color(0x12FFFFFF))));

    // 落地波纹：三圈，依次延迟 0.22 秒（设计稿时间）。
    if (widget.full) {
      for (var i = 0; i < 3; i++) {
        final q = p - i * 220 / 52;
        final op = _kf(q, const [(0, 0), (12, 0), (14, 0.6), (55, 0)]);
        if (op <= 0) continue;
        final s = _kf(q, const [(0, 0.55), (12, 0.55), (14, 0.6), (55, 2.7)]);
        children.add(
          Positioned(
            left: center.dx - logoW / 2,
            top: center.dy - logoH / 2,
            width: logoW,
            height: logoH,
            child: Transform.scale(
              scale: s,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: OvalBorder(
                    side: BorderSide(color: Colors.white.withValues(alpha: op), width: 2),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // 地面阴影。
    final shadowOp = _kf(p, const [(0, 0), (3, 0), (13, 0.36), (21, 0.16), (28, 0.3), (34, 0.2), (39, 0.26)]);
    final shadowS = _kf(p, const [(0, 0.4), (3, 0.4), (13, 1.15), (21, 0.6), (28, 1.05), (34, 0.85), (39, 1)]);
    children.add(
      Positioned(
        left: cx - 65 * k,
        top: logoTop + 196 * k,
        width: 130 * k,
        height: 18 * k,
        child: Opacity(
          opacity: shadowOp,
          child: Transform.scale(
            scale: shadowS,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 6 * k, sigmaY: 6 * k),
              child: const DecoratedBox(
                decoration: ShapeDecoration(color: Color(0x8C5A000F), shape: OvalBorder()),
              ),
            ),
          ),
        ),
      ),
    );

    // 碎片：从 Logo 中心弹出，落定后轻轻摆动。
    if (widget.full) {
      final m = desktop ? 1.6 : 1.0;
      const pops = [
        (26.0, -140.0, -128.0, 0),
        (44.0, 132.0, -150.0, 1),
        (30.0, -152.0, 74.0, 2),
        (14.0, 124.0, 112.0, 3),
        (22.0, -104.0, 176.0, 4),
        (30.0, 104.0, 178.0, 5),
      ];
      for (final (sz, tx, ty, i) in pops) {
        final q = p - i * 40 / 52;
        final op = _kf(q, const [(0, 0), (12, 0), (24, 1)]);
        if (op <= 0) continue;
        final f = _kf(q, const [(0, 0), (12, 0), (24, 1.12), (32, 1), (38, 1)]);
        final s = _kf(q, const [(0, 0), (12, 0), (24, 1.35), (32, 0.86), (38, 1)]);
        final bob = Curves.easeInOut.transform(_tri(((t / 1000 + i * 0.4) % 2.4) / 2.4));
        final d = sz * k;
        children.add(
          Positioned(
            left: center.dx + tx * m * k * f - d / 2,
            top: center.dy + ty * m * k * f - d / 2 - 9 * k * bob,
            width: d,
            height: d,
            child: Opacity(
              opacity: op,
              child: Transform.rotate(
                angle: bob * 10 * math.pi / 180,
                child: Transform.scale(scale: s, child: _particle(i, d)),
              ),
            ),
          ),
        );
      }
    }

    // Logo：下落、挤压、二次弹跳（变换原点在底边中点）。
    // 有系统启动图的平台（Android）不从屏幕外落下：首帧与系统启动图的云朵完全重合（屏幕正中、宽约 93dp），
    // 随后向上跃起到 Logo 位置再落地弹跳，系统启动图与启动动画之间不会跳变。
    var y = _kf(p, const [(0, -470), (13, 0), (21, -58), (28, 0), (34, -16), (39, 0)], _logoCurves);
    var sx = _kf(p, const [(0, 0.86), (13, 1.22), (21, 0.9), (28, 1.1), (34, 0.97), (39, 1.03), (44, 1)], _logoCurves);
    var sy = _kf(p, const [(0, 1.16), (13, 0.78), (21, 1.12), (28, 0.9), (34, 1.04), (39, 0.97), (44, 1)], _logoCurves);
    var logoOp = _kf(p, const [(0, 0), (3, 1)]);
    if (widget.systemSplash) {
      // 云朵在画布中宽 56/72，系统启动图中宽 56 × 1.6667dp；界面经过整体缩放时换算回屏幕尺寸。
      final cloudW = logoW * 56 / 72;
      final s0 = (56 * 1.6667 / widget.uiScale) / cloudW;
      // 变换原点在底边中点：缩放 s0 后云朵中心 = logoTop + logoH + y·k − logoH·s0/2，令其等于屏幕中心。
      final y0 = (size.height / 2 - logoTop - logoH + logoH * s0 / 2) / k;
      final grow = _kf(p, [(0, s0), (9, 1)], const [Curves.easeOutCubic]);
      y = _kf(
        p,
        [(0, y0), (9, -90), (13, 0), (21, -58), (28, 0), (34, -16), (39, 0)],
        const [Curves.easeOutCubic, Curves.easeInQuad, Curves.easeOutQuad, Curves.easeInQuad, Curves.easeOutQuad, Curves.easeInQuad],
      );
      final squashX = _kf(p, const [(0, 1), (9, 1), (13, 1.22), (21, 0.9), (28, 1.1), (34, 0.97), (39, 1.03), (44, 1)], const [Curves.linear, ..._logoCurves]);
      final squashY = _kf(p, const [(0, 1), (9, 1), (13, 0.78), (21, 1.12), (28, 0.9), (34, 1.04), (39, 0.97), (44, 1)], const [Curves.linear, ..._logoCurves]);
      sx = squashX * grow;
      sy = squashY * grow;
      logoOp = 1;
    }
    children.add(
      Positioned(
        left: cx - logoW / 2,
        top: logoTop,
        width: logoW,
        height: logoH,
        child: Opacity(
          opacity: logoOp,
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.translationValues(0, y * k, 0)..scaleByDouble(sx, sy, 1, 1),
            child: CustomPaint(painter: _CloudPainter(t / 1000)),
          ),
        ),
      ),
    );

    // 字标“云音”：逐字弹入（第二个字延迟 0.12 秒）。
    final wordTop = logoTop + 246 * k;
    final fontSize = 58 * k;
    Widget char(String c, double delay) {
      final q = p - delay * 1000 / 52;
      final op = _kf(q, const [(0, 0), (26, 0), (36, 1)]);
      final dy = _kf(q, const [(0, 46), (26, 46), (36, -16), (43, 4), (49, 0)]);
      final wx = _kf(q, const [(0, 0.4), (26, 0.4), (36, 1.18), (43, 0.95), (49, 1)]);
      final wy = _kf(q, const [(0, 0.5), (26, 0.5), (36, 0.9), (43, 1.06), (49, 1)]);
      return Opacity(
        opacity: op,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(0, dy * k, 0)..scaleByDouble(wx, wy, 1, 1),
          child: Text(
            c,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: Colors.white, height: 1.1, letterSpacing: fontSize * 0.08),
          ),
        ),
      );
    }

    children.add(
      Positioned(
        left: 0,
        right: 0,
        top: wordTop,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [char('云', 0), char('音', 0.12)]),
      ),
    );

    // 标语（只在完整版出现）。
    if (widget.full) {
      final op = _kf(p, const [(0, 0), (48, 0), (58, 1)]);
      final dy = _kf(p, const [(0, 18), (48, 18), (58, -4), (63, 0)]);
      children.add(
        Positioned(
          left: 0,
          right: 0,
          top: logoTop + 332 * k + dy * k,
          child: Opacity(
            opacity: op,
            child: Text(
              '听见好音乐',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16 * k, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 16 * k * 0.32),
            ),
          ),
        ),
      );
    }

    // 底部：桌面端进度条，移动端跳动圆点。
    if (desktop) {
      final f = _kf(((t % 2600) / 2600) * 100, const [(0, 0), (55, 0.72), (100, 1)], const [Curves.easeInOut, Curves.easeInOut]);
      children.add(
        Positioned(
          left: cx - 130,
          width: 260,
          bottom: 118 * k,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: ColoredBox(
              color: const Color(0x47FFFFFF),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: f,
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ),
        ),
      );
    } else {
      children.add(
        Positioned(
          left: 0,
          right: 0,
          bottom: 96 * k + pad.bottom * 0.5,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Builder(
                  builder: (_) {
                    final q = (((t / 1000 - i * 0.15) % 0.9 + 0.9) % 0.9) / 0.9 * 100;
                    final a = _kf(q, const [(0, 0), (40, 1), (80, 0), (100, 0)], const [Curves.easeInOut, Curves.easeInOut, Curves.linear]);
                    return Transform.translate(
                      offset: Offset(0, -12 * a),
                      child: Transform.scale(
                        scale: 1 + 0.2 * a,
                        child: _circle(9, Colors.white.withValues(alpha: 0.65 + 0.35 * a)),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      );
    }

    // 版本号。
    if (widget.version.isNotEmpty) {
      children.add(
        Positioned(
          left: 0,
          right: 0,
          bottom: 40 * k + pad.bottom * 0.5,
          child: Text(
            '版本 ${widget.version}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, letterSpacing: 12 * 0.08, color: Color(0xEBFFFFFF)),
          ),
        ),
      );
    }

    // 跳过（移动端）。
    if (!desktop) {
      children.add(
        Positioned(
          right: 16,
          top: pad.top + 22,
          child: Semantics(
            button: true,
            label: '跳过启动动画',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: _leave,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x47780014),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x4DFFFFFF)),
                ),
                child: const Text(
                  '跳过',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: '云音正在启动',
      child: SizedBox.expand(
        child: DecoratedBox(
          decoration: const BoxDecoration(color: _red),
          child: CustomPaint(
            painter: _BackgroundPainter(),
            child: Stack(clipBehavior: Clip.hardEdge, children: children),
          ),
        ),
      ),
    );
  }

  static Widget _circle(double d, Color c) => SizedBox(
    width: d,
    height: d,
    child: DecoratedBox(
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    ),
  );

  static Widget _particle(int i, double d) => switch (i) {
    0 || 3 => _circle(d, _yellow),
    1 => DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _cream, width: d * 6 / 44),
      ),
    ),
    2 => Transform.rotate(
      angle: math.pi / 4,
      child: DecoratedBox(
        decoration: BoxDecoration(color: _cream, borderRadius: BorderRadius.circular(d * 0.2)),
      ),
    ),
    4 => _circle(d, _teal),
    _ => _circle(d, _sky),
  };
}

/// Logo 下落各段的缓动（设计稿 cubic-bezier）：下落加速、弹起减速。
const _logoCurves = [Cubic(0.5, 0, 0.9, 0.6), Cubic(0.2, 0.7, 0.3, 1), Cubic(0.6, 0, 0.9, 0.5), Cubic(0.2, 0.7, 0.3, 1), Curves.easeIn, Curves.linear];

/// 三角波：0 → 1 → 0。
double _tri(double x) => x < 0.5 ? x * 2 : (1 - x) * 2;

/// 关键帧插值：[frames] 为（百分比，数值），超出两端取端点值；[curves] 为各段缓动（缺省线性）。
double _kf(double p, List<(num, num)> frames, [List<Curve> curves = const []]) {
  if (p <= frames.first.$1) return frames.first.$2.toDouble();
  for (var i = 1; i < frames.length; i++) {
    final (a, va) = frames[i - 1];
    final (b, vb) = frames[i];
    if (p <= b) {
      var f = (p - a) / (b - a);
      if (i - 1 < curves.length) f = curves[i - 1].transform(f.clamp(0.0, 1.0));
      return va + (vb - va) * f;
    }
  }
  return frames.last.$2.toDouble();
}

/// 背景：顶部高光与底部暗角两层径向渐变（设计稿 radial-gradient）。
class _BackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset c, double rx, double ry, Color color) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(1, ry / rx);
      canvas.drawCircle(Offset.zero, rx, Paint()..shader = ui.Gradient.radial(Offset.zero, rx, [color, color.withValues(alpha: 0)], const [0, 0.7]));
      canvas.restore();
    }

    glow(Offset(size.width / 2, size.height * 0.22), 420, 380, const Color.fromRGBO(255, 130, 150, 0.55));
    glow(Offset(size.width / 2, size.height * 1.12), 520, 420, const Color.fromRGBO(150, 0, 30, 0.45));
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => false;
}

/// 白色云朵 Logo：1 个圆角矩形 + 2 个圆，镂空 3 根跳动的均衡条（72 × 62 画布）。
class _CloudPainter extends CustomPainter {
  _CloudPainter(this.seconds);

  final double seconds;

  static const _bars = [(38.0, 49.0, 14.0, 0.0), (47.0, 44.0, 24.0, 0.15), (56.0, 47.0, 18.0, 0.3)];

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 72, sy = size.height / 62;
    Rect r(double x, double y, double w, double h) => Rect.fromLTWH((x - 14) * sx, (y - 18) * sy, w * sx, h * sy);
    final cloud = Path()
      ..addRRect(RRect.fromRectAndRadius(r(22, 50, 56, 22), Radius.circular(11 * sx)))
      ..addOval(r(42 - 13, 48 - 13, 26, 26))
      ..addOval(r(60 - 16, 42 - 16, 32, 32));
    // 柔和投影（drop-shadow 0 14 22）。
    canvas.drawPath(
      cloud.shift(const Offset(0, 14)),
      Paint()
        ..color = const Color.fromRGBO(110, 0, 20, 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawPath(cloud, Paint()..color = Colors.white);
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final (x, y, h, delay) in _bars) {
      // 均衡条以 1.1 秒循环缩放：0.45 → 1.25 → 0.75 → 1.05 → 0.45。
      final q = (((seconds - delay) % 1.1 + 1.1) % 1.1) / 1.1 * 100;
      final s = _kf(q, const [(0, 0.45), (35, 1.25), (60, 0.75), (80, 1.05), (100, 0.45)], const [_bounce, _bounce, _bounce, _bounce]);
      final rect = r(x, y, 6, h);
      final scaled = Rect.fromCenter(center: rect.center, width: rect.width, height: rect.height * s);
      canvas.drawRRect(RRect.fromRectAndRadius(scaled, Radius.circular(3 * sx)), clear);
    }
    canvas.restore();
  }

  static const _bounce = Cubic(0.3, 1.4, 0.5, 1);

  @override
  bool shouldRepaint(_CloudPainter old) => old.seconds != seconds;
}
