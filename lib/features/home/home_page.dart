import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../data/sources/music_source.dart';
import '../../data/sources/source_manager.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../common/song_row.dart';
import '../shell/nav.dart';

String todayText([DateTime? now]) {
  final d = now ?? DateTime.now();
  const w = '一二三四五六日';
  return '${d.month}月${d.day}日 星期${w[d.weekday - 1]}';
}

String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h >= 5 && h < 11) return '早安';
  if (h >= 11 && h < 13) return '午安';
  if (h >= 13 && h < 18) return '下午好';
  return '晚上好';
}

PlaylistInfo dailyPlaylist(MusicSource source, List<Song> songs) => PlaylistInfo(
  id: 'daily',
  sourceId: source.id,
  name: '每日推荐',
  cover: songs.firstOrNull?.coverUrl,
  creator: source.loggedIn ? '根据你的口味生成' : '飙升榜精选',
  description: '新歌与老朋友，每天清晨更新',
  trackCount: songs.length,
  kind: PlaylistKind.daily,
  tracks: songs,
);

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sources = context.watch<SourceManager>();
    final source = sources.current;
    final user = source.user;
    return MobilePage(
      top: 22,
      children: [
        // 日期与问候语和头像同一行，头像与文字块垂直居中。
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todayText(),
                    style: ts(13, weight: w600, color: p.text2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    greeting(),
                    style: ts(36, weight: w700, em: -0.02, height: 1.1, color: p.text),
                  ),
                ],
              ),
            ),
            if (user?.avatar != null)
              Pressable(onTap: () => context.read<AppNav>().switchTab(2), semanticLabel: '个人主页', child: Cover(user!.avatar, size: 44, circle: true))
            else
              CircleButton(
                YIcons.user,
                size: 44,
                iconSize: 22,
                color: p.text3,
                label: '个人主页',
                onTap: () => user == null && source.supports(SourceFeature.login) ? go(context, LoginRoute()) : context.read<AppNav>().switchTab(2),
              ),
          ],
        ),
        AsyncView<HomeFeed>(
          keyValue: sources.generation,
          load: source.homeFeed,
          loading: const Padding(padding: EdgeInsets.only(top: 20), child: SkeletonList()),
          builder: (context, feed, _) => _HomeBody(feed: feed),
        ),
      ],
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.feed});

  final HomeFeed feed;

  @override
  Widget build(BuildContext context) {
    final source = context.read<SourceManager>().current;
    final player = context.watch<PlayerController>();
    final recent = player.history.take(4).toList();
    final daily = dailyPlaylist(source, feed.daily);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        DailyCard(
          height: 196,
          songs: feed.daily,
          onOpen: () => openPlaylist(context, daily),
          onPlay: () => playAll(context, feed.daily, title: '每日推荐'),
        ),
        SectionHeader('歌单精选', action: '全部', onAction: () => context.read<AppNav>().switchTab(1)),
        _Bleed(
          right: 20,
          height: 132 + 9 + 20 + 2 + 17,
          child: SizedBox(
            height: 132 + 9 + 20 + 2 + 17,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(right: 20),
              itemCount: feed.playlists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final pl = feed.playlists[i];
                return PlaylistTile(width: 132, cover: pl.cover, title: pl.name, subtitle: playlistSubtitle(pl), onTap: () => openPlaylist(context, pl));
              },
            ),
          ),
        ),
        SectionHeader('最近播放', action: '更多', onAction: () => go(context, CollectionRoute(PlaylistKind.recent))),
        if (recent.isEmpty)
          const EmptyRecent()
        else
          CardList(
            indent: 70,
            children: [
              for (final s in recent)
                SongRow(
                  song: s,
                  onTap: () => playAll(context, recent, start: recent.indexOf(s), title: '最近播放'),
                ),
            ],
          ),
      ],
    );
  }
}

/// 让子组件向右延伸到屏幕边缘（设计稿中的 margin-right: -20px）。
class _Bleed extends StatelessWidget {
  const _Bleed({required this.child, required this.height, this.right = 0});

  final Widget child;
  final double height;
  final double right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return SizedBox(
          width: c.maxWidth,
          height: height,
          child: OverflowBox(alignment: Alignment.centerLeft, minWidth: c.maxWidth + right, maxWidth: c.maxWidth + right, child: child),
        );
      },
    );
  }
}

/// 每日推荐大卡片（桃色渐变 + 随机推荐歌曲的封面 + 播放全部）。
class DailyCard extends StatefulWidget {
  const DailyCard({super.key, required this.height, this.songs = const [], this.onOpen, this.onPlay, this.desktop = false});

  final double height;
  final List<Song> songs;
  final VoidCallback? onOpen;
  final VoidCallback? onPlay;
  final bool desktop;

  @override
  State<DailyCard> createState() => _DailyCardState();
}

class _DailyCardState extends State<DailyCard> {
  static final _random = math.Random();
  List<String> _covers = const [];

  @override
  void initState() {
    super.initState();
    _pick();
  }

