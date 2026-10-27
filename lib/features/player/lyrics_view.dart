import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';

/// 滚动歌词（Apple Music 风格）。
///
/// - 换行时每一行各自以弹簧曲线移动，越靠下的行起步越晚，形成波浪式的滚动；
/// - 当前行逐字填色（有逐字时间轴时按字，唱到的字轻微上浮），其余行按距离变淡、模糊；
/// - 长间奏（≥ 5 秒）显示三个呼吸圆点；
/// - 拖动或滚轮浏览时取消模糊、暂停跟随，停止操作 2.5 秒后回到当前行；点击某行跳转。
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.desktop, this.anchor = 0.3, this.padding = EdgeInsets.zero});

  final bool desktop;

  /// 当前行在可视区域中的位置（0 顶部，1 底部）。
  final double anchor;
  final EdgeInsets padding;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

/// 歌词条目：一行歌词，或长间奏处的圆点。
class _Item {
  const _Item.line(this.index, this.start, this.end) : dots = false;
  const _Item.dots(this.start, this.end) : index = -1, dots = true;

  /// 在 [Lyrics.lines] 中的下标；圆点为 -1。
  final int index;
  final Duration start;
  final Duration end;
  final bool dots;
}

const _interlude = Duration(seconds: 5);

List<_Item> _itemsOf(Lyrics l) {
  final lines = l.lines;
  if (!l.synced) return [for (var i = 0; i < lines.length; i++) _Item.line(i, Duration.zero, Duration.zero)];
  final out = <_Item>[];
  var prevEnd = Duration.zero;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.time - prevEnd >= _interlude) out.add(_Item.dots(prevEnd, line.time));
    final next = i + 1 < lines.length ? lines[i + 1].time : null;
    // 逐字歌词带行时长；普通 LRC 以下一行开始为结束。
    var end = line.duration != null ? line.time + line.duration! : (next ?? line.time + const Duration(seconds: 6));
    if (next != null && end > next) end = next;
    out.add(_Item.line(i, line.time, end));
    prevEnd = end;
  }
  return out;
}

