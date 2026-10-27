import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'package:provider/provider.dart';

import '../settings.dart';
import '../theme/palette.dart';
import 'box.dart';
import 'icons.dart';
import 'text.dart';

/// 按压反馈：缩放 0.98（设计规范“按下”状态），桌面端显示手型光标与悬停底色。
///
/// 按下时快速收缩，松开时以轻微回弹的弹簧恢复。组件树结构固定：悬停底色只改变颜色，
/// 不插入新的父组件，子组件（例如封面图片）因此不会在鼠标移入移出时重建。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.scale = 0.98,
    this.pressedOpacity = 1,
    this.hoverColor,
    this.radius = BorderRadius.zero,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final double scale;
  final double pressedOpacity;
  final Color? hoverColor;
  final BorderRadius radius;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  /// 0 = 松开，1 = 按下。
  late final AnimationController _press = AnimationController(vsync: this, duration: const Duration(milliseconds: 90));
  bool _hover = false;
  bool _down = false;

  /// 松开的回弹：轻微欠阻尼。
  static final _release = SpringDescription.withDampingRatio(mass: 1, stiffness: 520, ratio: 0.62);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _set(bool down) {
    // 触屏没有悬停，按下时显示底色。
    if (widget.hoverColor != null && _down != down) setState(() => _down = down);
    _down = down;
    if (down) {
      _press.animateTo(1, curve: Curves.easeOut);
    } else if (_press.value > 0 || _press.isAnimating) {
      // 点得很快时先补完按下，让反馈可见。
      final from = math.max(_press.value, 0.6);
      _press.animateWith(SpringSimulation(_release, from, 0, 0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    Widget child = widget.child;
    if (widget.hoverColor != null) {
      child = AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(color: _hover || _down ? widget.hoverColor : widget.hoverColor!.withValues(alpha: 0), borderRadius: widget.radius),
        child: child,
      );
    }
    if (widget.scale != 1 || widget.pressedOpacity != 1) {
      child = AnimatedBuilder(
        animation: _press,
        builder: (context, child) {
          final t = _press.value;
          Widget c = Transform.scale(scale: 1 - (1 - widget.scale) * t, child: child);
          if (widget.pressedOpacity != 1) c = Opacity(opacity: (1 - (1 - widget.pressedOpacity) * t).clamp(0.0, 1.0), child: c);
          return c;
        },
        child: child,
      );
    }
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: widget.hoverColor == null ? null : (_) => setState(() => _hover = true),
        onExit: widget.hoverColor == null ? null : (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _set(true) : null,
          onTapUp: enabled ? (_) => _set(false) : null,
          onTapCancel: enabled ? () => _set(false) : null,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTap: widget.onSecondaryTap,
          child: child,
        ),
      ),
    );
  }
}

/// 透明背景的图标按钮（热区 ≥ 44）。
class YIconButton extends StatelessWidget {
  const YIconButton(this.icon, {super.key, this.onTap, this.size = 44, this.iconSize = 22, this.color, this.label, this.strokeWidth});

  final YIconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? color;
  final String? label;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.9,
      pressedOpacity: 0.6,
      semanticLabel: label,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: YIcon(icon, size: iconSize, color: color ?? Palette.of(context).text, strokeWidth: strokeWidth),
        ),
      ),
    );
  }
}

/// 白色圆形按钮（顶部头像、乐库设置/新建按钮）。
class CircleButton extends StatelessWidget {
  const CircleButton(this.icon, {super.key, this.onTap, this.size = 40, this.iconSize = 20, this.color, this.label, this.strokeWidth});

  final YIconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? color;
  final String? label;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      semanticLabel: label,
      child: YBox(
        width: size,
        height: size,
        radius: BorderRadius.circular(size / 2),
        color: p.chip,
        shadows: p.chipShadow,
        insets: p.chipInset,
        alignment: Alignment.center,
        child: YIcon(icon, size: iconSize, color: color ?? p.text, strokeWidth: strokeWidth),
      ),
    );
  }
}

/// 玻璃圆形按钮（页面左上角返回 / 右上角更多）。
class GlassButton extends StatelessWidget {
  const GlassButton(this.icon, {super.key, this.onTap, this.size = 44, this.iconSize = 22, this.label, this.color, this.strokeWidth, this.shadows});

