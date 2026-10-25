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
import '../artist/artist_page.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../common/song_row.dart';
import '../discover/discover_page.dart';
import '../library/library_page.dart';
import '../shell/nav.dart';
import 'search_page.dart';

const _tabs = ['综合', '歌曲', '歌手', '专辑', '歌单'];

class SearchResultPage extends StatefulWidget {
  const SearchResultPage({super.key, required this.route});

  final SearchResultRoute route;

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  late final _c = TextEditingController(text: widget.route.keyword);
  late int _tab = widget.route.type.index;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = LayoutScope.isDesktop(context);
    final sources = context.watch<SourceManager>();
    final k = widget.route.keyword;
    final type = SearchType.values[_tab];
    final body = AsyncView<SearchResult>(
      key: ValueKey('$k-$_tab-${sources.generation}'),
      load: () => sources.current.search(k, type: type, limit: type == SearchType.all ? 20 : 50),
      builder: (context, r, _) => switch (type) {
        SearchType.all => desktop ? _DesktopAll(result: r, keyword: k, onMore: () => setState(() => _tab = 1)) : _MobileAll(result: r, keyword: k, onMore: () => setState(() => _tab = 1)),
        SearchType.song => _Songs(songs: r.songs, keyword: k),
        SearchType.artist => r.artists.isEmpty ? _empty(k) : ArtistStrip(artists: r.artists, wrap: true),
        SearchType.album => r.albums.isEmpty ? _empty(k) : AlbumGrid(items: r.albums),
        SearchType.playlist => r.playlists.isEmpty ? _empty(k) : CardList(indent: 78, children: [for (final pl in r.playlists) PlaylistRow(playlist: pl, subtitle: playlistSubtitle(pl))]),
      },
    );
    return AdaptivePage(
      chrome: Chrome.miniOnly,
      mobileTop: 22,
      children: [
        if (!desktop)
          Row(children: [
            CircleButton(YIcons.back, size: 44, iconSize: 22, label: '返回', onTap: () => context.read<AppNav>().pop()),
            const SizedBox(width: 12),
            Expanded(
              child: SearchField(
                controller: _c,
                onSubmit: (q) => submitSearch(context, q),
                onClear: () => _c.clear(),
              ),
            ),
          ]),
        SizedBox(height: desktop ? 0 : 16),
        ChipBar(labels: _tabs, index: _tab, scroll: !desktop, onChanged: (i) => setState(() => _tab = i)),
        SizedBox(height: desktop ? 22 : 18),
        body,
      ],
    );
  }

  Widget _empty(String k) => YCard(child: StateView.empty(title: '没有找到“$k”', message: '换个关键词试试吧。', icon: YIcons.search));
}

class _MobileAll extends StatelessWidget {
  const _MobileAll({required this.result, required this.keyword, required this.onMore});

  final SearchResult result;
  final String keyword;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final best = result.bestSong;
    final songs = result.songs.take(4).toList();
    if (best == null && result.artists.isEmpty) {
      return YCard(child: StateView.empty(title: '没有找到“$keyword”', message: '换个关键词试试吧。', icon: YIcons.search));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (best != null)
        Pressable(
          onTap: () => playAll(context, result.songs, start: result.songs.indexOf(best), title: '搜索“$keyword”'),
          child: YCard(
            child: SizedBox(
              height: 96,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Cover(best.coverUrl, size: 64, radius: 16, shadows: [Shadow2(0, 8, 18, CoverArt.tint(best.coverUrl).withValues(alpha: 0.30))]),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Tag('最佳匹配'),
                      const SizedBox(height: 6),
                      highlightText(best.name, keyword, ts(20, weight: w700, em: -0.01, color: p.text), p.accentText),
                      const SizedBox(height: 2),
                      Text(best.subtitle, style: ts(13, color: p.text2), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  const SizedBox(width: 14),
                  _RedPlay(size: 44, iconSize: 20, onTap: () => playAll(context, result.songs, start: result.songs.indexOf(best), title: '搜索“$keyword”')),
                ]),
              ),
            ),
          ),
        ),
      if (songs.isNotEmpty) ...[
        SectionHeader('歌曲', top: 24, action: '更多', onAction: onMore),
        CardList(indent: 70, children: [
          for (var i = 0; i < songs.length; i++)
            SongRow(song: songs[i], keyword: keyword, subtitle: songs[i].subtitle, onTap: () => playAll(context, result.songs, start: i, title: '搜索“$keyword”')),
        ]),
      ],
      if (result.artists.isNotEmpty) ...[
        const SectionHeader('相关歌手', top: 24),
        ArtistStrip(artists: result.artists.take(4).toList()),
      ],
    ]);
  }
}

class _RedPlay extends StatelessWidget {
  const _RedPlay({required this.size, required this.iconSize, this.onTap});

