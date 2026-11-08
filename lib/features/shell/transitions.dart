import 'package:flutter/cupertino.dart';

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
        // 组件树结构保持不变（只改参数），页面状态不会因为动画而重建。不做缩放：连续缩放时满屏文字每帧都要重新光栅化。
        return Opacity(
          opacity: (fade * (1 - s)).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.translationValues(0, 22 * (1 - rise) - 8 * s, 0),
            child: child,
          ),
        );
      },
      child: child,
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
                    transform: Matrix4.translationValues(0, 18 * t, 0),
                    child: child,
                  );
                },
                child: widget.children[i],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 移动端的页面：iOS 式从右侧滑入，被覆盖的页面同时向左平移（保留从左边缘右滑返回）。
///
/// 不对整页做缩放：Impeller 按“字号 × 缩放比例”光栅化字形，整页连续缩放时每一帧都要把满屏的文字重新
/// 光栅化一遍。三星 S23 Ultra 上实测，去掉缩放后同样 16 次页面切换的掉帧从约 300 帧降到约 45 帧。
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
}
