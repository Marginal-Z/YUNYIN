import 'package:flutter/scheduler.dart';
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

/// 推迟页面转场的起点：新页面推入的那一帧先停在动画起点，完成首帧的构建、布局与截图，下一帧再开始播放。
///
/// 页面较重时首帧可能要几十毫秒；如果动画从首帧就开始计时，下一帧会直接跳过一大截，看起来就是“卡一下”。
/// 推迟起点后动画从 0 平滑播放到 1（总时长不变），代价只是起步晚一两帧。
abstract final class TransitionStart {
  static bool _holding = false;

  /// 在路由的 didPush 中调用：这一帧之内的转场动画都停在起点。
  static void hold() {
    _holding = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _holding = false);
  }

  static final Expando<_DeferredStart> _cache = Expando();

  /// 包装转场动画：推入时延后起步（见 [hold]），手势与返回动画照常跟随原动画。
  static Animation<double> of(Animation<double> parent) => _cache[parent] ??= _DeferredStart(parent);
}

class _DeferredStart extends Animation<double> with AnimationWithParentMixin<double> {
  _DeferredStart(this.parent) {
    parent.addStatusListener((s) {
      if (s != AnimationStatus.forward) {
        _fromZero = false;
        _start = null;
      }
    });
  }

  @override
  final Animation<double> parent;

  /// 这次前进是在推入时从 0 开始的（只有这种情况延后起步）。
  bool _fromZero = false;

  /// 首帧完成后原动画已经走到的位置：之后把 [_start]..1 映射为 0..1。
  double? _start;

  @override
  double get value {
    final v = parent.value;
    if (parent.status != AnimationStatus.forward) return v;
    if (TransitionStart._holding) {
      if (_start == null && v == 0) _fromZero = true;
      return _fromZero ? 0 : v;
    }
    if (!_fromZero) return v;
    final s = _start ??= v;
    return s >= 1 ? 1 : ((v - s) / (1 - s)).clamp(0.0, 1.0);
  }
}
