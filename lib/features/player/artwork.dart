import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/cover_colors.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';

/// 播放页的封面区域，按 [PlayerStyle] 显示为大封面、黑胶唱片或光盘（沉浸样式的封面由播放页铺满上半屏）。
/// 点按打开歌词，长按切换样式。
class PlayerArtwork extends StatelessWidget {
  const PlayerArtwork({super.key, required this.song, required this.size, required this.style});

  final Song song;
  final double size;
  final PlayerStyle style;

  @override
  Widget build(BuildContext context) {
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final Widget art = switch (style) {
      PlayerStyle.vinyl => _Vinyl(song: song, size: size, playing: playing),
      PlayerStyle.disc => _Disc(song: song, size: size, playing: playing),
      _ => Hero(
        tag: 'cover',
        child: _CoverArt(song: song, size: size, playing: playing),
      ),
    };
    return Pressable(onTap: () => openLyrics(context), onLongPress: () => pickPlayerStyle(context), scale: 1, semanticLabel: '封面，点按查看歌词，长按切换播放样式', child: art);
  }
}

/// 选择播放页样式。
Future<void> pickPlayerStyle(BuildContext context) async {
  final s = context.read<AppSettings>();
  final v = await showOptions<PlayerStyle>(context, title: '播放样式', options: [for (final st in PlayerStyle.values) (st, st.label)], selected: s.playerStyle);
  if (v != null) s.setPlayerStyle(v);
}

/// 大封面：暂停时轻微缩小，播放时以弹簧曲线放大回来。
class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.song, required this.size, required this.playing});

  final Song song;
  final double size;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: playing ? 1 : 0.88,
      duration: const Duration(milliseconds: 520),
      curve: playing ? Curves.easeOutBack : Curves.easeOutCubic,
      child: Cover(
        song.coverUrl,
        size: size,
        radius: 30,
        imageSize: 800,
        shadows: [
          Shadow2(0, 28, 56, CoverThemed.shadowOf(context).withValues(alpha: playing ? 0.35 : 0.2)),
          const Shadow2(0, 4, 10, Color.fromRGBO(0, 0, 0, 0.08)),
        ],
      ),
    );
  }
}

/// 播放时匀速旋转、暂停时停在当前角度的容器。
class _Spin extends StatefulWidget {
  const _Spin({required this.playing, required this.period, required this.child});

  final bool playing;
  final Duration period;
  final Widget child;

  @override
  State<_Spin> createState() => _SpinState();
}

class _SpinState extends State<_Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(_Spin old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 唱片本身单独成层，旋转只改变变换，不重绘纹路。
    return RotationTransition(
      turns: _c,
      child: RepaintBoundary(child: widget.child),
    );
  }
}

/// 黑胶唱片：深色唱片带细密纹路，封面作为中心标签；高光不随唱片转动；唱臂在播放时落到唱片上。
class _Vinyl extends StatelessWidget {
  const _Vinyl({required this.song, required this.size, required this.playing});

  final Song song;
  final double size;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final disc = size * 0.86;
    final label = disc * 0.4;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: size * 0.03,
            top: (size - disc) / 2,
            width: disc,
            height: disc,
            child: Stack(
              children: [
                // 投影。
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 36, offset: const Offset(0, 18))],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: _Spin(
                    playing: playing,
                    period: const Duration(seconds: 12),
                    child: Stack(
                      children: [
                        Positioned.fill(child: CustomPaint(painter: _GroovePainter())),
                        Center(
                          child: ClipOval(
                            child: SizedBox(width: label, height: label, child: CoverImage(song.coverUrl, imageSize: 400)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 固定的高光与中心轴。
                Positioned.fill(
                  child: IgnorePointer(child: CustomPaint(painter: _VinylShinePainter(label / disc))),
                ),
              ],
            ),
          ),
          // 唱臂：转轴在右上角，播放时转入唱片。
          Positioned(
            left: size * 0.74,
            top: -size * 0.02,
            width: size * 0.26,
            height: size * 0.72,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: playing ? 0 : -0.42),
              duration: const Duration(milliseconds: 650),
              curve: playing ? Curves.easeOutBack : Curves.easeInOutCubic,
              builder: (context, angle, _) => CustomPaint(painter: _TonearmPainter(angle)),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF222225), Color(0xFF0B0B0D), Color(0xFF151517)],
          stops: [0.0, 0.7, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // 纹路：细密的同心圆，明暗交替。
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, r / 260);
    for (var i = 0; i < 46; i++) {
      final rr = r * (0.24 + 0.74 * i / 45);
      groove.color = Color.fromRGBO(255, 255, 255, i.isEven ? 0.045 : 0.02);
      canvas.drawCircle(c, rr, groove);
    }
    // 外缘与标签外圈。
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x22FFFFFF),
    );
    canvas.drawCircle(c, r * 0.23, Paint()..color = const Color(0xFF0E0E10));
  }

  @override
  bool shouldRepaint(_GroovePainter old) => false;
}

class _VinylShinePainter extends CustomPainter {
  _VinylShinePainter(this.labelFraction);