  @override
  void didUpdateWidget(DailyCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.songs, widget.songs)) _pick();
  }

  /// 每次进入首页随机取三首推荐歌曲的封面。
  void _pick() {
    final urls = {for (final s in widget.songs) ?s.coverUrl}.toList()..shuffle(_random);
    _covers = urls.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = widget.desktop;
    final height = widget.height;
    final onOpen = widget.onOpen;
    final onPlay = widget.onPlay;
    final p = Palette.of(context);
    return Pressable(
      onTap: onOpen,
      scale: 0.99,
      child: YBox(
        clip: true,
        height: height,
        radius: BorderRadius.circular(desktop ? 30 : 28),
        gradient: CssGradient(150, colors: p.dailyGradient),
        shadows: const [Shadow2(0, 16, 34, Color.fromRGBO(255, 106, 87, 0.22))],
        insets: [Shadow2(0, 1, 0, p.highlightInset)],
        child: Stack(
          children: [
            if (_covers.isEmpty)
              Positioned(
                right: 0,
                top: 0,
                child: CustomPaint(
                  size: desktop ? const Size(340, 208) : const Size(170, 196),
                  painter: _DailyArt(desktop, p.isDark ? const Color(0xFFFFE3DA) : const Color(0xFF1D1D1F)),
                ),
              )
            else
              Positioned(
                right: desktop ? 36 : 14,
                top: 0,
                bottom: 0,
                width: desktop ? 300 : 150,
                child: _CoverStack(covers: _covers, size: desktop ? 136 : 98),
              ),
            Padding(
              padding: EdgeInsets.all(desktop ? 28 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(color: p.dailyLabelBg, borderRadius: BorderRadius.circular(9)),
                        child: Text(
                          'DAILY MIX',
                          style: ts(11, weight: w700, em: 0.1, color: p.dailyLabel),
                        ),
                      ),
                      SizedBox(height: desktop ? 8 : 6),
                      Text(
                        '每日推荐',
                        style: ts(desktop ? 36 : 30, weight: w700, em: -0.02, height: 1.12, color: p.text),
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: desktop ? 400 : 150),
                        child: Text(
                          '新歌与老朋友，每天清晨更新',
                          style: ts(desktop ? 14 : 13, height: desktop ? null : 1.5, color: p.dailyDesc),
                        ),
                      ),
                    ],
                  ),
                  PrimaryButton(
                    label: '播放全部',
                    icon: YIcons.play,
                    iconSize: 17,
                    height: 42,
                    fontSize: 15,
                    padding: EdgeInsets.fromLTRB(desktop ? 18 : 16, 0, desktop ? 22 : 20, 0),
                    onTap: onPlay,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyArt extends CustomPainter {
  _DailyArt(this.desktop, this.ring);

  final bool desktop;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final coral = Paint()..color = const Color(0xFFFF6A57);
    final yellow = Paint()..color = const Color(0xFFFFC83D);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = ring;
    if (desktop) {
      canvas.drawCircle(const Offset(230, 80), 86, coral);
      canvas.drawCircle(const Offset(170, 170), 48, stroke..strokeWidth = 10);
      canvas.drawCircle(const Offset(300, 170), 14, yellow);
    } else {
      canvas.drawCircle(const Offset(126, 66), 56, coral);
      canvas.drawCircle(const Offset(96, 146), 36, stroke..strokeWidth = 8);
      canvas.drawCircle(const Offset(150, 148), 10, yellow);
    }
  }

  @override
  bool shouldRepaint(_DailyArt old) => old.desktop != desktop || old.ring != ring;
}

/// 三张错落叠放的封面，前景一张最大。
class _CoverStack extends StatelessWidget {
  const _CoverStack({required this.covers, required this.size});

  final List<String> covers;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shadow = [const Shadow2(0, 14, 28, Color.fromRGBO(120, 40, 20, 0.28))];
    Widget card(String url, double s, double angle) => Transform.rotate(
      angle: angle,
      child: YBox(
        width: s,
        height: s,
        radius: BorderRadius.circular(s * 0.16),
        shadows: shadow,
        clip: true,
        child: Cover(url, size: s, radius: s * 0.16),
      ),
    );
    final back = size * 0.78;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (covers.length > 2) Positioned(right: 0, top: 16, child: Opacity(opacity: 0.9, child: card(covers[2], back, 0.16))),
        if (covers.length > 1) Positioned(left: 0, bottom: 16, child: Opacity(opacity: 0.95, child: card(covers[1], back, -0.14))),
        card(covers[0], size, 0.04),
      ],
    );
  }
}

/// 私人雷达卡片（桌面端首页右侧）。
class RadarCard extends StatelessWidget {
  const RadarCard({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: YBox(
        clip: true,
        height: 208,
        radius: BorderRadius.circular(30),
        gradient: CssGradient(150, colors: p.albumGradient),
        shadows: const [Shadow2(0, 16, 34, Color.fromRGBO(20, 145, 127, 0.20))],
        insets: [Shadow2(0, 1, 0, p.highlightInset)],
        child: Stack(
          children: [
            Positioned(
              right: 0,
              bottom: 0,
              child: CustomPaint(size: const Size(170, 208), painter: _RadarArt()),
            ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RADAR',
                    style: ts(12, weight: w600, em: 0.12, color: p.albumDesc),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '私人雷达',
                    style: ts(28, weight: w700, em: -0.02, height: 1.12, color: p.text),
                  ),
                  const SizedBox(height: 6),
                  Text('按你的口味发现新歌', style: ts(14, color: p.albumDesc)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarArt extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(const Offset(110, 130), 40, Paint()..color = const Color(0xFFFFD45E));
    canvas.drawRect(const Rect.fromLTWH(40, 130, 130, 78), Paint()..color = const Color(0xFF3BB7A5));
    final bar = Paint()..color = const Color(0xFFD9F0EA);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(62, 150, 76, 5), const Radius.circular(2.5)), bar);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(84, 168, 64, 5), const Radius.circular(2.5)), bar);
  }

  @override
  bool shouldRepaint(_RadarArt old) => false;
}

/// 还没有播放记录时的提示。
class EmptyRecent extends StatelessWidget {
  const EmptyRecent({super.key});

  @override
  Widget build(BuildContext context) {
    return YCard(
      child: StateView.empty(title: '还没有播放记录', message: '播放过的歌曲会出现在这里。', icon: YIcons.clock),
    );
  }
}
