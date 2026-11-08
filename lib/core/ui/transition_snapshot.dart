import 'package:flutter/widgets.dart';

/// 动画进行时用快照绘制子组件：动画开始时把子组件画成一张位图，之后的缩放、淡入等变换都作用在这张位图上，
/// 动画结束后换回实时绘制。
///
/// Impeller 按“字号 × 缩放比例”光栅化字形：直接对满屏文字做连续缩放时，每一帧都要把所有文字重新光栅化
/// 一遍（三星 S23 Ultra 上实测 16 次页面切换掉帧约 300 帧）。改为缩放快照后视觉效果不变，开销只剩一次截图。
/// Flutter 自带的安卓缩放转场（ZoomPageTransitionsBuilder）也是这样做的。
///
/// 动画期间页面内容冻结在开始那一刻（转场只有零点几秒，看不出来）。
class TransitionSnapshot extends StatefulWidget {
  const TransitionSnapshot({super.key, required this.animations, required this.child});

  /// 其中任意一个在播放时使用快照。
  final List<Animation<double>> animations;
  final Widget child;

  @override
  State<TransitionSnapshot> createState() => _TransitionSnapshotState();
}

class _TransitionSnapshotState extends State<TransitionSnapshot> {
  final _controller = SnapshotController();

  bool get _animating => widget.animations.any((a) => a.status == AnimationStatus.forward || a.status == AnimationStatus.reverse);

  void _sync(AnimationStatus _) {
    final animating = _animating;
    // 每次开始新的动画都重新截图（页面内容可能已经变了）。
    if (animating && !_controller.allowSnapshotting) _controller.clear();
    _controller.allowSnapshotting = animating;
  }

  @override
  void initState() {
    super.initState();
    for (final a in widget.animations) {
      a.addStatusListener(_sync);
    }
    _controller.allowSnapshotting = _animating;
  }

  @override
  void didUpdateWidget(TransitionSnapshot old) {
    super.didUpdateWidget(old);
    for (final a in old.animations) {
      a.removeStatusListener(_sync);
    }
    for (final a in widget.animations) {
      a.addStatusListener(_sync);
    }
    _sync(AnimationStatus.dismissed);
  }

  @override
  void dispose() {
    for (final a in widget.animations) {
      a.removeStatusListener(_sync);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: _controller,
    // 子组件含有平台视图等无法截图的内容时直接实时绘制，不报错。
    mode: SnapshotMode.permissive,
    autoresize: true,
    child: widget.child,
  );
}
