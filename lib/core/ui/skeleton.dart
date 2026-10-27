import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// 骨架屏：按页面内容的真实形状排布的占位块，上面有一道从左向右扫过的柔和高光。
///
/// - [SkeletonList]：歌曲 / 歌单行（封面 + 两行文字）；
/// - [SkeletonComments]：评论（圆形头像 + 昵称 + 长短不一的正文）；
/// - [SkeletonHome]：首页（推荐大卡片、歌单方块、歌曲行），区分移动端与桌面端。

/// 扫光：用一道移动的渐变覆盖子组件中不透明的部分。只在加载期间存在，内容出现后随骨架一起移除。
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final glow = p.isDark ? const Color(0x1AFFFFFF) : const Color(0x99FFFFFF);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          // 高光带宽约为组件宽度的 40%，从左外侧扫到右外侧，末尾停顿一会儿。
          final t = Curves.easeInOutSine.transform((_c.value * 1.25).clamp(0.0, 1.0));
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [glow.withValues(alpha: 0), glow, glow.withValues(alpha: 0)],
              stops: const [0.3, 0.5, 0.7],
              transform: _Slide(-1.2 + 2.4 * t),
            ).createShader(r),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _Slide extends GradientTransform {
  const _Slide(this.f);

  final double f;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(bounds.width * f, 0, 0);
}

/// 一块占位。
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 12, this.radius, this.circle = false, this.widthFactor});

  final double? width;
  final double height;
  final double? radius;
  final bool circle;

  /// 占父级宽度的比例（用于文字行）。
  final double? widthFactor;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: p.skeleton,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius ?? height / 2),
      ),
      child: SizedBox(width: width, height: height),
    );
    if (widthFactor == null) return box;
    return FractionallySizedBox(widthFactor: widthFactor, alignment: Alignment.centerLeft, child: box);
  }
}

/// 每行文字占位的长度各不相同，看起来更像真实内容。
const _titleWidths = [0.62, 0.48, 0.72, 0.55, 0.66, 0.42, 0.58, 0.7];
const _subWidths = [0.34, 0.28, 0.4, 0.24, 0.36, 0.3, 0.26, 0.38];

/// 歌曲 / 歌单行占位：封面 + 标题 + 副标题。
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.padding = const EdgeInsets.symmetric(horizontal: 4)});

  final int count;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: padding,
        child: Column(children: [for (var i = 0; i < count; i++) _row(i)]),
      ),
    );
  }

  static Widget _row(int i) => SizedBox(
    height: 64,
    child: Row(
      children: [
        const Bone(width: 46, height: 46, radius: 10),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Bone(height: 13, widthFactor: _titleWidths[i % _titleWidths.length]),
              const SizedBox(height: 9),
              Bone(height: 10, widthFactor: _subWidths[i % _subWidths.length]),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 评论占位：圆形头像 + 昵称 + 两到三行正文。
class SkeletonComments extends StatelessWidget {
  const SkeletonComments({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    const lines = [
      [0.94, 0.62],
      [0.88, 0.95, 0.4],
      [0.7],
      [0.92, 0.55],
      [0.96, 0.9, 0.3],
    ];
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Bone(width: 38, height: 38, circle: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Bone(width: 64.0 + (i * 23) % 40, height: 11),
                            const Spacer(),
                            const Bone(width: 30, height: 11),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Bone(width: 48.0 + (i * 17) % 24, height: 9),
                        for (final w in lines[i % lines.length]) ...[const SizedBox(height: 10), Bone(height: 12, widthFactor: w)],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 首页占位：与真实首页相同的排布（推荐大卡片、“歌单精选”方块、“最近播放”行）。
class SkeletonHome extends StatelessWidget {
  const SkeletonHome({super.key, this.desktop = false});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    Widget title() => const Padding(padding: EdgeInsets.only(top: 28, bottom: 14), child: Bone(width: 110, height: 20, radius: 8));
    Widget tile() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AspectRatio(aspectRatio: 1, child: Bone(radius: 20)),
        const SizedBox(height: 10),
        const Bone(height: 13, widthFactor: 0.82),
        const SizedBox(height: 7),
        const Bone(height: 10, widthFactor: 0.4),
      ],
    );
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: desktop ? 0 : 20),
          if (desktop)
            const SizedBox(
              height: 230,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 2, child: Bone(radius: 28)),
                  SizedBox(width: 20),
                  Expanded(child: Bone(radius: 28)),
                ],
              ),
            )
          else
            const SizedBox(height: 196, child: Bone(radius: 28)),
          title(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < (desktop ? 6 : 3); i++) ...[if (i > 0) const SizedBox(width: 16), Expanded(child: tile())],
            ],
          ),
          title(),
          for (var i = 0; i < (desktop ? 4 : 3); i++) SkeletonList._row(i),
        ],
      ),
    );
  }
}
