import 'dart:math' as math;

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

/// 移动端玻璃标签栏：选中底色是一个可滑动的滑块。
///
/// 滑块的左右两条边各是一个弹簧：前进方向的边弹簧较硬、先到，后面的边较软、随后跟上，
/// 滑块因此先拉长再收拢，呈现非线性的“液滴”滑动（与酷安底部导航栏相似）。
/// - 点击：滑块滑到目标标签（再次点击当前标签交给 [onSelect] 处理，例如回到根页面）；
/// - 按住拖动：滑块跟随手指并略微放大；松手后按位置与速度停在最近的标签上，
///   经过每个标签时有轻微触感反馈。
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

  /// 拖动时的放大程度（0 ~ 1）。
  late final AnimationController _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));

  /// 前进方向的边（硬）与后面的边（软）。
  static final _lead = SpringDescription.withDampingRatio(mass: 1, stiffness: 700, ratio: 0.82);
  static final _trail = SpringDescription.withDampingRatio(mass: 1, stiffness: 210, ratio: 0.9);

  /// 滑块要去的位置（左边）。
  late double _target = widget.index.toDouble();
  bool _dragging = false;
  int _hovered = -1;

  @override
  void didUpdateWidget(SlidingTabBar old) {
    super.didUpdateWidget(old);
    if (!_dragging && widget.index != old.index) _moveTo(widget.index.toDouble());
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    _lift.dispose();
    super.dispose();
  }

  /// 两条边分别以各自的弹簧奔向目标；保留当前速度，连续拖动时不会顿挫。
  void _moveTo(double target) {
    final forward = target > _target || (target == _target && target > _left.value);
    _target = target;
    _left.animateWith(SpringSimulation(forward ? _trail : _lead, _left.value, target, _left.velocity));
    _right.animateWith(SpringSimulation(forward ? _lead : _trail, _right.value, target + 1, _right.velocity));
  }

  double _at(double dx, double itemWidth) => (dx / itemWidth - 0.5).clamp(0.0, widget.items.length - 1.0);

  void _start(Offset local, double w) {
    _dragging = true;
    _lift.forward();
    _hovered = _target.round();
    _move(local, w);
  }

  void _move(Offset local, double w) {
    final v = _at(local.dx, w);
    _moveTo(v);
    final i = v.round();
    if (i != _hovered) {
      _hovered = i;
      HapticFeedback.selectionClick();
    }
  }

  void _end(double velocity, double w) {
    _dragging = false;
    _lift.reverse();
    final v = velocity / w;
    // 按 0.12 秒后的位置取最近的标签：轻甩可以越过半格，但最多多走约半格，不会一下跳过一个标签。
    final target = (_target + (v * 0.12).clamp(-0.6, 0.6)).round().clamp(0, widget.items.length - 1);
    _moveTo(target.toDouble());
    if (target != widget.index) widget.onSelect(target);
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
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final i = (d.localPosition.dx / w).floor().clamp(0, n - 1);
              if (i != widget.index) _moveTo(i.toDouble());
              widget.onSelect(i);
            },
            onHorizontalDragStart: (d) => _start(d.localPosition, w),
            onHorizontalDragUpdate: (d) => _move(d.localPosition, w),
            onHorizontalDragEnd: (d) => _end(d.velocity.pixelsPerSecond.dx, w),
            onHorizontalDragCancel: () => _end(0, w),
            child: AnimatedBuilder(
              animation: Listenable.merge([_left, _right, _lift]),
              builder: (context, _) {
                final l = _left.value, r = math.max(_right.value, _left.value + 0.6);
                final center = (l + r) / 2 - 0.5;
                final lift = Curves.easeOut.transform(_lift.value);
                // 拖动时滑块整体略微放大。
                final grow = w * 0.04 * lift;
                final pillH = c.maxHeight * (1 + 0.1 * lift);
                final rr = BorderRadius.circular(pillH / 2);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: l * w - grow,
                      top: (c.maxHeight - pillH) / 2,
                      width: (r - l) * w + grow * 2,
                      height: pillH,
                      child: CustomPaint(
                        foregroundPainter: InsetShadowPainter(rr, [Shadow2(0, 0.5, 1, p.navActiveInset)]),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color.lerp(p.navActive, p.isDark ? const Color(0x33FFFFFF) : const Color(0xCCFFFFFF), lift * 0.6),
                            borderRadius: rr,
                            boxShadow: lift > 0 ? [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.12 * lift), blurRadius: 16, offset: const Offset(0, 4))] : null,
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
                              // 颜色随滑块中心的距离渐变；按住时滑块下的图标略微放大。
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
        scale: 1 + 0.12 * grow,
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
