import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../common/actions.dart';
import '../common/song_row.dart';

/// 照片墙中的一张封面：歌单或歌曲。
class FeedItem {
  const FeedItem.playlist(PlaylistInfo this.playlist) : song = null;
  const FeedItem.song(Song this.song) : playlist = null;

  final PlaylistInfo? playlist;
  final Song? song;

  String? get cover => playlist?.cover ?? song?.coverUrl;
  String get title => playlist?.name ?? song!.name;
  String get subtitle => playlist != null ? playlistSubtitle(playlist!) : song!.artistText;
}

/// 歌单与每日推荐歌曲交错排列。
List<FeedItem> feedItems(HomeFeed feed) {
  final out = <FeedItem>[];
  final pls = feed.playlists;
  final songs = feed.daily;
  for (var i = 0; i < math.max(pls.length, songs.length); i++) {
    if (i < pls.length) out.add(FeedItem.playlist(pls[i]));
    if (i < songs.length) out.add(FeedItem.song(songs[i]));
  }
  return out;
}

void _open(BuildContext context, FeedItem item, List<FeedItem> all) {
  final pl = item.playlist;
  if (pl != null) {
    openPlaylist(context, pl);
    return;
  }
  final songs = [
    for (final x in all)
      if (x.song != null) x.song!,
  ];
  playAll(context, songs, start: songs.indexOf(item.song!), title: '每日推荐');
}

/// 无限照片墙：封面铺满整个区域，可以向任意方向拖动（松手后惯性滑动），静止时缓慢漂移。
/// 奇数列错开半格。点按歌曲封面播放，点按歌单封面打开歌单。
class PhotoWall extends StatefulWidget {
  const PhotoWall({super.key, required this.feed, this.tile = 128, this.gap = 8});

  final HomeFeed feed;
  final double tile;
  final double gap;

  @override
  State<PhotoWall> createState() => _PhotoWallState();
}

class _PhotoWallState extends State<PhotoWall> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<Offset> _offset = ValueNotifier(Offset.zero);
  late List<FeedItem> _items = feedItems(widget.feed);
  FrictionSimulation? _fx, _fy;
  Duration _flingStart = Duration.zero;
  Duration _last = Duration.zero;
  bool _dragging = false;

  static const _drift = Offset(-9, -5); // 静止时的漂移速度（像素 / 秒）

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void didUpdateWidget(PhotoWall old) {
    super.didUpdateWidget(old);
    if (!identical(old.feed, widget.feed)) _items = feedItems(widget.feed);
    _gridChild = null;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _tick(Duration t) {
    final dt = _last == Duration.zero ? 0.0 : (t - _last).inMicroseconds / 1e6;
    _last = t;
    if (_dragging) return;
    if (_fx != null) {
      final s = (t - _flingStart).inMicroseconds / 1e6;
      _offset.value = Offset(_fx!.x(s), _fy!.x(s));
      if (_fx!.isDone(s) && _fy!.isDone(s)) _fx = _fy = null;
      return;
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _offset.value += _drift * dt;
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            _dragging = true;
            _fx = _fy = null;
          },
          onPanUpdate: (d) => _offset.value += d.delta,
          onPanEnd: (d) {
            _dragging = false;
            final v = d.velocity.pixelsPerSecond;
            _fx = FrictionSimulation(0.12, _offset.value.dx, v.dx);
            _fy = FrictionSimulation(0.12, _offset.value.dy, v.dy);
            _flingStart = _last;
          },
          child: ClipRect(
            child: ValueListenableBuilder<Offset>(valueListenable: _offset, builder: (context, o, _) => _grid(context, c.biggest, o)),
          ),
        );
      },
    );
  }

  /// 已经搭好的格子：只在露出新的一行或一列（左上角格子变化）、尺寸或封面列表变化时重建。
  /// 之间的移动只改整片格子的位移（单独的图层，不重建、不重绘每一张封面）：此前每一帧都重建、重新排版并重绘
  /// 所有封面，Linux / Windows 上每张封面的圆角还各开一个图层，照片墙在这两个平台上掉帧严重。
  (int, int, Size, int, double)? _gridKey;
  Widget? _gridChild;

  Widget _grid(BuildContext context, Size size, Offset o) {
    final stride = widget.tile + widget.gap;
    final c0 = (-o.dx / stride).floor() - 1;
    // 奇数列错开半格：按错开后的位置多留一行。
    final r0 = ((-o.dy - stride / 2) / stride).floor() - 1;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final key = (c0, r0, size, _items.length, dpr);
    if (key != _gridKey || _gridChild == null) {
      _gridKey = key;
      _gridChild = RepaintBoundary(child: _tiles(size, c0, r0, stride, dpr));
    }
    return Transform.translate(offset: Offset(c0 * stride + o.dx, r0 * stride + o.dy), child: _gridChild);
  }

  /// 以 ([c0], [r0]) 号格子为原点排出铺满 [size]（多留两格）的封面。
  Widget _tiles(Size size, int c0, int r0, double stride, double dpr) {
    final cols = (size.width / stride).ceil() + 3;
    final rows = (size.height / stride).ceil() + 4;
    final n = _items.length;
    final tiles = <Widget>[];
    for (var dc = 0; dc < cols; dc++) {
      final col = c0 + dc;
      final stagger = col.isOdd ? stride / 2 : 0.0;
      for (var dr = 0; dr < rows; dr++) {
        final row = r0 + dr;
        // 相邻格子取不同的封面：横向相差 7 张，纵向相差 3 张。
        final item = _items[((col * 7 + row * 3) % n + n) % n];
        tiles.add(
          Positioned(
            key: ValueKey((col, row)),
            left: dc * stride,
            top: dr * stride + stagger,
            width: widget.tile,
            height: widget.tile,
            child: Semantics(
              label: item.title,
              button: true,
              child: GestureDetector(
                onTap: () => _open(context, item, _items),
                // 封面直接作为圆角盒子的内容：桌面端走“画成抗锯齿圆角图片”的快速路径，不另开遮罩图层。
                child: YBox(
                  clip: true,
                  radius: BorderRadius.circular(16),
                  child: CoverImage(item.cover, imageSize: (widget.tile * dpr).round()),
                ),
              ),
            ),
          ),
        );
      }
    }
    return Stack(clipBehavior: Clip.none, children: tiles);
  }
}

/// 照片墙首页的悬浮标题：问候语 + 随机播放。
class PhotoWallHeader extends StatelessWidget {
  const PhotoWallHeader({super.key, required this.title, required this.subtitle, required this.feed, this.trailing});

  final String title;
  final String subtitle;
  final HomeFeed feed;

  /// 问候右侧的按钮；默认为随机播放每日推荐（手机竖屏照片墙传入个人中心头像）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Glass(
      radius: 26,
      legible: true,
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: ts(12, weight: w600, color: p.text2),
              ),
              Text(
                title,
                style: ts(24, weight: w700, em: -0.02, height: 1.15, color: p.text),
              ),
            ],
          ),
          const SizedBox(width: 14),
          ?trailing,
          if (trailing == null)
            Pressable(
              onTap: () => playAll(context, feed.daily, shuffle: true, title: '每日推荐'),
              semanticLabel: '随机播放每日推荐',
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: p.accentText, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const YIcon(YIcons.shuffle, size: 20, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