  final YIconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final String? label;
  final Color? color;
  final double? strokeWidth;
  final List<Shadow2>? shadows;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      semanticLabel: label,
      child: Glass(
        radius: size / 2,
        width: size,
        height: size,
        shadows: shadows ?? p.glassButtonShadow,
        insets: p.glassButtonInset,
        alignment: Alignment.center,
        child: YIcon(icon, size: iconSize, color: color ?? p.text, strokeWidth: strokeWidth),
      ),
    );
  }
}

/// 胶囊筛选标签（选中：深色底白字）。
class YChip extends StatelessWidget {
  const YChip(this.label, {super.key, this.selected = false, this.onTap, this.height = 34});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      child: YBox(
        height: height,
        radius: BorderRadius.circular(17),
        color: selected ? p.chipSelected : p.chip,
        shadows: selected ? const [Shadow2(0, 8, 16, Color.fromRGBO(29, 29, 31, 0.22))] : p.chipShadow,
        insets: selected ? const [] : p.chipInset,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        child: Text(
          label,
          style: ts(14, weight: selected ? w600 : w500, color: selected ? p.chipSelectedText : p.text3),
        ),
      ),
    );
  }
}

class ChipBar extends StatelessWidget {
  const ChipBar({super.key, required this.labels, required this.index, required this.onChanged, this.scroll = false});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++) ...[if (i > 0) const SizedBox(width: 8), YChip(labels[i], selected: i == index, onTap: () => onChanged(i))],
      ],
    );
    if (!scroll) return Align(alignment: Alignment.centerLeft, child: row);
    return SingleChildScrollView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, child: row);
  }
}

/// 分区标题：22/700 + 右侧红色链接。
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.top = 28, this.bottom = 12});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: ts(22, weight: w700, em: -0.015, color: p.text),
            ),
          ),
          if (action != null)
            Pressable(
              onTap: onAction,
              pressedOpacity: 0.6,
              child: Text(action!, style: ts(15, color: p.accentText)),
            ),
        ],
      ),
    );
  }
}

/// 白色圆角卡片（圆角 26 · 弥散阴影）。
class YCard extends StatelessWidget {
  const YCard({super.key, required this.child, this.radius = 26, this.padding, this.color, this.gradient});

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return YBox(
      clip: true,
      radius: BorderRadius.circular(radius),
      color: gradient == null ? (color ?? p.card) : null,
      gradient: gradient,
      shadows: p.cardShadow,
      insets: p.cardInset,
      padding: padding,
      child: child,
    );
  }
}

/// 卡片内的行列表，在每行顶部绘制带缩进的分隔线。
class CardList extends StatelessWidget {
  const CardList({super.key, required this.children, required this.indent, this.radius = 26});

  final List<Widget> children;
  final double indent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return YCard(
      radius: radius,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++)
            Stack(
              children: [
                children[i],
                if (i > 0)
                  Positioned(
                    left: indent,
                    right: 0,
                    top: 0,
                    child: Container(height: 1, color: p.separator),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// iOS 风格开关（开关绿 #34C759）。
class YSwitch extends StatelessWidget {
  const YSwitch({super.key, required this.value, required this.onChanged, this.label});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      child: Pressable(
        onTap: () => onChanged(!value),
        scale: 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 51,
          height: 31,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: value ? const Color(0xFF34C759) : const Color.fromRGBO(120, 120, 128, 0.32),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.all(2),
              width: 27,
              height: 27,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.25), offset: Offset(0, 2), blurRadius: 3.5)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分段控件（浅色 / 深色 / 跟随系统、顺序 / 随机 / 单曲）。
class Segmented extends StatelessWidget {
  const Segmented({super.key, required this.labels, required this.index, required this.onChanged, this.height = 36});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: p.segmentTrack, borderRadius: BorderRadius.circular(10)),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: p.segmentSelected,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.15), offset: Offset(0, 1), blurRadius: 1.7),
                      BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.04), spreadRadius: 0.5),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: Pressable(
                        onTap: () => onChanged(i),
                        scale: 1,
                        child: Center(
                          child: Text(
                            labels[i],
                            style: ts(13, weight: i == index ? w600 : w500, color: p.text),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 扁平的彩色图标块：纯色底、白色图标，没有渐变、辉光与高光。
class IconTile extends StatelessWidget {
  const IconTile(this.icon, this.color, {super.key, this.size = 30, this.iconSize = 18, this.strokeWidth = 1.9});

  final YIconData icon;
  final TileColor color;
  final double size;
  final double iconSize;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final r = size >= 56 ? 18.0 : (size >= 44 ? 13.0 : 9.0);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.flat, borderRadius: BorderRadius.circular(r)),
      child: YIcon(icon, size: iconSize, color: Colors.white, strokeWidth: strokeWidth),
    );
  }
}

