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
    final room = math.max(0.0, (width - card) / 2);
    final near = card * 0.5 + (_cover ? (room * 0.3).clamp(card * 0.12, card * 0.32) : (room * 0.42).clamp(card * 0.2, card * 0.46));
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
    final first = math.max(0, (page - 4).floor());
    final last = math.min(queue.length - 1, (page + 4).ceil());
    final items = <(double, Widget)>[];
    for (var i = first; i <= last; i++) {
      final d = i - page;
      final a = d.abs();
      final Matrix4 m;
      double x;
      if (_cover) {
        // 3D 封面流：中心正对，两侧翻转约 55° 后退。第一张与中心留出明显间隔，之后依次叠放。
        // 透视强度按卡片大小换算（Flutter 中 z 为正表示远离观察者）。
        final t = d.clamp(-1.0, 1.0);
        final near = card * 0.5 + (room * 0.3).clamp(card * 0.12, card * 0.32);
        final step = ((room - (near - card * 0.5)) / 3.2).clamp(card * 0.14, card * 0.3);
        x = t * near + (d - t) * step;
        final sc = 1 - math.min(a, 1) * 0.12;
        m = Matrix4.identity()
          ..setEntry(3, 2, 0.5 / card)
          ..translateByDouble(x, 0, math.min(a, 1) * card * 0.3 + math.max(0, a - 1) * card * 0.04, 1)
          ..rotateY(-t * 0.96)
          ..scaleByDouble(sc, sc, 1, 1);
      } else {
        // 卡片流：两侧卡片缩小、向内倾斜，与中心卡片之间按可用宽度留出间隔。
        final sc = math.max(0.58, 1 - a * 0.2);
        final near = card * 0.5 + (room * 0.42).clamp(card * 0.2, card * 0.46);
        final step = ((room - (near - card * 0.5)) / 2.2).clamp(card * 0.16, card * 0.48);
        x = d.sign * (math.min(a, 1) * near + math.max(0, a - 1) * step);
        m = Matrix4.identity()
          ..setEntry(3, 2, 0.0011)
          ..translateByDouble(x, 0, 0, 1)
          ..rotateY(-d.clamp(-2.0, 2.0) * 0.38)
          ..scaleByDouble(sc, sc, 1, 1);
      }
      final opacity = (1 - math.max(0, a - 2.2) * 0.6).clamp(0.0, 1.0);
      if (opacity <= 0) continue;
      items.add((
        a,
        Positioned(
          key: ValueKey(i),
          left: box.width / 2 - card / 2,
          top: _cover ? (box.height - card * 1.32) / 2 : (box.height - card) / 2,
          width: card,
          child: IgnorePointer(
            child: Transform(
              alignment: Alignment.center,
              transform: m,
              child: Opacity(
                opacity: opacity,
                child: _cover
                    ? _Reflected(song: queue[i], size: card, dim: (a * 0.35).clamp(0.0, 0.55))
                    : _FlowCard(song: queue[i], size: card, current: i == player.index, dim: (a * 0.28).clamp(0.0, 0.5)),
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

/// 照片墙：播放队列铺成封面网格，当前歌曲放大并显示跳动的均衡条，切歌时自动滚动到当前歌曲。
class QueueWall extends StatefulWidget {
  const QueueWall({super.key, required this.height, this.tile = 104});

  final double height;
  final double tile;

  @override
  State<QueueWall> createState() => _QueueWallState();
}

class _QueueWallState extends State<QueueWall> {
  final _scroll = ScrollController();
  int _focused = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _focus(int index, int columns, double extent) {
    if (index == _focused) return;
    final first = _focused < 0;
    _focused = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final row = index ~/ columns;
      final target = (row * extent - (widget.height - extent) / 2).clamp(0.0, _scroll.position.maxScrollExtent);
      if (first) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final queue = player.queue;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, c) {
          const gap = 10.0;
          final columns = math.max(3, ((c.maxWidth + gap) / (widget.tile + gap)).floor());
          final tile = (c.maxWidth - gap * (columns - 1)) / columns;
          _focus(player.index, columns, tile + gap);
          return ShaderMask(
            // 上下边缘渐隐。
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
              stops: [0, 0.06, 0.94, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: gap, crossAxisSpacing: gap),
              itemCount: queue.length,
              itemBuilder: (context, i) {
                final current = i == player.index;
                final song = queue[i];
                return Pressable(
                  onTap: () => current ? openLyrics(context) : player.jumpTo(song),
                  scale: 0.95,
                  semanticLabel: current ? '${song.name}，正在播放' : '播放${song.name}',
                  child: AnimatedScale(
                    scale: current ? 1 : 0.94,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutBack,
                    child: YBox(
                      clip: true,
                      radius: BorderRadius.circular(16),
                      shadows: current ? [Shadow2(0, 14, 28, CoverThemed.shadowOf(context).withValues(alpha: 0.32))] : const [],
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CoverImage(song.coverUrl, imageSize: (tile * dpr).round()),
                          if (current) ...[
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: p.accentText, width: 2.5),
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x00000000), Color(0x99000000)],
                                  stops: [0.45, 1],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 7,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      song.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: ts(12, weight: w700, color: Colors.white),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: NowPlayingBars(color: Colors.white, playing: player.playing),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
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
