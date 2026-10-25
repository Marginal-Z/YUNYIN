import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';

/// 滚动歌词。当前行逐字填色并放大，以弹簧曲线滚动到 [anchor] 位置；点击某行跳转。
/// 手动拖动歌词后暂停自动跟随几秒。
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.desktop, this.anchor = 0.3, this.padding = EdgeInsets.zero});

  final bool desktop;

  /// 当前行在可视区域中的位置（0 顶部，1 底部）。
  final double anchor;
  final EdgeInsets padding;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _scroll = ScrollController();
  late final PlayerController _player;
  List<GlobalKey> _keys = [];
  Lyrics _lyrics = Lyrics.empty;
  int _active = -1;

  /// 用户拖动歌词后暂停自动跟随，松手 2.5 秒后恢复。
  bool _manual = false;
  double? _height;
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
    _scroll.dispose();
    super.dispose();
  }

  void _onPosition() {
    final i = _lyrics.indexAt(_player.position.value);
    if (i == _active) return;
    setState(() => _active = i);
    _follow();
  }

  void _follow({bool jump = false}) {
    if (!_lyrics.synced || _manual) return;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final i = _active.clamp(0, _keys.length - 1);
        final box = _keys.isEmpty ? null : _keys[i].currentContext?.findRenderObject();
        if (box == null) return;
        final viewport = RenderAbstractViewport.of(box);
        final pos = _scroll.position;
        final target = viewport.getOffsetToReveal(box, widget.anchor).offset.clamp(pos.minScrollExtent, pos.maxScrollExtent);
        if ((target - pos.pixels).abs() < 1) return;
        if (jump) {
          _scroll.jumpTo(target);
        } else {
          _scroll.animateTo(target, duration: const Duration(milliseconds: 900), curve: const _SpringCurve());
        }
      })
      ..ensureVisualUpdate();
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _manual = true;
      _resume?.cancel();
    } else if (n is ScrollEndNotification && _manual) {
      _resume?.cancel();
      _resume = Timer(const Duration(milliseconds: 2500), () {
        _manual = false;
        _follow();
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lyrics = context.select<PlayerController, Lyrics>((c) => c.lyrics);
    final showTr = context.select<AppSettings, bool>((s) => s.showTranslation);
    final scale = context.select<AppSettings, double>((s) => s.lyricScale);
    if (!identical(lyrics, _lyrics)) {
      _lyrics = lyrics;
      _keys = List.generate(lyrics.lines.length, (_) => GlobalKey());
      _active = lyrics.indexAt(_player.position.value);
      _manual = false;
      _follow(jump: true);
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
    final dimScale = widget.desktop ? 0.76 : 0.84;
    return LayoutBuilder(
      builder: (context, c) {
        final synced = lyrics.synced;
        // 可视区域大小变化（例如歌词页控件显示 / 隐藏）时，让当前行保持在锚点位置。
        if (c.maxHeight != _height) {
          final first = _height == null;
          _height = c.maxHeight;
          if (!first) _follow(jump: true);
        }
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.1, 0.84, 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              // 歌词靠自动滚动与拖动浏览，不显示滚动条。
              child: SingleChildScrollView(
                controller: _scroll,
                padding: widget.padding.add(
                  synced ? EdgeInsets.only(top: c.maxHeight * widget.anchor, bottom: c.maxHeight * (1 - widget.anchor)) : EdgeInsets.zero,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < lyrics.lines.length; i++)
                      _LyricLineView(
                        key: _keys[i],
                        line: lyrics.lines[i],
                        end: i + 1 < lyrics.lines.length ? lyrics.lines[i + 1].time : lyrics.lines[i].time + const Duration(seconds: 6),
                        distance: synced ? i - _active : 3,
                        style: base,
                        dimScale: dimScale,
                        showTranslation: showTr,
                        translationSize: (widget.desktop ? 20.0 : 16.0) * scale,
                        gap: (widget.desktop ? 22.0 : 20.0) * scale,
                        onTap: synced ? () => _player.seek(lyrics.lines[i].time) : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 一行歌词。当前行放大并按播放进度逐字填色，其余行缩小、变淡。
/// 缩放只作用于绘制，不改变布局，滚动目标位置因此保持稳定。
class _LyricLineView extends StatelessWidget {
  const _LyricLineView({
    super.key,
    required this.line,
    required this.end,
    required this.distance,
    required this.style,
    required this.dimScale,
    required this.showTranslation,
    required this.translationSize,
    required this.gap,
    this.onTap,
  });

  final LyricLine line;
  final Duration end;
  final int distance;
  final TextStyle style;
  final double dimScale;
  final bool showTranslation;
  final double translationSize;
  final double gap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final active = distance == 0;
    final near = distance.abs() == 1;
    final dim = active ? p.playerText2 : (near ? Color.lerp(p.lyricDim, p.playerText2, 0.45)! : p.lyricDim);
    final opacity = active || near ? 1.0 : (distance.abs() == 2 ? 0.8 : 0.6);
    const dur = Duration(milliseconds: 520);
    const curve = Curves.easeOutCubic;
    final tr = line.translation ?? '';
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Pressable(
        onTap: onTap,
        scale: 1,
        child: AnimatedOpacity(
          opacity: opacity,
          duration: dur,
          curve: curve,
          child: AnimatedScale(
            scale: active ? 1 : dimScale,
            alignment: Alignment.centerLeft,
            duration: dur,
            curve: const _SpringCurve(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (active)
                  ValueListenableBuilder<Duration>(
                    valueListenable: context.read<PlayerController>().position,
                    builder: (context, pos, _) {
                      final span = (end - line.time).inMilliseconds;
                      final f = span <= 0 ? 1.0 : ((pos - line.time).inMilliseconds / span).clamp(0.0, 1.0);
                      return _KaraokeText(line.text, style: style, base: dim, fill: p.lyricActive, progress: f);
                    },
                  )
                else
                  TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: dim),
                    duration: dur,
                    builder: (context, c, _) => Text(line.text, style: style.copyWith(color: c)),
                  ),
                if (showTranslation && tr.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: AnimatedDefaultTextStyle(
                      duration: dur,
                      style: ts(translationSize, weight: w500, color: active ? p.playerText2 : p.lyricDim),
                      child: Text(tr),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 逐字填色：按阅读顺序跨多行填充，填充边缘柔和过渡。
class _KaraokeText extends LeafRenderObjectWidget {
  const _KaraokeText(this.text, {required this.style, required this.base, required this.fill, required this.progress});

  final String text;
  final TextStyle style;
  final Color base;
  final Color fill;
  final double progress;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderKaraoke(text, style, base, fill, progress, Directionality.of(context), MediaQuery.textScalerOf(context));

  @override
  void updateRenderObject(BuildContext context, _RenderKaraoke r) {
    r.update(text, style, base, fill, progress, MediaQuery.textScalerOf(context));
  }
}

class _RenderKaraoke extends RenderBox {
  _RenderKaraoke(this._text, this._style, this._base, this._fill, this._progress, TextDirection dir, TextScaler scaler)
    : _dim = TextPainter(textDirection: dir, textScaler: scaler),
      _lit = TextPainter(textDirection: dir, textScaler: scaler) {
    _setText();
  }

  String _text;
  TextStyle _style;
  Color _base, _fill;
  double _progress;
  final TextPainter _dim, _lit;
  List<ui.LineMetrics> _rows = const [];

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

  void update(String text, TextStyle style, Color base, Color fill, double progress, TextScaler scaler) {
    final relayout = text != _text || style != _style || scaler != _dim.textScaler;
    final repaint = base != _base || fill != _fill;
    _text = text;
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
    } else if (repaint || progress != _progress) {
      markNeedsPaint();
    }
    _progress = progress;
  }

  @override
  void performLayout() {
    _dim.layout(maxWidth: constraints.maxWidth);
    _lit.layout(maxWidth: constraints.maxWidth);
    _rows = _dim.computeLineMetrics();
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
    final canvas = context.canvas;
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

/// 轻微欠阻尼的弹簧曲线，用于歌词滚动与缩放。
class _SpringCurve extends Curve {
  const _SpringCurve();

  static final _sim = SpringSimulation(SpringDescription.withDampingRatio(mass: 1, stiffness: 120, ratio: 0.82), 0, 1, 0);

  @override
  double transformInternal(double t) => _sim.x(t * 0.9);
}