int _activeAt(List<_Item> items, Duration pos) {
  var lo = 0, hi = items.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (items[mid].start <= pos) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

/// 用户浏览产生的整体偏移，由渲染对象据此移动各行。
class _LyricsScroll extends ChangeNotifier {
  double offset = 0;
  double min = 0;
  double max = 0;

  /// 正在拖动 / 惯性滑动：偏移立即生效；否则以弹簧动画过渡（例如回到当前行）。
  bool dragging = false;

  /// 浏览中：不跟随播放进度、取消模糊。
  bool manual = false;

  void set(double v, {required bool drag}) {
    offset = v.clamp(min, max);
    dragging = drag;
    notifyListeners();
  }
}

class _LyricsViewState extends State<LyricsView> with SingleTickerProviderStateMixin {
  late final PlayerController _player;
  final _scroll = _LyricsScroll();
  late final AnimationController _fling = AnimationController.unbounded(vsync: this)..addListener(_onFling);
  Lyrics _lyrics = Lyrics.empty;
  List<_Item> _items = const [];
  int _active = -1;
  int _jump = 0;
  Timer? _resume;

  @override
  void initState() {
    super.initState();
    _player = context.read<PlayerController>();
    _player.position.addListener(_onPosition);
  }

  @override
  void dispose() {
    _player.position.removeListener(_onPosition);
    _resume?.cancel();
    _fling.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onPosition() {
    final i = _activeAt(_items, _player.position.value);
    if (i != _active) setState(() => _active = i);
  }

  // ── 浏览 ──────────────────────────────────────────

  void _browse() {
    _resume?.cancel();
    if (!_scroll.manual) setState(() => _scroll.manual = true);
  }

  void _scheduleResume() {
    _resume?.cancel();
    if (!_lyrics.synced) return;
    _resume = Timer(const Duration(milliseconds: 2500), _follow);
  }

  void _follow() {
    _resume?.cancel();
    _fling.stop();
    if (!mounted) return;
    setState(() => _scroll.manual = false);
    _scroll.set(0, drag: false);
  }

  void _onDragStart(DragStartDetails _) {
    _fling.stop();
    _browse();
  }

  void _onDragUpdate(DragUpdateDetails d) => _scroll.set(_scroll.offset + d.delta.dy, drag: true);

  void _onDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    if (v.abs() > 50) {
      _fling.value = _scroll.offset;
      _fling.animateWith(FrictionSimulation(0.12, _scroll.offset, v));
    }
    _scheduleResume();
  }

  void _onFling() {
    _scroll.set(_fling.value, drag: true);
    if (_scroll.offset == _scroll.min || _scroll.offset == _scroll.max) _fling.stop();
  }

  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (e) {
      _fling.stop();
      _browse();
      _scroll.set(_scroll.offset - (e as PointerScrollEvent).scrollDelta.dy, drag: true);
      _scheduleResume();
    });
  }

  void _seek(_Item item) {
    _player.seek(item.start);
    if (_scroll.manual) _follow();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lyrics = context.select<PlayerController, Lyrics>((c) => c.lyrics);
    final showTr = context.select<AppSettings, bool>((s) => s.showTranslation);
    final scale = context.select<AppSettings, double>((s) => s.lyricScale);
    if (!identical(lyrics, _lyrics)) {
      _lyrics = lyrics;
      _items = _itemsOf(lyrics);
      _active = _activeAt(_items, _player.position.value);
      _resume?.cancel();
      _fling.stop();
      // 未同步的歌词只能手动浏览。
      _scroll
        ..manual = !lyrics.synced
        ..offset = 0
        ..dragging = false;
      _jump++;
    }
    final size = (widget.desktop ? 44.0 : 32.0) * scale;
    final base = ts(size, weight: w700, em: -0.015, height: 1.3);
    if (lyrics.lines.isEmpty) {
      return Align(
        alignment: widget.desktop ? Alignment.centerLeft : Alignment.topLeft,
        child: Padding(
          padding: widget.padding,
          child: Text(
            '暂无歌词，请欣赏',
            style: base.copyWith(fontSize: size * 0.8, color: p.playerText2),
          ),
        ),
      );
    }
    final synced = lyrics.synced;
    // 桌面端悬停时整行显示圆角底色，内边距 10；外侧相应收窄，文字位置不变。
    final inner = widget.desktop ? 10.0 : 0.0;
    final pad = widget.padding;
    return Listener(
      onPointerSignal: _onWheel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
            stops: [0, 0.1, 0.84, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: Padding(
            padding: EdgeInsets.fromLTRB(math.max(0, pad.left - inner), pad.top, math.max(0, pad.right - inner), pad.bottom),
            child: _LyricsLayout(
              active: synced ? _active : 0,
              anchor: synced ? widget.anchor : 0,
              scroll: _scroll,
              jump: _jump,
              stagger: synced,
              children: [
                for (var i = 0; i < _items.length; i++)
                  _LineView(
                    key: ValueKey(i),
                    item: _items[i],
                    line: _items[i].dots ? null : lyrics.lines[_items[i].index],
                    distance: synced ? i - _active : 3,
                    synced: synced,
                    browsing: _scroll.manual,
                    style: base,
                    inner: inner,
                    showTranslation: showTr,
                    translationSize: (widget.desktop ? 20.0 : 16.0) * scale,
                    gap: (widget.desktop ? 18.0 : 16.0) * scale,
                    onTap: synced && !_items[i].dots ? () => _seek(_items[i]) : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 布局与逐行弹簧 ──────────────────────────────────────────

class _LyricsLayout extends MultiChildRenderObjectWidget {
  const _LyricsLayout({required this.active, required this.anchor, required this.scroll, required this.jump, required this.stagger, required super.children});

  final int active;
  final double anchor;
  final _LyricsScroll scroll;

  /// 变化时直接放到目标位置（换歌）。
  final int jump;
  final bool stagger;

  @override
  _RenderLyrics createRenderObject(BuildContext context) => _RenderLyrics(active, anchor, scroll, jump, stagger);

  @override
  void updateRenderObject(BuildContext context, _RenderLyrics r) {
    r
      ..stagger = stagger
      ..jump = jump
      ..anchor = anchor
      ..scroll = scroll
      ..active = active;
  }
}

class _LineData extends ContainerBoxParentData<RenderBox> {
  /// 当前位置、速度与目标位置（顶部，相对视图）。
  double y = 0;
  double v = 0;
  double target = 0;

  /// 开始移动前剩余的等待时间（秒）。
  double wait = 0;
}

/// 竖直排列各行；每行的位置是独立的弹簧，换行时按与当前行的距离错开起步。
/// 只移动绘制位置，不重新布局；视图外的行不绘制。
class _RenderLyrics extends RenderBox with ContainerRenderObjectMixin<RenderBox, _LineData>, RenderBoxContainerDefaultsMixin<RenderBox, _LineData> {
  _RenderLyrics(this._active, this._anchor, this._scroll, this._jump, this._stagger);

  /// 弹簧：响应时间约 0.6 秒、轻微欠阻尼。
  static const _omega = 2 * math.pi / 0.62;
  static const _zeta = 0.86;

  /// 相邻两行起步间隔（秒）。
  static const _step = 0.045;

  int _active;
  double _anchor;
  _LyricsScroll _scroll;
  int _jump;
  bool _stagger;
  bool _needsJump = true;
  Size? _laidOut;
  List<double> _tops = const [];
  double _applied = 0;
  int? _frame;
  Duration? _last;

  set active(int v) {
    if (v == _active) return;
    // 浏览中换行：调整偏移让画面保持不动。
    if (_scroll.manual && _tops.isNotEmpty) {
      final shift = _topOf(v) - _topOf(_active);
      _scroll.offset += shift;
      _applied = _scroll.offset;
    }
    _active = v;
    _retarget(stagger: !_scroll.manual && _stagger);
    markNeedsLayout();
  }

  set anchor(double v) {
    if (v == _anchor) return;
    _anchor = v;
    _needsJump = true;
    markNeedsLayout();
  }

  set jump(int v) {
    if (v == _jump) return;
    _jump = v;
    _needsJump = true;
    markNeedsLayout();
  }

  set stagger(bool v) => _stagger = v;

  set scroll(_LyricsScroll v) {
    if (identical(v, _scroll)) return;
    if (attached) _scroll.removeListener(_onScroll);
    _scroll = v;
    if (attached) _scroll.addListener(_onScroll);
    markNeedsLayout();
  }

  double _topOf(int i) => _tops.isEmpty ? 0 : _tops[i.clamp(0, _tops.length - 1)];

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LineData) child.parentData = _LineData();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scroll.addListener(_onScroll);
  }

  @override
  void detach() {
    _scroll.removeListener(_onScroll);
    if (_frame != null) SchedulerBinding.instance.cancelFrameCallbackWithId(_frame!);
    _frame = null;
    _last = null;
    super.detach();
  }

  void _onScroll() {
    final delta = _scroll.offset - _applied;
    _applied = _scroll.offset;
    if (delta == 0) return;
    if (_scroll.dragging) {
      // 拖动：所有行同步移动，进行中的弹簧随之平移。
      var child = firstChild;
      while (child != null) {
        final d = child.parentData! as _LineData;
        d
          ..y += delta
          ..target += delta;
        child = d.nextSibling;
      }
      markNeedsPaint();
    } else {
      _retarget(stagger: false);
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final c = BoxConstraints.tightFor(width: size.width);
    final tops = <double>[];
    var y = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(c, parentUsesSize: true);
      tops.add(y);
      y += child.size.height;
      child = (child.parentData! as _LineData).nextSibling;
    }
    _tops = tops;
    // 可浏览范围：第一行不低于锚点，最后一行不高于锚点。
    final a = _topOf(_active);
    if (_anchor == 0) {
      _scroll
        ..min = math.min(0, size.height * 0.6 - (tops.isEmpty ? 0 : tops.last))
        ..max = 0;
    } else {
      _scroll
        ..min = a - (tops.isEmpty ? 0 : tops.last)
        ..max = a;
    }
    if (_scroll.offset < _scroll.min || _scroll.offset > _scroll.max) {
      _scroll.offset = _scroll.offset.clamp(_scroll.min, _scroll.max);
      _applied = _scroll.offset;
    }
    final resized = _laidOut != size;
    _laidOut = size;
    if (_needsJump || resized) {
      _needsJump = false;
      _applied = _scroll.offset;
      _place();
    } else {
      // 行高变化（例如间奏圆点展开）：只更新目标，不打断已安排的错开起步。
      _retarget(stagger: false, keepWait: true);
    }
  }

  double _targetOf(int i) => size.height * _anchor - _topOf(_active) + _tops[i] + _scroll.offset;

  /// 直接放到目标位置。
  void _place() {
    var i = 0;
    var child = firstChild;
    while (child != null) {
      final d = child.parentData! as _LineData;
      d
        ..target = _targetOf(i)
        ..y = d.target
        ..v = 0
        ..wait = 0
        ..offset = Offset(0, d.y);
      child = d.nextSibling;
      i++;
    }
  }

  void _retarget({required bool stagger, bool keepWait = false}) {
    if (!hasSize || _tops.length != childCount) {
      markNeedsLayout();
      return;
    }
    final a = _active.clamp(0, math.max(0, childCount - 1));
    var moving = false;
    var i = 0;
    var child = firstChild;
    while (child != null) {
      final d = child.parentData! as _LineData;
      final t = _targetOf(i);
      if ((t - d.target).abs() > 0.01 || (d.y - t).abs() > 0.01) {
        d.target = t;
        // 当前行的上一行最先起步，往下逐行推迟。
        if (stagger) {
          d.wait = (i - a + 1).clamp(0, 12) * _step;
        } else if (!keepWait) {
          d.wait = 0;
        }
        moving = true;
      }
      child = d.nextSibling;
      i++;
    }
    if (moving) _start();
  }

  void _start() {
    if (_frame != null || !attached) return;
    _frame = SchedulerBinding.instance.scheduleFrameCallback(_tick);
  }

  void _tick(Duration now) {
    _frame = null;
    if (!attached) return;
    final dt = _last == null ? 1 / 60 : ((now - _last!).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    var moving = false;
    var child = firstChild;
    while (child != null) {
      final d = child.parentData! as _LineData;
      var t = dt;
      if (d.wait > 0) {
        final w = math.min(d.wait, t);
        d.wait -= w;
        t -= w;
        moving = true;
      }
      // 半隐式欧拉，步长不超过 1/240 秒，保证不同帧率下轨迹一致。
      while (t > 0 && (d.y != d.target || d.v != 0)) {
        final h = math.min(t, 1 / 240);
        final acc = -_omega * _omega * (d.y - d.target) - 2 * _zeta * _omega * d.v;
        d.v += acc * h;
        d.y += d.v * h;
        t -= h;
        if ((d.y - d.target).abs() < 0.05 && d.v.abs() < 2) {
          d
            ..y = d.target
            ..v = 0;
        }
      }
      if (d.y != d.target || d.v != 0) moving = true;
      d.offset = Offset(0, d.y);
      child = d.nextSibling;
    }
    markNeedsPaint();
    if (moving) {
      _frame = SchedulerBinding.instance.scheduleFrameCallback(_tick);
    } else {
      _last = null;
    }
  }

  final _clip = LayerHandle<ClipRectLayer>();

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // 各行可能移出视图（弹簧过冲、浏览），裁到视图内，避免画到上下的卡片后面。
    _clip.layer = context.pushClipRect(needsCompositing, offset, Offset.zero & size, _paintLines, oldLayer: _clip.layer);
  }

  void _paintLines(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final d = child.parentData! as _LineData;
      // 只绘制可见的行（上下各留一屏余量给放大与模糊）。
      if (d.y + child.size.height > -size.height * 0.5 && d.y < size.height * 1.5) {
        context.paintChild(child, offset + d.offset);
      }
      child = d.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}

// ── 单行 ──────────────────────────────────────────

/// 一行歌词。当前行完整亮度并逐字填色；其余行缩小、变淡，并按距离模糊。
/// 缩放与模糊只作用于绘制，不改变布局。
class _LineView extends StatelessWidget {
  const _LineView({
    super.key,
    required this.item,
    required this.line,
    required this.distance,
    required this.synced,
    required this.browsing,
    required this.style,
    required this.inner,
    required this.showTranslation,
    required this.translationSize,
    required this.gap,
    this.onTap,
  });

  final _Item item;
  final LyricLine? line;
  final int distance;
  final bool synced;
  final bool browsing;
  final TextStyle style;
  final double inner;
  final bool showTranslation;
  final double translationSize;
  final double gap;
  final VoidCallback? onTap;

  static const _dur = Duration(milliseconds: 600);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final active = distance == 0;
    final far = distance.abs();
    if (item.dots) {
      return _Interlude(item: item, active: active, size: style.fontSize!, color: p.lyricActive, gap: gap, inner: inner);
    }
    final l = line!;
    // 浏览时所有行清晰可读；跟随时越远越淡、越模糊。4 行以外已经很淡且处在边缘渐隐区，不再模糊，节省绘制。
    final double alpha = !synced || active ? 1 : (browsing ? 0.8 : (far == 1 ? 0.7 : math.max(0.32, 0.62 - far * 0.07)));
    final double sigma = !synced || active || browsing || far > 4 ? 0 : math.min(0.3 + far * 0.7, 3.0);
    final dim = (synced ? p.lyricDim : p.playerText2).withValues(alpha: alpha);
    final tr = l.translation ?? '';
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (active)
          RepaintBoundary(
            child: _LiveKaraoke(line: l, item: item, style: style, base: p.lyricDim, fill: p.lyricActive),
          )
        else
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: dim),
            duration: _dur,
            curve: Curves.easeOutCubic,
            builder: (context, c, _) => Text(l.text, style: style.copyWith(color: c)),
          ),
        if (showTranslation && tr.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AnimatedDefaultTextStyle(
              duration: _dur,
              style: ts(translationSize, weight: w500, color: active ? p.playerText2 : dim),
              child: Text(tr),
            ),
          ),
      ],
    );
    content = AnimatedScale(scale: active || !synced ? 1 : 0.94, alignment: Alignment.centerLeft, duration: _dur, curve: const _SpringCurve(), child: content);
    content = TweenAnimationBuilder<double>(
      tween: Tween(end: sigma),
      duration: _dur,
      curve: Curves.easeOutCubic,
      builder: (context, s, child) => ImageFiltered(
        enabled: s > 0.2,
        imageFilter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s, tileMode: TileMode.decal),
        child: child,
      ),
      child: content,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Pressable(
        onTap: onTap,
        scale: 1,
        hoverColor: inner > 0 && onTap != null ? (p.isDark ? const Color(0x14FFFFFF) : const Color(0x0F000000)) : null,
        radius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: inner, vertical: inner * 0.6),
          child: content,
        ),
      ),
    );
  }
}

