import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../data/sources/source_manager.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../common/song_row.dart';
import '../shell/nav.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final desktop = LayoutScope.isDesktop(context);
    final sources = context.watch<SourceManager>();
    return AdaptivePage(
      mobileTop: 30,
      children: [
        PageTitle('发现', subtitle: '新歌 · 榜单 · 电台', size: desktop ? 40 : 36),
        const SizedBox(height: 18),
        ChipBar(labels: const ['推荐', '排行榜', '电台', '新碟'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
        KeyedSubtree(
          key: ValueKey('${sources.generation}-$_tab'),
          child: switch (_tab) {
            0 => const _Recommend(),
            1 => const _Charts(),
            2 => const _Radios(),
            _ => const _NewAlbums(),
          },
        ),
      ],
    );
  }
}

class _Recommend extends StatelessWidget {
  const _Recommend();

  @override
  Widget build(BuildContext context) {
    final source = context.read<SourceManager>().current;
    final desktop = LayoutScope.isDesktop(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        AsyncView<List<AlbumInfo>>(
          load: () => source.newAlbums(limit: 6),
          loading: const SizedBox(height: 160),
          builder: (context, albums, _) {
            if (albums.isEmpty) return const SizedBox.shrink();
            final a = albums.first;
            return NewAlbumBanner(
              album: a,
              onTap: () => go(context, AlbumRoute(a.id, preview: a)),
            );
          },
        ),
        AsyncView<PlaylistInfo>(
          load: source.soaringChart,
          builder: (context, chart, _) {
            final songs = (chart.tracks ?? const <Song>[]).take(desktop ? 10 : 5).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader('飙升榜', top: 26, action: '完整榜单', onAction: () => openPlaylist(context, chart)),
                CardList(
                  indent: 68,
                  children: [
                    for (var i = 0; i < songs.length; i++)
                      SongRow(
                        song: songs[i],
                        lead: SongLead.rank,
                        number: i + 1,
                        trailing: SongTrailing.play,
                        onTap: () => playAll(context, chart.tracks!, start: i, title: chart.name),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        if (desktop)
          AsyncView<List<PlaylistInfo>>(
            load: () => source.recommendPlaylists(limit: 12),
            loading: const SizedBox.shrink(),
            builder: (context, list, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader('推荐歌单', top: 26),
                PlaylistGrid(items: list),
              ],
            ),
          ),
      ],
    );
  }
}

/// “新碟首发”横幅（薄荷渐变）。
class NewAlbumBanner extends StatelessWidget {
  const NewAlbumBanner({super.key, required this.album, this.onTap});

  final AlbumInfo album;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final art = album.cover == null || album.cover!.isEmpty;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: YBox(
        clip: true,
        height: 160,
        radius: BorderRadius.circular(28),
        gradient: CssGradient(150, colors: p.albumGradient),
        shadows: const [Shadow2(0, 16, 34, Color.fromRGBO(20, 145, 127, 0.20))],
        insets: [Shadow2(0, 1, 0, p.highlightInset)],
        child: Stack(
          children: [
            if (art)
              Positioned(
                right: 0,
                top: 0,
                child: CustomPaint(size: const Size(190, 160), painter: _SeaArt()),
              )
            else
              Positioned(
                right: 22,
                top: 22,
                child: Cover(album.cover, size: 116, radius: 18, shadows: const [Shadow2(0, 10, 24, Color.fromRGBO(14, 107, 92, 0.3))]),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(22, 22, art ? 22 : 160, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: p.dailyLabelBg, borderRadius: BorderRadius.circular(9)),
                    child: Text(
                      'NEW ALBUM',
                      style: ts(11, weight: w700, em: 0.1, color: p.albumLabel),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    album.name,
                    style: ts(30, weight: w700, em: -0.02, height: 1.1, color: p.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${album.artist?.name ?? ''} · 新专辑首发',
                    style: ts(14, color: p.albumDesc),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _SeaArt extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(const Offset(132, 84), 42, Paint()..color = const Color(0xFFFFD45E));
    canvas.drawRect(const Rect.fromLTWH(70, 84, 120, 76), Paint()..color = const Color(0xFF3BB7A5));
    final bar = Paint()..color = const Color(0xFFD9F0EA);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(92, 102, 70, 5), const Radius.circular(2.5)), bar);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(112, 120, 60, 5), const Radius.circular(2.5)), bar);
  }

  @override
  bool shouldRepaint(_SeaArt old) => false;
}

class _Charts extends StatelessWidget {
  const _Charts();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final source = context.read<SourceManager>().current;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: AsyncView<List<ChartInfo>>(
        load: source.charts,
        builder: (context, charts, _) => CardList(
          indent: 78,
          children: [
            for (final c in charts)
              Pressable(
                onTap: () => go(context, PlaylistRoute(c.id, sourceId: source.id)),
                scale: 1,
                hoverColor: p.separator.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Cover(c.cover, size: 52, radius: 12),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: ts(15, weight: w600, color: p.text),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.preview.isNotEmpty ? c.preview.take(2).join('  ') : (c.update ?? ''),
                              style: ts(13, color: p.text2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (c.update != null) Text(c.update!, style: ts(12, color: p.text2)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Radios extends StatelessWidget {
  const _Radios();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final source = context.read<SourceManager>().current;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: AsyncView<List<RadioInfo>>(
        load: source.hotRadios,
        builder: (context, radios, _) => CardList(
          indent: 78,
          children: [
            for (final r in radios)
              Pressable(
                onTap: () => go(context, RadioRoute(r)),
                scale: 1,
                hoverColor: p.separator.withValues(alpha: 0.06),
                child: SizedBox(
                  height: 72,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Cover(r.cover, size: 52, radius: 12),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.name,
                                style: ts(15, weight: w600, color: p.text),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [r.host, if (r.programCount > 0) '${r.programCount} 期'].whereType<String>().join(' · '),
                                style: ts(13, color: p.text2),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                        if (r.category != null) Tag(r.category!, kind: TagKind.plain),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NewAlbums extends StatelessWidget {
  const _NewAlbums();

  @override
  Widget build(BuildContext context) {
    final source = context.read<SourceManager>().current;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: AsyncView<List<AlbumInfo>>(
        load: () => source.newAlbums(limit: 24),
        builder: (context, albums, _) => AlbumGrid(items: albums),
      ),
    );
  }
}

/// 歌单网格：移动端 2 列，桌面端 6 列。
class PlaylistGrid extends StatelessWidget {
  const PlaylistGrid({super.key, required this.items});

  final List<PlaylistInfo> items;

  @override
  Widget build(BuildContext context) {
    return CoverGrid(
      count: items.length,
      builder: (context, i) => PlaylistTile(
        cover: items[i].cover,
        title: items[i].name,
        subtitle: playlistSubtitle(items[i]),
        radius: LayoutScope.isDesktop(context) ? 18 : 20,
        onTap: () => openPlaylist(context, items[i]),
      ),
    );
  }
}

class AlbumGrid extends StatelessWidget {
  const AlbumGrid({super.key, required this.items});

  final List<AlbumInfo> items;

  @override
  Widget build(BuildContext context) {
    return CoverGrid(
      count: items.length,
      builder: (context, i) => PlaylistTile(
        cover: items[i].cover,
        title: items[i].name,
        subtitle: items[i].artist?.name ?? '',
        radius: LayoutScope.isDesktop(context) ? 18 : 20,
        onTap: () => go(context, AlbumRoute(items[i].id, preview: items[i])),
      ),
    );
  }
}

class CoverGrid extends StatelessWidget {
  const CoverGrid({super.key, required this.count, required this.builder});

  final int count;
  final IndexedWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final desktop = LayoutScope.isDesktop(context);
    return LayoutBuilder(
      builder: (context, c) {
        final cols = desktop ? 6 : 2;
        final gap = desktop ? 20.0 : 14.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: desktop ? 20 : 18,
          children: [for (var i = 0; i < count; i++) SizedBox(width: w, child: builder(context, i))],
        );
      },
    );
  }
}
