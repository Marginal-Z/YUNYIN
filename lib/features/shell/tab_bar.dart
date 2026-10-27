import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';

/// 标签栏中的一项。
class TabBarItem {
  const TabBarItem(this.icon, this.label);

  final YIconData icon;
  final String label;
}

/// 移动端玻璃标签栏：选中底色是一个可滑动的滑块（与酷安底部导航栏的交互相同）。
///
/// - 按下：滑块立即放大浮起；
/// - 按住拖动：滑块中心紧跟手指，越快拉得越长；经过每个标签时有轻微触感反馈；
/// - 松手：滑块缩回，并以两条边各自的弹簧滑到最近的标签——前进方向的边先到、后面的边随后跟上，
///   滑块先拉长再收拢（非线性）。轻甩可以越过半格；
/// - 轻点：切到该标签（再次点击当前标签交给 [onSelect] 处理，例如回到根页面）。
///
/// 直接处理原始指针事件，不经过手势竞争，按下的瞬间就有反馈，拖动也不会被其他手势抢走。
class SlidingTabBar extends StatefulWidget {
  const SlidingTabBar({super.key, required this.items, required this.index, required this.onSelect, this.height = 64});

  final List<TabBarItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final double height;

  @override
  State<SlidingTabBar> createState() => _SlidingTabBarState();
}

class _SlidingTabBarState extends State<SlidingTabBar> with TickerProviderStateMixin {
  /// 滑块左边与右边的位置，以标签为单位（第 i 个标签占 [i, i + 1]）。
  late final AnimationController _left = AnimationController.unbounded(vsync: this, value: widget.index.toDouble());
  late final AnimationController _right = AnimationController.unbounded(vsync: this, value: widget.index + 1.0);

  /// 按下时的放大程度（0 ~ 1，松开时带轻微回弹）。
  late final AnimationController _lift = AnimationController.unbounded(vsync: this);

  /// 前进方向的边（硬）与后面的边（软）。
  static final _lead = SpringDescription.withDampingRatio(mass: 1, stiffness: 620, ratio: 0.8);
  static final _trail = SpringDescription.withDampingRatio(mass: 1, stiffness: 190, ratio: 0.86);
  static final _pop = SpringDescription.withDampingRatio(mass: 1, stiffness: 520, ratio: 0.62);

  /// 滑块要去的位置（左边）。
  late double _target = widget.index.toDouble();

  // 当前这次按压的状态。
  int? _pointer;
  double _downX = 0;
  bool _dragging = false;
  int _hovered = -1;
  double _velocity = 0;
  VelocityTracker? _tracker;

  @override
  void didUpdateWidget(SlidingTabBar old) {
    super.didUpdateWidget(old);
    if (_pointer == null && widget.index != old.index) _moveTo(widget.index.toDouble());
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    _lift.dispose();
    super.dispose();
  }

  /// 两条边分别以各自的弹簧奔向目标；保留当前速度，不会顿挫。
  void _moveTo(double target) {
    final forward = target > _left.value;
    _target = target;
    _left.animateWith(SpringSimulation(forward ? _trail : _lead, _left.value, target, _left.velocity));
    _right.animateWith(SpringSimulation(forward ? _lead : _trail, _right.value, target + 1, _right.velocity));
  }

  void _setLift(double v) => _lift.animateWith(SpringSimulation(_pop, _lift.value, v, _lift.velocity));

  double _at(double dx, double w) => (dx / w - 0.5).clamp(0.0, widget.items.length - 1.0);