/// 长间奏的三个圆点：依次点亮、轻微呼吸，结束前收起。不在间奏中时高度收起为 0。
class _Interlude extends StatefulWidget {
  const _Interlude({required this.item, required this.active, required this.size, required this.color, required this.gap, required this.inner});

  final _Item item;
  final bool active;
  final double size;
  final Color color;
  final double gap;
  final double inner;

  @override
  State<_Interlude> createState() => _InterludeState();
}

class _InterludeState extends State<_Interlude> with SingleTickerProviderStateMixin {
  late final PlayerController _player = context.read<PlayerController>();
  late final _clock = _Clock(_player, this, () => setState(() {}));

  @override
  void initState() {
    super.initState();
    _clock.run(widget.active, widget.item.end);
  }

  @override
  void didUpdateWidget(_Interlude old) {
    super.didUpdateWidget(old);
    _clock.run(widget.active, widget.item.end);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = widget.size * 0.36;
    final pos = _clock.now;
    final start = widget.item.start, end = widget.item.end;
    final span = math.max(1, (end - start).inMilliseconds);
    final f = ((pos - start).inMilliseconds / span).clamp(0.0, 1.0);
    final left = (end - pos).inMilliseconds / 1000;
    // 呼吸：周期约 2.4 秒；最后 0.5 秒收起。
    final breathe = 1 + 0.08 * math.sin((pos.inMilliseconds / 1000) * 2 * math.pi / 2.4);
    final out = widget.active ? Curves.easeInCubic.transform((left / 0.5).clamp(0.0, 1.0)) : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.active ? 1 : 0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, open, child) => ClipRect(
        child: Align(alignment: Alignment.topLeft, heightFactor: open, child: child),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(widget.inner, widget.size * 0.3, widget.inner, widget.gap + widget.size * 0.3),
        child: Transform.scale(
          scale: breathe * (0.4 + 0.6 * out),
          alignment: Alignment.centerLeft,
          child: Opacity(
            opacity: out,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) SizedBox(width: dot * 0.7),
                  Container(
                    width: dot,
                    height: dot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(alpha: 0.25 + 0.75 * ((f * 3 - i).clamp(0.0, 1.0))),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 播放进度时钟：进度每 250 毫秒更新一次，这里在两次更新之间按经过的时间插值，
/// 只在 [run] 指定需要时每帧刷新。
class _Clock {
  _Clock(this._player, TickerProvider vsync, this._onTick) {
    _ticker = vsync.createTicker((_) => _onTick());
    _player.position.addListener(_sync);
    _player.addListener(_sync);
    _base = _player.position.value;
    _since.start();
  }

  final PlayerController _player;
  final VoidCallback _onTick;
  late final Ticker _ticker;
  final Stopwatch _since = Stopwatch();
  Duration _base = Duration.zero;
  bool _want = false;
  Duration _until = Duration.zero;

  /// 插值最多向前推 400 毫秒，避免卡顿或缓冲时跑到下一次更新之前太远。
  Duration get now => _base + (_player.playing ? Duration(milliseconds: _since.elapsedMilliseconds.clamp(0, 400)) : Duration.zero);

  void run(bool want, Duration until) {
    _want = want;
    _until = until;
    _update();
  }

  void _sync() {
    _base = _player.position.value;
    _since
      ..reset()
      ..start();
    // 不逐帧刷新时，每次进度更新重绘一次。
    if (!_update() && _want) _onTick();
  }

  /// 返回是否正在每帧刷新。
  bool _update() {
    final go = _want && _player.playing && _base < _until;
    if (go && !_ticker.isActive) _ticker.start();
    if (!go && _ticker.isActive) _ticker.stop();
    return go;
  }

  void dispose() {
    _player.position.removeListener(_sync);
    _player.removeListener(_sync);
    _ticker.dispose();
  }
}

// ── 逐字填色 ──────────────────────────────────────────

class _LiveKaraoke extends StatefulWidget {
  const _LiveKaraoke({required this.line, required this.item, required this.style, required this.base, required this.fill});

  final LyricLine line;
  final _Item item;
  final TextStyle style;
  final Color base;
  final Color fill;

  @override
  State<_LiveKaraoke> createState() => _LiveKaraokeState();
}

class _LiveKaraokeState extends State<_LiveKaraoke> with SingleTickerProviderStateMixin {
  late final PlayerController _player = context.read<PlayerController>();
  late final _clock = _Clock(_player, this, () => setState(() {}));

  /// 唱完最后一个字后再刷新一会儿，让上浮动画走完。
  Duration get _until => widget.item.end + const Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _clock.run(true, _until);
  }

  @override
  void didUpdateWidget(_LiveKaraoke old) {
    super.didUpdateWidget(old);
    _clock.run(true, _until);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = _clock.now;
    final span = (widget.item.end - widget.item.start).inMilliseconds;
    final f = span <= 0 ? 1.0 : ((pos - widget.item.start).inMilliseconds / span).clamp(0.0, 1.0);
    return _KaraokeText(widget.line, style: widget.style, base: widget.base, fill: widget.fill, progress: f, position: pos);
  }
}

class _KaraokeText extends LeafRenderObjectWidget {
  const _KaraokeText(this.line, {required this.style, required this.base, required this.fill, required this.progress, required this.position});

  final LyricLine line;
  final TextStyle style;
  final Color base;
  final Color fill;

  /// 整行进度（无逐字时间轴时使用）。
  final double progress;

  /// 当前播放位置（逐字时间轴使用）。
  final Duration position;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderKaraoke(line, style, base, fill, progress, position, Directionality.of(context), MediaQuery.textScalerOf(context));

  @override
  void updateRenderObject(BuildContext context, _RenderKaraoke r) {
    r.update(line, style, base, fill, progress, position, MediaQuery.textScalerOf(context));
  }
}

/// 逐字填色。有逐字时间轴时每个字按自己的时间填色并上浮；否则按整行进度、按阅读顺序跨多行填充。
/// 填充边缘柔和过渡。
class _RenderKaraoke extends RenderBox {
  _RenderKaraoke(this._line, this._style, this._base, this._fill, this._progress, this._position, TextDirection dir, TextScaler scaler)
    : _dim = TextPainter(textDirection: dir, textScaler: scaler),
      _lit = TextPainter(textDirection: dir, textScaler: scaler) {
    _setText();
  }

  LyricLine _line;
  TextStyle _style;
  Color _base, _fill;
  double _progress;
  Duration _position;
  final TextPainter _dim, _lit;
  List<ui.LineMetrics> _rows = const [];

  /// 每个字在文本中的矩形（逐字歌词）。
  List<List<Rect>> _wordBoxes = const [];

  String get _text => _line.words == null ? _line.text : _line.words!.map((w) => w.text).join();

  void _setText() {
    _dim.text = TextSpan(
      text: _text,
      style: _style.copyWith(color: _base),
    );
    _lit.text = TextSpan(
      text: _text,
      style: _style.copyWith(color: _fill),
    );
  }

  void update(LyricLine line, TextStyle style, Color base, Color fill, double progress, Duration position, TextScaler scaler) {
    final relayout = !identical(line, _line) || style != _style || scaler != _dim.textScaler;
    final repaint = base != _base || fill != _fill;
    _line = line;
    _style = style;
    _base = base;
    _fill = fill;
    if (relayout || repaint) {
      _dim.textScaler = scaler;
      _lit.textScaler = scaler;
      _setText();
    }
    if (relayout) {
      markNeedsLayout();
    } else if (repaint || progress != _progress || position != _position) {
      markNeedsPaint();
    }
    _progress = progress;
    _position = position;
  }

  @override
  void performLayout() {
    _dim.layout(maxWidth: constraints.maxWidth);
    _lit.layout(maxWidth: constraints.maxWidth);
    _rows = _dim.computeLineMetrics();
    final words = _line.words;
    if (words != null) {
      var at = 0;
      _wordBoxes = [
        for (final w in words) [for (final b in _dim.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at += w.text.length))) b.toRect()],
      ];
    } else {
      _wordBoxes = const [];
    }
    size = constraints.constrain(_dim.size);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    _dim.layout(maxWidth: width);
    return _dim.height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_line.words != null) {
      _paintWords(context.canvas, offset);
    } else {
      _paintLine(context.canvas, offset);
    }
  }

