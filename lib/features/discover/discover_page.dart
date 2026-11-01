import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
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

  /// 手动刷新的次数：变化时各分区丢弃缓存重新加载。
  int _refresh = 0;

  void _reload(String sourceId) {
    // 发现页各分区的缓存键都以平台 ID 开头。
    DataCache.drop('discover:$sourceId:');
    setState(() => _refresh++);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = LayoutScope.isDesktop(context);
    final sources = context.watch<SourceManager>();
    final source = sources.current;
    // 只显示当前平台支持的分区（例如 QQ 音乐与酷狗没有电台）；_tab 是“推荐 / 排行榜 / 电台 / 新碟 / 歌单”的固定编号。
    final tabs = [
      (0, '推荐'),
      if (source.supports(SourceFeature.playlistCategories)) (4, '歌单'),
      if (source.supports(SourceFeature.charts)) (1, '排行榜'),
      if (source.supports(SourceFeature.radio)) (2, '电台'),
      if (source.supports(SourceFeature.newAlbums)) (3, '新碟'),
    ];
    final current = tabs.any((t) => t.$1 == _tab) ? _tab : 0;
    return AdaptivePage(
      mobileTop: 30,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: PageTitle('发现', subtitle: [for (final t in tabs.skip(1)) t.$2].join(' · '), size: desktop ? 40 : 36),
            ),
            CircleButton(YIcons.refresh, size: 38, iconSize: 18, color: Palette.of(context).text2, label: '刷新', onTap: () => _reload(source.id)),
          ],
        ),
        const SizedBox(height: 18),
        ChipBar(labels: [for (final t in tabs) t.$2], index: tabs.indexWhere((t) => t.$1 == current), onChanged: (i) => setState(() => _tab = tabs[i].$1)),
        EntranceFade(
          key: ValueKey('${sources.generation}-$current-$_refresh'),
          child: switch (current) {
            0 => const _Recommend(),
            1 => const _Charts(),
            2 => const _Radios(),
            4 => const PlaylistPlaza(),
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
        if (source.supports(SourceFeature.newAlbums))
          AsyncView<List<AlbumInfo>>(
            cacheKey: 'discover:${source.id}:newAlbums:6',
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
          cacheKey: 'discover:${source.id}:soaring',
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
        if (desktop && source.supports(SourceFeature.playlistCategories))
          AsyncView<List<PlaylistInfo>>(
            cacheKey: 'discover:${source.id}:recommend:12',
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
    final source = context.read<SourceManager>().current;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AsyncView<List<ChartInfo>>(
        cacheKey: 'discover:${source.id}:charts',
        load: source.charts,
        builder: (context, charts, _) {
          // 按平台的榜单分组排列（巅峰榜、地区榜、全球榜……），保持平台给出的顺序。
          final groups = <String, List<ChartInfo>>{};
          for (final c in charts) {
            groups.putIfAbsent(c.group ?? '榜单', () => []).add(c);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final g in groups.entries) ...[
                SectionHeader(g.key, top: 20),
                CardList(
                  indent: 78,
                  children: [for (final c in g.value) _ChartRow(chart: c, sourceId: source.id)],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.chart, required this.sourceId});

  final ChartInfo chart;
  final String sourceId;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = chart;
    return Pressable(
      onTap: () => go(context, PlaylistRoute(c.id, sourceId: sourceId)),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
            if (c.update != null && c.preview.isNotEmpty) ...[const SizedBox(width: 8), Text(c.update!, style: ts(12, color: p.text2))],
          ],
        ),
      ),
    );
  }
}

/// 歌单广场：平台的歌单分类与该分类下的歌单，分页加载。
class PlaylistPlaza extends StatefulWidget {
  const PlaylistPlaza({super.key});

  @override
  State<PlaylistPlaza> createState() => _PlaylistPlazaState();
}

class _PlaylistPlazaState extends State<PlaylistPlaza> {
  static const _page = 30;

  PlaylistCategory? _cat;
  bool _expanded = false;
  List<PlaylistInfo> _items = [];
  bool _loading = false;
  bool _done = false;
  Object? _error;
  int _request = 0;

  MusicSource get _source => context.read<SourceManager>().current;
  String _key(PlaylistCategory c) => 'discover:${_source.id}:plaza:${c.id}';

  void _select(PlaylistCategory c) {
    if (_cat?.id == c.id) return;
    _request++;
    final cached = DataCache.lookup(_key(c))?.$1;
    setState(() {
      _cat = c;
      _loading = false;
      _expanded = false;
      _items = cached is List<PlaylistInfo> ? cached : [];
      _done = false;
      _error = null;
    });
    if (_items.isEmpty) _more();
  }

  Future<void> _more() async {
    final c = _cat;
    if (c == null || _loading || _done) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _source.categoryPlaylists(c.id, offset: _items.length, limit: _page);
      if (!mounted || request != _request || _cat?.id != c.id) return;
      final seen = {for (final p in _items) p.id};
      setState(() {
        _items = [..._items, ...list.where((p) => seen.add(p.id))];
        _done = list.length < _page ~/ 2;
        _loading = false;
      });
      DataCache.put(_key(c), _items);
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final source = _source;
    return AsyncView<List<PlaylistCategory>>(
      cacheKey: 'discover:${source.id}:categories',
      maxAge: const Duration(hours: 6),
      load: source.playlistCategories,
      builder: (context, cats, _) {
        if (cats.isEmpty) return const SizedBox.shrink();
        if (_cat == null || !cats.any((c) => c.id == _cat!.id)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _cat == null) _select(cats.first);
          });
        }
        final current = _cat ?? cats.first;
        // 常用分类：推荐 / 全部，加上每个分组的前几个。
        final quick = <PlaylistCategory>[cats.first];
        final groups = <String, List<PlaylistCategory>>{};
        for (final c in cats.skip(1)) {
          groups.putIfAbsent(c.group ?? '分类', () => []).add(c);
        }
        for (final g in groups.values) {
          quick.addAll(g.take(groups.length > 2 ? 2 : 12));
        }
        if (!quick.any((c) => c.id == current.id)) quick.insert(1, current);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  // 横向滚动的分类不能盖住右侧的“全部分类”：只裁掉右侧，标签的阴影在其他方向保持完整。
                  child: ClipRect(
                    clipper: const _RightEdgeClip(),
                    child: ChipBar(
                      labels: [for (final c in quick) c.name],
                      index: quick.indexWhere((c) => c.id == current.id),
                      onChanged: (i) => _select(quick[i]),
                      scroll: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (cats.length > quick.length)
                  Pressable(
                    onTap: () => setState(() => _expanded = !_expanded),
                    semanticLabel: '全部分类',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '全部分类',
                          style: ts(14, weight: w600, color: p.accentText),
                        ),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 220),
                          child: YIcon(YIcons.chevronDown, size: 16, color: p.accentText),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_expanded
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: YCard(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final g in groups.entries) ...[
                                Padding(
                                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                                  child: Text(
                                    g.key,
                                    style: ts(13, weight: w600, color: p.text2),
                                  ),
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [for (final c in g.value) YChip(c.name, height: 32, selected: c.id == current.id, onTap: () => _select(c))],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            if (_items.isNotEmpty) PlaylistGrid(items: _items),
            if (_items.isEmpty && _loading) const SkeletonList(),
            if (_error != null)
              StateView.network(onRetry: _more, message: errorText(_error))
            else if (_items.isNotEmpty && !_done)
              Padding(
                padding: const EdgeInsets.only(top: 22),
                child: Center(
                  child: SecondaryButton(label: _loading ? '加载中…' : '加载更多', height: 44, onTap: _loading ? null : _more),
                ),
              ),
          ],
        );
      },
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
        cacheKey: 'discover:${source.id}:hotRadios',
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
        cacheKey: 'discover:${source.id}:newAlbums:24',
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

/// 只在右边缘裁剪，上下左三个方向留出阴影的空间。
class _RightEdgeClip extends CustomClipper<Rect> {
  const _RightEdgeClip();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-24, -24, size.width, size.height + 24);

  @override
  bool shouldReclip(_RightEdgeClip old) => false;
}
