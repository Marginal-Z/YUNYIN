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
/// - 点击：滑块以弹簧动画滑到目标标签（再次点击当前标签交给 [onSelect] 处理，例如回到根页面）；
/// - 按住拖动：滑块跟随手指并略微放大，速度越快拉得越长；松手后按位置与速度停在最近的标签上，
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
  /// 滑块位置，以标签为单位（0 = 第一个）。
  late final AnimationController _pos = AnimationController.unbounded(vsync: this, value: widget.index.toDouble());

  /// 拖动时的放大程度（0 ~ 1）。
  late final AnimationController _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));

  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: 0.72);

  bool _dragging = false;
  double _velocity = 0;
  int _hovered = -1;

  @override
  void didUpdateWidget(SlidingTabBar old) {
    super.didUpdateWidget(old);
    if (!_dragging && widget.index != old.index) _settle(widget.index);
  }

  @override
  void dispose() {
    _pos.dispose();
    _lift.dispose();
    super.dispose();
  }

  void _settle(int i, [double velocity = 0]) {
    _pos.animateWith(SpringSimulation(_spring, _pos.value, i.toDouble(), velocity));
  }

  double _at(double dx, double itemWidth) => (dx / itemWidth - 0.5).clamp(0.0, widget.items.length - 1.0);

  void _start(Offset local, double w) {
    _dragging = true;
    _pos.stop();
    _lift.forward();
    _hovered = _pos.value.round();
    _move(local, w, 0);
  }

  void _move(Offset local, double w, double velocity) {
    final v = _at(local.dx, w);
    _velocity = velocity / w;
    _pos.value = v;
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
    final target = (_pos.value + (v * 0.12).clamp(-0.6, 0.6)).round().clamp(0, widget.items.length - 1);
    _settle(target, v);
    _velocity = 0;
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
              if (i != widget.index) _settle(i);
              widget.onSelect(i);
            },
            onHorizontalDragStart: (d) => _start(d.localPosition, w),
            onHorizontalDragUpdate: (d) => _move(d.localPosition, w, d.primaryDelta ?? 0),
            onHorizontalDragEnd: (d) => _end(d.velocity.pixelsPerSecond.dx, w),
            onHorizontalDragCancel: () => _end(0, w),
            child: AnimatedBuilder(
              animation: Listenable.merge([_pos, _lift]),
              builder: (context, _) {
                final pos = _pos.value;
                final lift = Curves.easeOut.transform(_lift.value);
                // 拖动时滑块放大，并随速度沿水平方向拉长（液体感）。
                final stretch = (_dragging ? (_velocity.abs() * 0.6).clamp(0.0, 0.25) : 0.0) + (_pos.velocity.abs() * 0.02).clamp(0.0, 0.18);
                final pillW = w * (1 + 0.08 * lift + stretch);
                final pillH = c.maxHeight * (1 + 0.1 * lift);
                final r = BorderRadius.circular(pillH / 2);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: pos * w + (w - pillW) / 2,
                      top: (c.maxHeight - pillH) / 2,
                      width: pillW,
                      height: pillH,
                      child: CustomPaint(
                        foregroundPainter: InsetShadowPainter(r, [Shadow2(0, 0.5, 1, p.navActiveInset)]),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color.lerp(p.navActive, p.isDark ? const Color(0x33FFFFFF) : const Color(0xCCFFFFFF), lift * 0.6),
                            borderRadius: r,
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
                              // 颜色随滑块距离渐变；按住时滑块下的图标略微放大。
                              active: (1 - (pos - i).abs()).clamp(0.0, 1.0),
                              grow: lift * (1 - (pos - i).abs()).clamp(0.0, 1.0),
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
