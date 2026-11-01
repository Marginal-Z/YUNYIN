import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/cover_colors.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';

/// 卡片流与 3D 封面流：播放队列的封面横向排开，当前歌曲居中。
///
/// 一个透明的 [PageView] 负责拖动手势与吸附；封面按与中心的距离计算缩放、旋转与位移，
/// 并按距离从远到近绘制（中心的卡片在最上层）。停在某一张时切换到这首歌，切歌时自动滚动到当前歌曲。
class QueueFlow extends StatefulWidget {
  const QueueFlow({super.key, required this.style, required this.height, this.cardSize});

  final PlayerStyle style;
  final double height;

  /// 中心卡片的边长；默认按高度计算。
  final double? cardSize;

  @override
  State<QueueFlow> createState() => _QueueFlowState();
}

class _QueueFlowState extends State<QueueFlow> {
  PageController? _pc;
  double _fraction = 0;
  int _index = 0;
  bool _userScroll = false;

  bool get _cover => widget.style == PlayerStyle.coverFlow;

  /// 中心卡片最多占宽度的比例：手机竖屏留出更多空间给两侧的卡片。
  double _maxRatio(double width) => _cover ? (width < 520 ? 0.5 : 0.56) : (width < 520 ? 0.58 : 0.66);

  double get _card => widget.cardSize ?? (_cover ? widget.height * 0.62 : widget.height * 0.86);

  @override
  void dispose() {
    _pc?.dispose();
    super.dispose();
  }

  PageController _controller(double width) {
    // 拖动一页的距离等于相邻两张卡片的间距，卡片跟手移动。
    final card = math.min(_card, width * _maxRatio(width));
    // 与 [flowPlacement] 中相邻卡片的距离一致。
    final near = card * (_cover ? 0.7 : 0.5);
    final f = (near / width).clamp(0.12, 0.9);
    if (_pc == null || (f - _fraction).abs() > 0.001) {
      final page = _pc?.hasClients == true ? _pc!.page?.round() ?? _index : _index;
      _pc?.dispose();
      _fraction = f;
      _pc = PageController(viewportFraction: f, initialPage: page);
    }
    return _pc!;
  }