  void _paintWords(Canvas canvas, Offset offset) {
    final words = _line.words!;
    final fontSize = _style.fontSize!;
    final lift = fontSize * 0.06;
    final bounds = (offset & size).inflate(fontSize);
    final fills = <double>[];
    final lifts = <double>[];
    for (final w in words) {
      final ms = (_position - w.start).inMilliseconds;
      final dur = w.duration.inMilliseconds;
      fills.add(dur <= 0 ? (ms >= 0 ? 1.0 : 0.0) : (ms / dur).clamp(0.0, 1.0));
      // 上浮比填色稍慢，长音持续上浮。
      lifts.add(Curves.easeOutCubic.transform((ms / math.max(dur, 500)).clamp(0.0, 1.0)) * lift);
    }
    Rect clipOf(Rect r) => Rect.fromLTRB(r.left - 1, r.top - fontSize * 0.3, r.right + 1, r.bottom + fontSize * 0.3).shift(offset);

    // 未唱部分：每个字按各自的上浮位置绘制。
    for (var i = 0; i < words.length; i++) {
      for (final r in _wordBoxes[i]) {
        canvas
          ..save()
          ..clipRect(clipOf(r))
          ..translate(0, -lifts[i]);
        _dim.paint(canvas, offset);
        canvas.restore();
      }
    }
    if (!fills.any((f) => f > 0)) return;
    // 已唱部分：亮色文字叠一层逐字渐变遮罩。
    canvas.saveLayer(bounds, Paint());
    for (var i = 0; i < words.length; i++) {
      if (fills[i] <= 0) continue;
      for (final r in _wordBoxes[i]) {
        canvas
          ..save()
          ..clipRect(clipOf(r))
          ..translate(0, -lifts[i]);
        _lit.paint(canvas, offset);
        canvas.restore();
      }
    }
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    final white = Paint()..color = const Color(0xFFFFFFFF);
    for (var i = 0; i < words.length; i++) {
      final f = fills[i];
      if (f <= 0) continue;
      for (final r in _wordBoxes[i]) {
        final rect = clipOf(r).shift(Offset(0, -lifts[i]));
        if (f >= 1) {
          canvas.drawRect(rect, white);
          continue;
        }
        final feather = math.min(fontSize * 0.5, r.width);
        final edge = rect.left + (r.width + feather) * f;
        canvas.drawRect(rect, Paint()..shader = ui.Gradient.linear(Offset(edge - feather, 0), Offset(edge, 0), const [Color(0xFFFFFFFF), Color(0x00FFFFFF)]));
      }
    }
    canvas.restore();
    canvas.restore();
  }