  final double labelFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    // 两道对称的扇形反光。
    canvas.save();
    canvas.clipPath(
      Path()
        ..addOval(rect)
        ..addOval(Rect.fromCircle(center: c, radius: r * labelFraction / 2 + 2))
        ..fillType = PathFillType.evenOdd,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const SweepGradient(
          colors: [Color(0x00FFFFFF), Color(0x1FFFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0x1AFFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF)],
          stops: [0.0, 0.1, 0.2, 0.5, 0.6, 0.7, 1.0],
          transform: GradientRotation(-0.9),
        ).createShader(rect),
    );
    canvas.restore();
    // 中心轴。
    canvas.drawCircle(c, r * 0.035, Paint()..color = const Color(0xFFE5E5EA));
    canvas.drawCircle(c, r * 0.015, Paint()..color = const Color(0xFF8E8E93));
  }

  @override
  bool shouldRepaint(_VinylShinePainter old) => old.labelFraction != labelFraction;
}

class _TonearmPainter extends CustomPainter {
  _TonearmPainter(this.angle);

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width * 0.62, size.width * 0.32);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);
    final shadow = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final metal = Paint()..shader = const LinearGradient(colors: [Color(0xFFF2F2F7), Color(0xFFAEAEB2)]).createShader(Rect.fromLTWH(-6, 0, 12, size.height));
    final w = size.width * 0.07;
    final arm = Path()
      ..moveTo(-w / 2, 0)
      ..lineTo(w / 2, 0)
      ..lineTo(w / 2 - size.width * 0.06, size.height * 0.78)
      ..lineTo(-w / 2 - size.width * 0.06, size.height * 0.78)
      ..close();
    canvas.drawPath(arm.shift(const Offset(3, 5)), shadow);
    canvas.drawPath(arm, metal);
    // 唱头。
    final head = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(-size.width * 0.07, size.height * 0.82), width: size.width * 0.22, height: size.height * 0.11),
      Radius.circular(size.width * 0.04),
    );
    canvas.drawRRect(head.shift(const Offset(3, 5)), shadow);
    canvas.drawRRect(head, Paint()..color = const Color(0xFF2C2C2E));
    // 转轴底座。
    final base = size.width * 0.2;
    canvas.drawCircle(const Offset(3, 5), base, shadow);
    canvas.drawCircle(
      Offset.zero,
      base,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFFFFFFFF), Color(0xFFC7C7CC), Color(0xFF8E8E93)])
            .createShader(Rect.fromCircle(center: Offset.zero, radius: base)),
    );
    canvas.drawCircle(Offset.zero, base * 0.35, Paint()..color = const Color(0xFF636366));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TonearmPainter old) => old.angle != angle;
}

/// 光盘：封面印在盘面上，中心是透明的孔与内圈；彩虹光泽随盘面转动，镜面高光固定。
class _Disc extends StatelessWidget {
  const _Disc({required this.song, required this.size, required this.playing});

  final Song song;
  final double size;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final d = size * 0.92;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: SizedBox(
          width: d,
          height: d,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 34, offset: const Offset(0, 16))],
                  ),
                ),
              ),
              Positioned.fill(
                child: ClipPath(
                  clipper: _DonutClipper(0.12),
                  child: _Spin(
                    playing: playing,
                    period: const Duration(seconds: 9),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CoverImage(song.coverUrl, imageSize: 800),
                        const CustomPaint(painter: _IridescentPainter()),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: _DiscRimPainter())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutClipper extends CustomClipper<Path> {
  _DonutClipper(this.hole);

  /// 中心孔直径占盘面直径的比例。
  final double hole;

  @override
  Path getClip(Size size) {
    final c = size.center(Offset.zero);
    return Path()
      ..addOval(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: c, radius: size.width * hole / 2))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(_DonutClipper old) => old.hole != hole;
}

class _IridescentPainter extends CustomPainter {
  const _IridescentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // 彩虹光泽。
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = const SweepGradient(
          colors: [Color(0x00FF4D6A), Color(0x30FF4D6A), Color(0x30FFD45E), Color(0x303FCDB5), Color(0x305AA9F0), Color(0x30B78CFF), Color(0x00FF4D6A)],
        ).createShader(rect),
    );
    // 内圈透明塑料环与数据区分界。
    canvas.drawCircle(c, r * 0.3, Paint()..color = const Color(0x8CE5E5EA));
    canvas.drawCircle(
      c,
      r * 0.3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x66FFFFFF),
    );
    canvas.drawCircle(
      c,
      r * 0.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x55FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_IridescentPainter old) => false;
}

class _DiscRimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // 固定的镜面高光。
    canvas.save();
    canvas.clipPath(
      Path()
        ..addOval(rect)
        ..addOval(Rect.fromCircle(center: c, radius: r * 0.12))
        ..fillType = PathFillType.evenOdd,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x40FFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0x26FFFFFF)],
          stops: [0.0, 0.35, 0.7, 1.0],
        ).createShader(rect),
    );
    canvas.restore();
    // 银色外缘。
    canvas.drawCircle(
      c,
      r - 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = const SweepGradient(colors: [Color(0xFFE5E5EA), Color(0xFF8E8E93), Color(0xFFF2F2F7), Color(0xFF8E8E93), Color(0xFFE5E5EA)])
            .createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_DiscRimPainter old) => false;
}

/// 沉浸样式的背景：低分辨率封面放大后自然柔化，再叠一层与主题对应的蒙版（不做每帧的全屏模糊）。
class ImmersiveBackdrop extends StatelessWidget {
  const ImmersiveBackdrop({super.key, required this.url, required this.dark});

  final String? url;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(scale: 1.25, child: CoverImage(url, imageSize: 50)),
          ColoredBox(color: dark ? const Color(0x8C000000) : const Color(0x99FFFFFF)),
        ],
      ),
    );
  }
}
