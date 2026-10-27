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
import '../../data/sources/source_manager.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../common/song_row.dart';
import '../discover/discover_page.dart';
import '../shell/nav.dart';

String fansText(int? fans) {
  if (fans == null || fans <= 0) return '歌手';
  if (fans >= 10000) return '歌手 · ${(fans / 10000).toStringAsFixed(1)} 万粉丝';
  return '歌手 · $fans 粉丝';
}

class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key, required this.route});

  final ArtistRoute route;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  int _tab = 0;
  bool? _followed;

  @override
  Widget build(BuildContext context) {
    final source = context.read<SourceManager>().current;
    final desktop = LayoutScope.isDesktop(context);
    return AsyncView<ArtistInfo>(
      cacheKey: 'artist:${widget.route.id}',
      load: () => source.artist(widget.route.id),
      loading: _frame(context, ArtistInfo(id: widget.route.id, sourceId: source.id, name: widget.route.name ?? ''), loading: true),
      builder: (context, artist, _) => _frame(context, artist),
    ).withKey(desktop);
  }

  Widget _frame(BuildContext context, ArtistInfo a, {bool loading = false}) {
    final source = context.read<SourceManager>().current;
    final followed = _followed ?? a.followed;
    final children = <Widget>[
      _Hero(artist: a),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: followed ? '已关注' : '关注',
              icon: followed ? YIcons.check : YIcons.plus,
              iconSize: 18,
              height: 48,
              expand: true,
              onTap: loading
                  ? null
                  : () async {
                      try {
                        await source.followArtist(a.id, !followed);
                        setState(() => _followed = !followed);
                        if (context.mounted) Toast.show(context, followed ? '已取消关注' : '已关注 ${a.name}');
                      } catch (e) {
                        if (context.mounted) Toast.show(context, errorText(e), icon: YIcons.info);
                      }
                    },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SecondaryButton(
              label: '播放热门',
              icon: YIcons.play,
              iconSize: 18,
              height: 48,
              onTap: () => playAll(context, a.hotSongs, title: '${a.name} · 热门歌曲'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      ChipBar(labels: const ['热门歌曲', '专辑', '相似歌手'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
      const SizedBox(height: 14),
      if (loading)
        const SkeletonList()
      else
        EntranceFade(
          key: ValueKey(_tab),
          child: switch (_tab) {
            0 => _HotSongs(artist: a),
            1 => AsyncView<List<AlbumInfo>>(
              cacheKey: 'artistAlbums:${a.id}',
              load: () => source.artistAlbums(a.id),
              builder: (c, list, _) => AlbumGrid(items: list),
            ),
            _ => AsyncView<List<ArtistInfo>>(
              cacheKey: 'similarArtists:${a.id}',
              load: () => source.similarArtists(a.id),
              builder: (c, list, _) => ArtistStrip(artists: list, wrap: true),
            ),
          },
        ),
    ];
    return AdaptivePage(
      mobileTop: 76,
      overlay: [
        Positioned(
          left: 16,
          top: 20,
          child: GlassButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop()),
        ),
        Positioned(
          right: 16,
          top: 20,
          child: GlassButton(
            YIcons.more,
            label: '更多',
            onTap: () async {
              final v = await showOptions<int>(context, title: a.name, options: const [(0, '热门歌曲加入播放队列'), (1, '下载热门歌曲')]);
              if (!context.mounted) return;
              if (v == 0) {
                context.read<PlayerController>().addToQueue(a.hotSongs);
                Toast.show(context, '已加入播放队列');
              }
              if (v == 1) downloadSongs(context, a.hotSongs);
            },
          ),
        ),
      ],
      children: children,
    );
  }
}

extension on Widget {
  Widget withKey(Object key) => KeyedSubtree(key: ValueKey(key), child: this);
}

class _HotSongs extends StatelessWidget {
  const _HotSongs({required this.artist});

  final ArtistInfo artist;

  @override
  Widget build(BuildContext context) {
    final songs = artist.hotSongs;
    if (LayoutScope.isDesktop(context)) {
      return CardList(
        indent: 66,
        children: [
          for (var i = 0; i < songs.length; i++)
            DesktopSongRow(
              song: songs[i],
              cover: true,
              onTap: () => playAll(context, songs, start: i, title: '${artist.name} · 热门歌曲'),
            ),
        ],
      );
    }
    return CardList(
      indent: 70,
      children: [
        for (var i = 0; i < songs.length; i++)
          SongRow(
            song: songs[i],
            subtitle: [songs[i].albumName, if (songs[i].playCount != null) songs[i].playCount!].where((s) => s.isNotEmpty).join(' · '),
            onTap: () => playAll(context, songs, start: i, title: '${artist.name} · 热门歌曲'),
          ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.artist});

  final ArtistInfo artist;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final art = artist.avatar == null || artist.avatar!.isEmpty;
    return YBox(
      clip: true,
      height: 232,
      radius: BorderRadius.circular(34),
      gradient: CssGradient(150, colors: p.artistGradient),
      shadows: const [Shadow2(0, 18, 40, Color.fromRGBO(255, 140, 90, 0.28))],
      insets: [Shadow2(0, 1, 0, p.highlightInset)],
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 350,
            child: CustomPaint(painter: _HeroArt(drawFigure: art)),
          ),
          if (!art)
            Positioned(
              right: 92 - 62,
              top: 86 - 62,
              child: Cover(artist.avatar, size: 124, circle: true, imageSize: 400, shadows: const [Shadow2(0, 14, 30, Color.fromRGBO(120, 60, 30, 0.3))]),
            ),
          Positioned(
            left: 22,
            bottom: 20,
            right: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name,
                  style: ts(34, weight: w700, em: -0.02, height: 1.1, color: p.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(fansText(artist.fans), style: ts(13, color: p.dailyDesc, tabular: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroArt extends CustomPainter {
  _HeroArt({required this.drawFigure});

  final bool drawFigure;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width - 350, 0);
    final dark = Paint()..color = const Color(0xFF1D1D1F);
    if (drawFigure) {
      canvas.drawCircle(const Offset(258, 86), 62, Paint()..color = const Color(0xFFFF6A57));
      canvas.drawCircle(const Offset(258, 86), 34, Paint()..color = const Color(0xFFFFF4E8));
      final body = Path()
        ..moveTo(170, 232)
        ..cubicTo(170, 184, 208, 156, 258, 156)
        ..cubicTo(308, 156, 346, 184, 346, 232)
        ..close();
      canvas.drawPath(body, dark);
      canvas.drawCircle(const Offset(258, 116), 22, dark);
    }
    canvas.drawCircle(const Offset(316, 34), 6, Paint()..color = const Color(0xFFFFC83D));
    canvas.drawCircle(const Offset(196, 48), 4, dark);
  }

  @override
  bool shouldRepaint(_HeroArt old) => old.drawFigure != drawFigure;
}

/// 一排歌手头像（搜索结果“相关歌手”、歌手页“相似歌手”）。
class ArtistStrip extends StatelessWidget {
  const ArtistStrip({super.key, required this.artists, this.wrap = false});

  final List<ArtistInfo> artists;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget item(ArtistInfo a) => Pressable(
      onTap: () => go(context, ArtistRoute(a.id, name: a.name)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Cover(
            a.avatar,
            size: 64,
            circle: true,
            shadows: [Shadow2(0, 8, 18, p.isDark ? const Color.fromRGBO(0, 0, 0, 0.4) : const Color.fromRGBO(28, 44, 92, 0.14))],
          ),
          const SizedBox(height: 8),
          Text(
            a.name,
            style: ts(13, weight: w600, color: p.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    if (artists.isEmpty) return const SizedBox.shrink();
    if (!wrap) {
      return Row(
        children: [
          for (var i = 0; i < artists.length && i < 4; i++) ...[if (i > 0) const SizedBox(width: 6), Expanded(child: item(artists[i]))],
          for (var i = artists.length; i < 4; i++) ...[const SizedBox(width: 6), const Expanded(child: SizedBox())],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final cols = LayoutScope.isDesktop(context) ? 8 : 4;
        final w = (c.maxWidth - 6 * (cols - 1)) / cols;
        return Wrap(
          spacing: 6,
          runSpacing: 16,
          children: [for (final a in artists) SizedBox(width: w, child: item(a))],
        );
      },
    );
  }
}