  void _follow(int index) {
    if (index == _index) return;
    _index = index;
    final pc = _pc;
    if (pc == null || !pc.hasClients || _userScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pc.hasClients && (pc.page ?? 0).round() != index) {
        pc.animateToPage(index, duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final queue = player.queue;
    if (queue.isEmpty) return SizedBox(height: widget.height);
    _follow(player.index);
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, c) {
          final pc = _controller(c.maxWidth);
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) _userScroll = true;
              if (n is ScrollEndNotification && _userScroll) {
                _userScroll = false;
                final p = (pc.page ?? 0).round().clamp(0, queue.length - 1);
                if (p != player.index) {
                  _index = p;
                  player.jumpTo(queue[p]);
                }
              }
              return false;
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: pc,
                    builder: (context, _) {
                      final page = pc.hasClients && pc.position.haveDimensions ? pc.page ?? _index.toDouble() : _index.toDouble();
                      return _cards(context, c.biggest, queue, page, player);
                    },
                  ),
                ),
                // 手势层：透明的页面，点按中心封面打开歌词，点按两侧封面切到那一首。
                Positioned.fill(
                  child: PageView.builder(
                    controller: pc,
                    itemCount: queue.length,
                    itemBuilder: (context, i) => GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        if (i == player.index) {
                          openLyrics(context);
                        } else {
                          pc.animateToPage(i, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
                          _index = i;
                          player.jumpTo(queue[i]);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cards(BuildContext context, Size box, List<Song> queue, double page, PlayerController player) {
    final card = math.min(_card, box.width * _maxRatio(box.width));
    // 两侧可用的空间：宽屏（横屏、桌面）上卡片间距更大，不再挤在中心卡片周围。
    final room = math.max(0.0, (box.width - card) / 2);
    final first = math.max(0, (page - 5).floor());
    final last = math.min(queue.length - 1, (page + 5).ceil());
    final items = <(double, Widget)>[];
    for (var i = first; i <= last; i++) {
      final place = flowPlacement(cover: _cover, d: i - page, card: card, room: room);
      if (place == null) continue;
      final a = (i - page).abs();
      items.add((
        a,
        Positioned(
          key: ValueKey(i),
          left: box.width / 2 - card / 2,
          top: _cover ? (box.height - card * 1.32) / 2 : (box.height - card) / 2,
          width: card,
          child: IgnorePointer(
            child: Transform(
              // 绕封面本身的中心旋转（3D 封面流的卡片下方还有倒影）。
              alignment: _cover ? const Alignment(0, -0.25) : Alignment.center,
              transform: place.transform,
              child: Opacity(
                opacity: place.opacity,
                child: _cover
                    ? _Reflected(song: queue[i], size: card, dim: place.dim)
                    : _FlowCard(song: queue[i], size: card, current: i == player.index, dim: place.dim),
              ),
            ),
          ),
        ),
      ));
    }
    items.sort((p, q) => q.$1.compareTo(p.$1));
    return Stack(clipBehavior: Clip.none, children: [for (final it in items) it.$2]);
  }
}

/// 卡片流与 3D 封面流中与中心距离为 [d]（可为小数，切换时连续变化）的卡片的摆放。
///
/// 两种样式的两侧卡片都向内转、朝向观察者（外侧边缘更近更高），沿一道弧面排开：
/// 卡片流的卡片紧密叠放、越往外越小；3D 封面流的卡片之间留出小间隔，转角更小，下方带倒影。
/// [card] 为中心卡片边长，[room] 为中心卡片一侧到边缘的宽度；超出范围、完全透明时返回 null。
({Matrix4 transform, double opacity, double dim})? flowPlacement({required bool cover, required double d, required double card, required double room}) {
  final a = d.abs();
  final t = d.clamp(-1.0, 1.0);
  final far = math.max(0.0, a - 1);
  // 竖屏手机两侧空间小，相邻卡片再缩小一些，不会比中心卡片显得更大。
  final tight = room < card * 0.6 ? 0.08 : 0.0;
  final double x, angle, sc, z;
  if (cover) {
    angle = 0.86;
    sc = 1 - math.min(a, 1) * (0.16 + tight) - far * 0.05;
    final step = ((room - card * 0.3) / 3.4).clamp(card * 0.3, card * 0.42);
    x = t * card * 0.7 + d.sign * far * step;
    z = 0;
  } else {
    angle = 0.86;
    sc = math.max(0.5, 1 - math.min(a, 1) * (0.14 + tight) - far * 0.1);
    final step = ((room - card * 0.14) / 3.6).clamp(card * 0.12, card * 0.24);
    x = t * card * 0.5 + d.sign * far * step;
    z = 0;
  }
  final opacity = (1 - math.max(0, a - 3.6) * 0.8).clamp(0.0, 1.0);
  if (opacity <= 0) return null;
  final m = Matrix4.identity()
    ..setEntry(3, 2, (cover ? 0.42 : 0.5) / card)
    ..translateByDouble(x, 0, z, 1)
    ..rotateY(t * angle)
    ..scaleByDouble(sc, sc, 1, 1);
  return (transform: m, opacity: opacity, dim: cover ? (a * 0.22).clamp(0.0, 0.5) : (a * 0.16).clamp(0.0, 0.45));
}

/// 卡片流中的一张卡片：封面 + 底部渐变上的歌名与歌手。
class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.song, required this.size, required this.current, required this.dim});

  final Song song;
  final double size;
  final bool current;
  final double dim;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return YBox(
      width: size,
      height: size,
      clip: true,
      radius: BorderRadius.circular(size * 0.09),
      shadows: [Shadow2(0, 22, 44, CoverThemed.shadowOf(context).withValues(alpha: current ? 0.34 : 0.18))],
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverImage(song.coverUrl, imageSize: (size * dpr).round().clamp(200, 900)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x00000000), Color(0x8C000000)],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
          Positioned(
            left: size * 0.07,
            right: size * 0.07,
            bottom: size * 0.06,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(math.max(13, size * 0.07), weight: w700, color: Colors.white),
                ),
                Text(
                  song.artistText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(math.max(11, size * 0.045), color: const Color(0xCCFFFFFF)),
                ),
              ],
            ),
          ),
          if (dim > 0) ColoredBox(color: Colors.black.withValues(alpha: dim)),
        ],
      ),
    );
  }
}

