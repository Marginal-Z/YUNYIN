import 'package:flutter/cupertino.dart';

import '../../core/ui/transition_snapshot.dart';
import '../../core/ui/motion.dart';

/// 桌面端内容区的页面。
class FadePage extends Page<void> {
  const FadePage({required super.key, required this.child});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => _FadeRoute(this);
}

/// 桌面端页面切换。页面本身是透明的（共用外壳的背景），所以旧页面要先淡出，不能和新页面的文字叠在一起：
/// 新页面淡入并从下方 16 像素处升起，旧页面在前 60% 的时间里淡出并略微缩小；返回时反过来。
class _FadeRoute extends PageRoute<void> {
  _FadeRoute(FadePage page) : _child = page.child, super(settings: page);

  final Widget _child;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => _child;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      builder: (context, child) {
        final reverse = animation.status == AnimationStatus.reverse;
        // 淡入用平滑曲线，位移与缩放用弹簧：新页面升起时略微越过终点再落定。
        final fade = reverse ? Curves.easeInCubic.transform(animation.value) : Curves.easeOutCubic.transform((animation.value / 0.6).clamp(0.0, 1.0));
        final rise = reverse ? fade : Motion.spring.transform(animation.value);
        // 旧页面在前 40% 的时间里淡出，不会和新页面的文字以接近的透明度叠在一起。
        // 返回时（上层页面关闭）它随上层页面的离开平稳淡回。
        final s = secondaryAnimation.status == AnimationStatus.reverse
            ? Curves.easeIn.transform(secondaryAnimation.value)
            : Curves.easeOut.transform((secondaryAnimation.value / 0.4).clamp(0.0, 1.0));
        // 组件树结构保持不变（只改参数），页面状态不会因为动画而重建。
        final scale = (0.985 + 0.015 * rise) * (1 - 0.02 * s);
        return Opacity(
          opacity: (fade * (1 - s)).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.translationValues(0, 22 * (1 - rise), 0)..scaleByDouble(scale, scale, 1, 1),
            child: child,
          ),
        );
      },
      // 缩放与淡入作用在快照上（见 TransitionSnapshot）。
      child: TransitionSnapshot(animations: [animation, secondaryAnimation], child: child),
    );
  }
}

/// 移动端的三个标签页，各自保留状态。
///
/// 切换时两页交叉淡化，新页面从下方 8 像素处升起；未显示的标签不绘制、不响应点击，
/// 并暂停其中的动画（IndexedStack 不会暂停，隐藏标签里的骨架屏扫光等动画会让画面一直满帧重绘）。
class TabStack extends StatefulWidget {
  const TabStack({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<TabStack> createState() => _TabStackState();
}

class _TabStackState extends State<TabStack> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.tab, value: 1)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && _from != null) setState(() => _from = null);
    });
  late final CurvedAnimation _in = CurvedAnimation(parent: _c, curve: const Interval(0, 0.6, curve: Curves.easeOutCubic));
  late final Animation<double> _out = ReverseAnimation(_in);

  /// 位移与缩放用弹簧（Q 弹落定），淡入在前 60% 的时间内完成。
  late final CurvedAnimation _move = CurvedAnimation(parent: _c, curve: Motion.spring);

  /// 正在淡出的标签。
  int? _from;

  @override
  void didUpdateWidget(TabStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _from = old.index;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _move.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final from = _from;
    // 页面背景不透明：淡入时让上层的页面变透明。新标签在上层时淡入新标签，否则淡出旧标签，效果相同。
    final newOnTop = from == null || widget.index > from;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _tab(
            i,
            shown: i == widget.index || i == from,
            opacity: from == null
                ? kAlwaysCompleteAnimation
                : (i == widget.index && newOnTop ? _in : (i == from && !newOnTop ? _out : kAlwaysCompleteAnimation)),
          ),
      ],
    );
  }

  /// 组件树结构始终不变，切换标签不会重建页面。
  Widget _tab(int i, {required bool shown, required Animation<double> opacity}) {
    final current = i == widget.index;
    return TickerMode(
      enabled: shown,
      child: Offstage(
        offstage: !shown,
        child: IgnorePointer(
          ignoring: !current,
          child: ExcludeFocus(
            excluding: !current,
            child: FadeTransition(
              opacity: opacity,
              child: AnimatedBuilder(
                animation: _move,
                builder: (context, child) {
                  final t = current && _from != null ? 1 - _move.value : 0.0;
                  return Transform(
                    alignment: Alignment.topCenter,
                    transform: Matrix4.translationValues(0, 18 * t, 0)..scaleByDouble(1 - 0.02 * t, 1 - 0.02 * t, 1, 1),
                    child: child,
                  );
                },
                // 切换时缩放与淡入作用在快照上。
                child: TransitionSnapshot(animations: [_c], child: widget.children[i]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 移动端的页面：iOS 式从右侧滑入（保留从左边缘右滑返回），新页面同时从 96% 弹性放大到全尺寸，
/// 被覆盖的页面略微缩小，层次感更强、落定时带一点 Q 弹。
class SpringPage<T> extends Page<T> {
  const SpringPage({required super.key, required this.child});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _SpringPageRoute<T>(this);
}

class _SpringPageRoute<T> extends PageRoute<T> with CupertinoRouteTransitionMixin<T> {
  _SpringPageRoute(SpringPage<T> page) : super(settings: page);

  SpringPage<T> get _page => settings as SpringPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Motion.page;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    // 缩放作用在快照上（见 TransitionSnapshot）：直接缩放满屏文字时每帧都要重新光栅化，页面切换掉帧严重。
    final slide = CupertinoRouteTransitionMixin.buildPageTransitions<T>(
      this,
      context,
      animation,
      secondaryAnimation,
      TransitionSnapshot(animations: [animation, secondaryAnimation], child: child),
    );
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      builder: (context, child) {
        // 只有打开时用弹簧；手势返回与关闭时线性跟随，避免松手瞬间跳动。组件树结构始终不变。
        final forward = animation.status == AnimationStatus.forward && navigator?.userGestureInProgress != true;
        final enter = forward ? Motion.spring.transform(animation.value) : animation.value;
        final covered = Curves.easeOutCubic.transform(secondaryAnimation.value);
        final scale = (0.96 + 0.04 * enter) * (1 - 0.035 * covered);
        return Transform.scale(scale: scale, child: child);
      },
      child: slide,
    );
  }
}