  final double size;
  final double iconSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      semanticLabel: '播放',
      child: YBox(
        width: size,
        height: size,
        radius: BorderRadius.circular(size / 2),
        gradient: CssGradient.vertical(p.buttonGradient),
        shadows: p.buttonShadow,
        insets: [Shadow2(0, 1, 0, p.buttonInsetHighlight)],
        alignment: Alignment.center,
        child: YIcon(YIcons.play, size: iconSize, color: Colors.white),
      ),
    );
  }
}

class _DesktopAll extends StatelessWidget {
  const _DesktopAll({required this.result, required this.keyword, required this.onMore});

  final SearchResult result;
  final String keyword;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final best = result.bestSong;
    final pl = result.bestPlaylist;
    final songs = result.songs.take(6).toList();
    if (best == null && pl == null) {
      return YCard(child: StateView.empty(title: '没有找到“$keyword”', message: '换个关键词试试吧。', icon: YIcons.search));
    }
    Widget heading(String t) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(t, style: ts(22, weight: w700, em: -0.015, color: p.text)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            heading('最佳匹配'),
            if (best != null)
              Pressable(
                onTap: () => playAll(context, result.songs, start: result.songs.indexOf(best), title: '搜索“$keyword”'),
                child: YCard(
                  child: SizedBox(
                    height: 150,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(children: [
                        Cover(best.coverUrl, size: 106, radius: 18, shadows: [Shadow2(0, 6, 18, CoverArt.tint(best.coverUrl).withValues(alpha: 0.3))]),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('歌曲', style: ts(12, weight: w600, color: p.text2)),
                            const SizedBox(height: 4),
                            Text(best.name, style: ts(26, weight: w700, em: -0.02, height: 1.15, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(best.subtitle, style: ts(14, color: p.text2), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        const SizedBox(width: 20),
                        _RedPlay(size: 46, iconSize: 20, onTap: () => playAll(context, result.songs, start: result.songs.indexOf(best), title: '搜索“$keyword”')),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            heading('相关歌单'),
            if (pl != null)
              Pressable(
                onTap: () => openPlaylist(context, pl),
                child: YBox(
                  height: 150,
                  radius: BorderRadius.circular(26),
                  gradient: CssGradient(150, colors: p.dailyGradient),
                  shadows: const [Shadow2(0, 16, 34, Color.fromRGBO(255, 106, 87, 0.22))],
                  insets: [Shadow2(0, 1, 0, p.highlightInset)],
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(children: [
                    Cover(pl.cover, size: 106, radius: 18),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('歌单', style: ts(12, weight: w600, color: p.dailyDesc)),
                        const SizedBox(height: 4),
                        Text(pl.name, style: ts(26, weight: w700, em: -0.02, height: 1.15, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('${pl.creator ?? ''} · ${pl.trackCount} 首', style: ts(14, color: p.dailyDesc), maxLines: 1),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
      if (songs.isNotEmpty) ...[
        SectionHeader('歌曲', top: 26, bottom: 10, action: '查看全部', onAction: onMore),
        CardList(indent: 66, children: [
          for (var i = 0; i < songs.length; i++)
            DesktopSongRow(song: songs[i], cover: true, keyword: keyword, highlightCurrent: false,
                onTap: () => playAll(context, result.songs, start: i, title: '搜索“$keyword”')),
        ]),
      ],
      if (result.albums.isNotEmpty) ...[
        const SectionHeader('专辑', top: 26, action: '查看全部'),
        AlbumGrid(items: result.albums.take(6).toList()),
      ],
    ]);
  }
}

class _Songs extends StatelessWidget {
  const _Songs({required this.songs, required this.keyword});

  final List<Song> songs;
  final String keyword;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return YCard(child: StateView.empty(title: '没有找到“$keyword”', message: '换个关键词试试吧。', icon: YIcons.search));
    }
    final desktop = LayoutScope.isDesktop(context);
    final player = context.read<PlayerController>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CardList(indent: desktop ? 66 : 70, children: [
        for (var i = 0; i < songs.length; i++)
          desktop
              ? DesktopSongRow(song: songs[i], cover: true, keyword: keyword, onTap: () => playAll(context, songs, start: i, title: '搜索“$keyword”'))
              : SongRow(song: songs[i], keyword: keyword, subtitle: songs[i].subtitle, onTap: () => playAll(context, songs, start: i, title: '搜索“$keyword”')),
      ]),
      const SizedBox(height: 14),
      Center(
        child: SecondaryButton(label: '全部加入播放队列', icon: YIcons.plus, height: 40, fontSize: 14, iconSize: 18, onTap: () {
          player.addToQueue(songs);
          Toast.show(context, '已加入播放队列');
        }),
      ),
    ]);
  }
}