/// 主按钮（胶囊 · 红色辉光）。
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.height = 50,
    this.fontSize = 16,
    this.iconSize = 19,
    this.expand = false,
    this.padding,
    this.enabled = true,
  });

  final String label;
  final YIconData? icon;
  final VoidCallback? onTap;
  final double height;
  final double fontSize;
  final double iconSize;
  final bool expand;
  final EdgeInsetsGeometry? padding;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[YIcon(icon!, size: iconSize, color: enabled ? Colors.white : const Color.fromRGBO(60, 60, 67, 0.42)), const SizedBox(width: 8)],
        Text(
          label,
          style: ts(fontSize, weight: w600, color: enabled ? Colors.white : const Color.fromRGBO(60, 60, 67, 0.42)),
        ),
      ],
    );
    return Pressable(
      onTap: enabled ? onTap : null,
      child: YBox(
        height: height,
        radius: BorderRadius.circular(height / 2),
        gradient: enabled ? CssGradient.vertical(p.buttonGradient) : null,
        color: enabled ? null : const Color.fromRGBO(60, 60, 67, 0.12),
        shadows: enabled ? p.buttonShadow : const [],
        insets: enabled ? [Shadow2(0, 1, 0, p.buttonInsetHighlight)] : const [],
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 22),
        child: content,
      ),
    );
  }
}

/// 次要按钮（白底）。
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    this.label,
    this.icon,
    this.onTap,
    this.height = 50,
    this.fontSize = 16,
    this.iconSize = 20,
    this.padding,
    this.flat = false,
    this.semanticLabel,
  });

  final String? label;
  final YIconData? icon;
  final VoidCallback? onTap;
  final double height;
  final double fontSize;
  final double iconSize;
  final EdgeInsetsGeometry? padding;

  /// 状态页里的灰底扁平样式（#F1F2F7，无阴影）。
  final bool flat;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: YBox(
        height: height,
        width: label == null ? height : null,
        radius: BorderRadius.circular(height / 2),
        color: flat ? p.field : p.chip,
        shadows: flat ? const [] : p.cardShadow,
        insets: flat ? const [] : p.chipInset,
        padding: label == null ? null : (padding ?? const EdgeInsets.symmetric(horizontal: 22)),
        child: Row(
          mainAxisSize: label == null ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) YIcon(icon!, size: iconSize, color: p.text),
            if (icon != null && label != null) const SizedBox(width: 8),
            if (label != null)
              Text(
                label!,
                style: ts(fontSize, weight: w600, color: p.text),
              ),
          ],
        ),
      ),
    );
  }
}

enum TagKind { hot, fresh, up, plain }

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.kind = TagKind.hot});

  final String text;
  final TagKind kind;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (bg, fg) = switch (kind) {
      TagKind.hot => (p.tagHot, p.tagHotText),
      TagKind.fresh => (p.tagNew, p.tagNewText),
      TagKind.up => (p.tagUp, p.tagUpText),
      TagKind.plain => (p.tagPlain, p.tagPlainText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        text,
        style: ts(11, weight: w700, color: fg),
      ),
    );
  }
}

/// 正在播放的三根跳动竖条。像均衡器一样按帧跳动（约每秒 6 帧），不做补间：
/// 每次跳动只产生一帧，避免为了这个小动画持续以满帧率重绘整个画面（玻璃背景滤镜每帧都要重新计算）。
class NowPlayingBars extends StatefulWidget {
  const NowPlayingBars({super.key, required this.color, this.playing = true});

  final Color color;
  final bool playing;

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars> {
  static const _frames = [
    [9.0, 16.0, 12.0],
    [12.0, 13.0, 8.0],
    [14.0, 10.0, 6.0],
    [10.0, 7.0, 11.0],
    [6.0, 13.0, 16.0],
    [9.0, 15.0, 13.0],
    [12.0, 7.0, 10.0],
    [15.0, 9.0, 7.0],
  ];
  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(NowPlayingBars old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.playing && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 160), (_) => setState(() => _i = (_i + 1) % _frames.length));
    } else if (!widget.playing && _timer != null) {
      _timer!.cancel();
      _timer = null;
      _i = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(size: const Size(15, 16), painter: _BarsPainter(_frames[_i], widget.color)),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.heights, this.color);

  final List<double> heights;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var i = 0; i < 3; i++) {
      final h = heights[i];
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(i * 6.0, size.height - h, 3, h), const Radius.circular(1.5)), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => !identical(old.heights, heights) || old.color != color;
}