/// 3D 封面流中的封面：下方带渐隐倒影。
class _Reflected extends StatelessWidget {
  const _Reflected({required this.song, required this.size, required this.dim});

  final Song song;
  final double size;
  final double dim;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final image = CoverImage(song.coverUrl, imageSize: (size * dpr).round().clamp(200, 900));
    final r = BorderRadius.circular(size * 0.05);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        YBox(
          width: size,
          height: size,
          clip: true,
          radius: r,
          shadows: [Shadow2(0, 18, 36, CoverThemed.shadowOf(context).withValues(alpha: 0.28))],
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              if (dim > 0) ColoredBox(color: Colors.black.withValues(alpha: dim)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: size,
          height: size * 0.3,
          child: ClipRect(
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x55000000), Color(0x00000000)],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: size,
                child: Transform.flip(
                  flipY: true,
                  child: ClipRRect(
                    borderRadius: r,
                    child: SizedBox(width: size, height: size, child: image),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 照片墙：播放队列铺成多列瀑布流，卡片高矮错落，底部显示歌名与歌手；当前歌曲加描边与跳动的均衡条，
/// 切歌时自动滚动到当前歌曲，点按其他卡片播放那一首。
class QueueWall extends StatefulWidget {
  const QueueWall({super.key, required this.height, this.tile = 112});

  final double height;

  /// 期望的卡片宽度，按可用宽度换算列数。
  final double tile;

  @override
  State<QueueWall> createState() => _QueueWallState();
}

/// 瀑布流的卡片高宽比，按歌曲 id 取，切歌时布局不变。
const _wallRatios = [1.0, 1.34, 0.8, 1.18, 0.92, 1.42, 1.08, 0.86];

/// 按列数排出瀑布流：每张卡片放进当前最短的一列。返回每张卡片的位置与总高度。
@visibleForTesting
({List<Rect> rects, double height}) wallLayout(List<String> ids, double width, int columns, double gap) {
  final w = (width - gap * (columns - 1)) / columns;
  final heights = List<double>.filled(columns, 0);
  final rects = <Rect>[];
  for (final id in ids) {
    var col = 0;
    for (var c = 1; c < columns; c++) {
      if (heights[c] < heights[col] - 0.5) col = c;
    }
    final h = w * _wallRatios[(id.hashCode & 0x7fffffff) % _wallRatios.length];
    rects.add(Rect.fromLTWH(col * (w + gap), heights[col], w, h));
    heights[col] += h + gap;
  }
  return (rects: rects, height: heights.fold(0.0, math.max) - gap);
}

class _QueueWallState extends State<QueueWall> {
  final _scroll = ScrollController();
  String? _focused;
  ({List<Rect> rects, double height})? _layout;
  List<Song>? _laidQueue;
  double _laidWidth = 0;

  static const _gap = 10.0;
  static const _pad = 12.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  ({List<Rect> rects, double height}) _layoutFor(List<Song> queue, double width) {
    if (_layout == null || !identical(_laidQueue, queue) || _laidWidth != width) {
      final columns = (width / (widget.tile + _gap)).round().clamp(3, 8);
      _layout = wallLayout([for (final s in queue) s.id], width, columns, _gap);
      _laidQueue = queue;
      _laidWidth = width;
    }
    return _layout!;
  }

  /// 把当前歌曲的卡片滚到中间。
  void _focus(Song song, Rect rect) {
    final key = '${song.id}@${rect.top}';
    if (key == _focused) return;
    final first = _focused == null;
    _focused = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = (rect.center.dy + _pad - widget.height / 2).clamp(0.0, _scroll.position.maxScrollExtent);
      if (first) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 560), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final queue = player.queue;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, c) {
          if (queue.isEmpty) return const SizedBox.shrink();
          final layout = _layoutFor(queue, c.maxWidth);
          final index = player.index.clamp(0, queue.length - 1);
          _focus(queue[index], layout.rects[index]);
          return ShaderMask(
            // 上下边缘渐隐。
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
              stops: [0, 0.06, 0.94, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: _pad),
              child: SizedBox(
                width: c.maxWidth,
                height: layout.height,
                // 只构建可见范围附近的卡片：播放队列可能有上千首。
                child: ListenableBuilder(
                  listenable: _scroll,
                  builder: (context, _) {
                    final top = (_scroll.hasClients ? _scroll.offset : 0) - widget.height;
                    final bottom = top + widget.height * 3;
                    return Stack(
                      children: [
                        for (var i = 0; i < queue.length; i++)
                          if (layout.rects[i].bottom >= top && layout.rects[i].top <= bottom)
                            Positioned.fromRect(
                              key: ValueKey(i),
                              rect: layout.rects[i],
                              child: _WallTile(song: queue[i], current: i == index, playing: player.playing, index: i),
                            ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 照片墙中的一张卡片。
class _WallTile extends StatelessWidget {
  const _WallTile({required this.song, required this.current, required this.playing, required this.index});

  final Song song;
  final bool current;
  final bool playing;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final small = w < 90;
        return Pressable(
          onTap: () => current ? openLyrics(context) : context.read<PlayerController>().jumpTo(song),
          scale: 0.96,
          semanticLabel: current ? '${song.name}，正在播放' : '播放${song.name}',
          child: AnimatedScale(
            scale: current ? 1 : 0.97,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            child: YBox(
              clip: true,
              radius: BorderRadius.circular(14),
              shadows: current ? [Shadow2(0, 14, 28, CoverThemed.shadowOf(context).withValues(alpha: 0.36))] : const [],
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverImage(song.coverUrl, imageSize: (math.max(w, c.maxHeight) * dpr).round().clamp(150, 700)),
                  if (!small)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0x00000000), Color(0xA6000000)],
                          stops: [0, 0.5, 1],
                        ),
                      ),
                    ),
                  if (!small)
                    Positioned(
                      left: 9,
                      right: 9,
                      bottom: 8,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  song.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ts(w > 150 ? 14 : 12, weight: w700, color: Colors.white),
                                ),
                                Text(
                                  song.artistText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ts(w > 150 ? 12 : 10.5, color: const Color(0xCCFFFFFF)),
                                ),
                              ],
                            ),
                          ),
                          if (current) ...[
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: NowPlayingBars(color: Colors.white, playing: playing),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (current)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.playerAccent ?? p.accentText, width: 2.5),
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

/// 极简样式的封面：小圆形封面，外圈一层柔和光晕，播放时缓慢旋转。
class MinimalArt extends StatelessWidget {
  const MinimalArt({super.key, required this.song, required this.size});

  final Song song;
  final double size;

  @override
  Widget build(BuildContext context) {
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final glow = CoverThemed.shadowOf(context);
    return Pressable(
      onTap: () => openLyrics(context),
      scale: 1,
      semanticLabel: '封面，点按查看歌词',
      child: AnimatedScale(
        scale: playing ? 1 : 0.92,
        duration: const Duration(milliseconds: 520),
        curve: playing ? Curves.easeOutBack : Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x33FFFFFF),
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: playing ? 0.45 : 0.25),
                blurRadius: size * 0.3,
                spreadRadius: size * 0.02,
              ),
            ],
          ),
          child: Cover(song.coverUrl, size: size, circle: true, imageSize: 600),
        ),
      ),
    );
  }
}