  void _paintLine(Canvas canvas, Offset offset) {
    _dim.paint(canvas, offset);
    if (_progress <= 0 || _rows.isEmpty) return;
    final total = _rows.fold<double>(0, (s, r) => s + r.width);
    // 填充边缘的柔和宽度。
    final feather = _style.fontSize! * 0.9;
    var remain = _progress * (total + feather);
    final bounds = offset & size;
    canvas.saveLayer(bounds, Paint());
    _lit.paint(canvas, offset);
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    final white = Paint()..color = const Color(0xFFFFFFFF);
    for (final r in _rows) {
      if (remain <= 0) break;
      final top = offset.dy + r.baseline - r.ascent;
      final rect = Rect.fromLTWH(offset.dx + r.left, top, r.width, r.ascent + r.descent);
      if (remain >= r.width + feather) {
        canvas.drawRect(rect.inflate(2), white);
        remain -= r.width;
        continue;
      }
      final edge = rect.left + remain;
      canvas.drawRect(
        Rect.fromLTRB(rect.left - 2, rect.top - 2, rect.right + 2, rect.bottom + 2),
        Paint()..shader = ui.Gradient.linear(Offset(edge - feather, 0), Offset(edge, 0), const [Color(0xFFFFFFFF), Color(0x00FFFFFF)]),
      );
      remain = 0;
    }
    canvas.restore();
    canvas.restore();
  }
}

/// 轻微欠阻尼的弹簧曲线，用于歌词缩放。
class _SpringCurve extends Curve {
  const _SpringCurve();

  static final _sim = SpringSimulation(SpringDescription.withDampingRatio(mass: 1, stiffness: 120, ratio: 0.82), 0, 1, 0);

  @override
  double transformInternal(double t) => _sim.x(t * 0.9);
}