/// 进度条：4px 轨道 + 可选 12px 圆点，支持拖动。
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, required this.value, this.onSeek, this.thumb = true, this.track, this.fill, this.height = 12});

  final double value;
  final ValueChanged<double>? onSeek;
  final bool thumb;
  final Color? track;
  final Color? fill;
  final double height;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;

  void _update(Offset local, double width) {
    setState(() => _drag = (local.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final v = (_drag ?? widget.value).clamp(0.0, 1.0);
    final fill = widget.fill ?? p.trackFill;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return MouseRegion(
          cursor: widget.onSeek != null ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.onSeek == null ? null : (d) => _update(d.localPosition, w),
            onTapUp: widget.onSeek == null
                ? null
                : (_) {
                    widget.onSeek!(_drag ?? v);
                    setState(() => _drag = null);
                  },
            onHorizontalDragStart: widget.onSeek == null ? null : (d) => _update(d.localPosition, w),
            onHorizontalDragUpdate: widget.onSeek == null ? null : (d) => _update(d.localPosition, w),
            onHorizontalDragEnd: widget.onSeek == null
                ? null
                : (_) {
                    widget.onSeek!(_drag ?? v);
                    setState(() => _drag = null);
                  },
            child: SizedBox(
              height: widget.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: (widget.height - 4) / 2,
                    height: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: widget.track ?? p.track, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    width: w * v,
                    top: (widget.height - 4) / 2,
                    height: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  if (widget.thumb)
                    Positioned(
                      left: w * v - 6,
                      top: (widget.height - 12) / 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 设置页里的一行：图标块 + 标题 + 右侧值/开关 + 箭头。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    this.tile,
    required this.title,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron,
    this.titleColor,
    this.height = 52,
  });

  final YIconData? icon;
  final TileColor? tile;
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? chevron;
  final Color? titleColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final showChevron = chevron ?? (onTap != null && trailing == null);
    final row = SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (icon != null) ...[IconTile(icon!, tile ?? TileColor.blue), const SizedBox(width: 12)],
            Expanded(
              child: Text(
                title,
                style: ts(16, color: titleColor ?? p.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 12),
              Flexible(
                flex: 0,
                child: Text(
                  value!,
                  style: ts(15, color: p.text2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            if (showChevron) ...[const SizedBox(width: 12), const YIcon(YIcons.chevronRight, size: 16, color: Color(0xFF8E8E93))],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Pressable(onTap: onTap, scale: 1, hoverColor: p.separator.withValues(alpha: 0.05), child: row);
  }
}

/// 设置分组标题（13px 次文字，左缩进 14）。
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.top = 22});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, top, 0, 8),
      child: Text(text, style: ts(13, color: Palette.of(context).text2)),
    );
  }
}

/// 页面大标题（36/700/-0.02em）+ 小副标题。
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.subtitle, this.size = 36});

  final String title;
  final String? subtitle;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (subtitle != null)
          Text(
            subtitle!,
            style: ts(13, weight: w600, color: p.text2),
          ),
        if (subtitle != null) const SizedBox(height: 2),
        Text(
          title,
          style: ts(size, weight: w700, em: -0.02, height: 1.1, color: p.text),
        ),
      ],
    );
  }
}

/// 应用图标（云 + 声波）。
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 30, this.gradient = false});

  final double size;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final accent = context.select<AppSettings, AccentColor>((s) => s.iconAccent);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(gradient, accent)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.gradient, this.accent);

  final bool gradient;
  final AccentColor accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.scale(s);
    final red = accent.base;
    final bgPaint = Paint();
    if (gradient) {
      bgPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [accent.buttonTop, red],
      ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    } else {
      bgPaint.color = red;
    }
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(22.5)), bgPaint);
    canvas.translate(50, 50);
    canvas.scale(1.12);
    canvas.translate(-50, -49);
    final white = Paint()..color = Colors.white;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 50, 56, 22), const Radius.circular(11)), white);
    canvas.drawCircle(const Offset(42, 48), 13, white);
    canvas.drawCircle(const Offset(60, 42), 16, white);
    final r = Paint()..color = red;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(38, 49, 6, 14), const Radius.circular(3)), r);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(47, 44, 6, 24), const Radius.circular(3)), r);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(56, 47, 6, 18), const Radius.circular(3)), r);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.gradient != gradient || old.accent != accent;
}