  void _down(PointerDownEvent e, double w) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _downX = e.localPosition.dx;
    _dragging = false;
    _hovered = _target.round();
    _tracker = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.localPosition);
    _setLift(1);
  }

  void _move(PointerMoveEvent e, double w) {
    if (e.pointer != _pointer) return;
    _tracker?.addPosition(e.timeStamp, e.localPosition);
    if (!_dragging && (e.localPosition.dx - _downX).abs() < kTouchSlop / 2) return;
    _dragging = true;
    // 滑块中心紧跟手指，速度带来的拉伸在绘制时计算。
    final v = _at(e.localPosition.dx, w);
    _left.stop();
    _right.stop();
    _target = v;
    _left.value = v;
    _right.value = v + 1;
    setState(() => _velocity = (_tracker?.getVelocity().pixelsPerSecond.dx ?? 0) / w);
    final i = v.round();
    if (i != _hovered) {
      _hovered = i;
      HapticFeedback.selectionClick();
    }
  }

  void _up(PointerUpEvent e, double w) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _setLift(0);
    final n = widget.items.length;
    if (_dragging) {
      final v = (_tracker?.getVelocity().pixelsPerSecond.dx ?? 0) / w;
      // 按 0.12 秒后的位置取最近的标签：轻甩可以越过半格，但最多多走约半格，不会一下跳过一个标签。
      final target = (_target + (v * 0.12).clamp(-0.6, 0.6)).round().clamp(0, n - 1);
      _velocity = 0;
      _moveTo(target.toDouble());
      if (target != widget.index) widget.onSelect(target);
    } else {
      final i = (e.localPosition.dx / w).floor().clamp(0, n - 1);
      if (i != widget.index) _moveTo(i.toDouble());
      widget.onSelect(i);
    }
    _dragging = false;
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _dragging = false;
    _velocity = 0;
    _setLift(0);
    _moveTo(widget.index.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final n = widget.items.length;
    return Glass(
      radius: widget.height / 2,
      height: widget.height,
      padding: const EdgeInsets.all(5),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / n;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _down(e, w),
            onPointerMove: (e) => _move(e, w),
            onPointerUp: (e) => _up(e, w),
            onPointerCancel: _cancel,
            child: AnimatedBuilder(
              animation: Listenable.merge([_left, _right, _lift]),
              builder: (context, _) {
                final lift = _lift.value;
                var l = _left.value, r = math.max(_right.value, _left.value + 0.6);
                // 拖动时按速度向后拉伸（最多 0.45 格），像被拖着走的液滴。
                if (_dragging) {
                  final stretch = (_velocity.abs() * 0.08).clamp(0.0, 0.45);
                  if (_velocity > 0) {
                    l -= stretch;
                  } else {
                    r += stretch;
                  }
                }
                final center = (l + r) / 2 - 0.5;
                // 按下时滑块放大浮起：宽高各放大约 14%。
                final grow = 0.14 * lift;
                final pillW = (r - l) * w * (1 + grow);
                final pillH = c.maxHeight * (1 + grow);
                final rr = BorderRadius.circular(pillH / 2);
                final up = lift.clamp(0.0, 1.0);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: (l + r) / 2 * w - pillW / 2,
                      top: (c.maxHeight - pillH) / 2,
                      width: pillW,
                      height: pillH,
                      child: CustomPaint(
                        foregroundPainter: InsetShadowPainter(rr, [Shadow2(0, 0.5, 1, p.navActiveInset)]),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color.lerp(p.navActive, p.isDark ? const Color(0x40FFFFFF) : const Color(0xF2FFFFFF), up * 0.75),
                            borderRadius: rr,
                            boxShadow: up > 0.01
                                ? [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.16 * up), blurRadius: 18 * up, offset: Offset(0, 5 * up))]
                                : null,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          Expanded(
                            child: _Item(
                              item: widget.items[i],
                              // 颜色随滑块中心的距离渐变；按住时滑块下的图标放大。
                              active: (1 - (center - i).abs()).clamp(0.0, 1.0),
                              grow: lift * (1 - (center - i).abs()).clamp(0.0, 1.0),
                              selected: i == widget.index,
                              onTap: () => widget.onSelect(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.item, required this.active, required this.grow, required this.selected, required this.onTap});

  final TabBarItem item;
  final double active;
  final double grow;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = Color.lerp(p.text3, p.accentText, active)!;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      onTap: onTap,
      excludeSemantics: true,
      child: Transform.scale(
        scale: 1 + 0.18 * grow,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            YIcon(item.icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: ts(11, weight: active > 0.5 ? w600 : w500, color: color, height: 1.2),
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ],
        ),
      ),
    );
  }
}
