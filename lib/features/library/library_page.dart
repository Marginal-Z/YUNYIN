import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/downloads.dart';
import '../../data/models.dart';
import '../../data/sources/music_source.dart';
import '../../data/sources/source_manager.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../common/song_row.dart';
import '../shell/nav.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sources = context.watch<SourceManager>();
    final source = sources.current;
    return MobilePage(
      top: 30,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(child: PageTitle('乐库', subtitle: '我的音乐')),
            CircleButton(YIcons.sliders, label: '设置', onTap: () => go(context, SettingsRoute())),
            const SizedBox(width: 10),
            CircleButton(
              YIcons.plus,
              label: '新建歌单',
              color: p.accentText,
              strokeWidth: 2,
              onTap: () => Toast.show(context, '新建歌单请在${source.name}中完成', icon: YIcons.info),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ChipBar(labels: const ['歌单', '专辑', '歌手', '本地'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
        KeyedSubtree(
          key: ValueKey('${sources.generation}-$_tab'),
          child: switch (_tab) {
            0 => const LibraryOverview(),
            1 => const SubscribedAlbums(),
            2 => const FollowedArtists(),
            _ => const DownloadedList(),
          },
        ),
      ],
    );
  }
}

/// 未登录时的提示卡片。
class LoginPrompt extends StatelessWidget {
  const LoginPrompt({super.key, required this.source});

  final MusicSource source;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: YCard(
        child: StateView(
          icon: YIcons.user,
          tile: TileColor.red,
          title: '登录${source.name}',
          message: '登录后可同步你的歌单、喜欢的音乐与播放记录。',
          action: '去登录',
          primary: true,
          onAction: () => go(context, LoginRoute()),
        ),
      ),
    );
  }
}

class LibraryOverview extends StatelessWidget {
  const LibraryOverview({super.key});

  @override
  Widget build(BuildContext context) {
    final source = context.read<SourceManager>().current;
    final downloads = context.watch<DownloadManager>();
    final history = context.select<PlayerController, int>((p) => p.history.length);
    if (!source.loggedIn && source.supports(SourceFeature.login)) {
      return Column(children: [
        const SizedBox(height: 20),
        _QuickGrid(liked: null, recent: history, downloaded: downloads.items.length, subscribed: null),
        LoginPrompt(source: source),
      ]);
    }
    return AsyncView<List<PlaylistInfo>>(
      load: source.userPlaylists,
      loading: const Padding(padding: EdgeInsets.only(top: 20), child: SkeletonList()),
      builder: (context, lists, _) {
        final liked = lists.where((l) => l.isLikedList).firstOrNull;
        final created = lists.where((l) => l.ownedByMe && !l.isLikedList).toList();
        final subscribed = lists.where((l) => !l.ownedByMe && !l.isLikedList).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            _QuickGrid(
              liked: liked?.trackCount,
              recent: history,
              downloaded: downloads.items.length,
              subscribed: subscribed,
              likedList: liked,
            ),
            SectionHeader('我创建的歌单', action: '管理', onAction: () => go(context, MyCollectionsRoute())),
            if (created.isEmpty)
              YCard(child: StateView.empty(title: '还没有创建歌单', message: '在${source.name}里创建的歌单会显示在这里。', icon: YIcons.library))
            else
              CardList(
                indent: 78,
                children: [for (final pl in created) PlaylistRow(playlist: pl)],
              ),
          ],
        );
      },
    );
  }
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.liked, required this.recent, required this.downloaded, required this.subscribed, this.likedList});

  final int? liked;
  final int recent;
  final int downloaded;
  final int? subscribed;
  final PlaylistInfo? likedList;

  @override
  Widget build(BuildContext context) {
    Widget tile(YIconData icon, TileColor c, String title, String sub, VoidCallback onTap) => _QuickTile(icon: icon, color: c, title: title, subtitle: sub, onTap: onTap);
    return LayoutBuilder(builder: (context, cons) {
      final w = (cons.maxWidth - 12) / 2;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(
          width: w,
          child: tile(YIcons.heart, TileColor.red, '我喜欢的音乐', liked == null ? '—' : '$liked 首', () {
            likedList != null ? openPlaylist(context, likedList!) : go(context, CollectionRoute(PlaylistKind.liked));
          }),
        ),
        SizedBox(width: w, child: tile(YIcons.clock, TileColor.blue, '最近播放', '$recent 首', () => go(context, CollectionRoute(PlaylistKind.recent)))),
        SizedBox(width: w, child: tile(YIcons.download, TileColor.teal, '已下载', '$downloaded 首', () => go(context, CollectionRoute(PlaylistKind.downloaded)))),
        SizedBox(width: w, child: tile(YIcons.bookmark, TileColor.graphite, '收藏的歌单', subscribed == null ? '—' : '$subscribed 个', () => go(context, MyCollectionsRoute()))),
      ]);
    });
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  final YIconData icon;
  final TileColor color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      child: YCard(
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              IconTile(icon, color, size: 44, iconSize: 22, strokeWidth: 1.75),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: ts(14, weight: w600, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle, style: ts(12, color: p.text2)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 歌单行（封面 52，高 72）。
class PlaylistRow extends StatelessWidget {
  const PlaylistRow({super.key, required this.playlist, this.subtitle});

  final PlaylistInfo playlist;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pl = playlist;
    final sub = subtitle ?? ['${pl.trackCount} 首', if (pl.downloaded) '已下载', if (!pl.ownedByMe && pl.creator != null) pl.creator!].join(' · ');
    return Pressable(
      onTap: () => openPlaylist(context, pl),
      scale: 1,
      hoverColor: p.separator.withValues(alpha: 0.06),
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Cover(pl.cover, size: 52, radius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pl.name, style: ts(15, weight: w600, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(sub, style: ts(13, color: p.text2), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class SubscribedAlbums extends StatelessWidget {
  const SubscribedAlbums({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final source = context.read<SourceManager>().current;
    if (!source.loggedIn && source.supports(SourceFeature.login)) return LoginPrompt(source: source);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: AsyncView<List<AlbumInfo>>(
        load: source.subscribedAlbums,
        builder: (context, albums, _) {
          if (albums.isEmpty) {
            return YCard(child: StateView.empty(title: '还没有收藏专辑', message: '在专辑页点收藏，就会出现在这里。', icon: YIcons.library));
          }
          return CardList(indent: 78, children: [
            for (final a in albums)
              Pressable(
                onTap: () => go(context, AlbumRoute(a.id, preview: a)),
                scale: 1,
                hoverColor: p.separator.withValues(alpha: 0.06),
                child: SizedBox(
                  height: 72,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Cover(a.cover, size: 52, radius: 12),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.name, style: ts(15, weight: w600, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(a.artist?.name ?? '', style: ts(13, color: p.text2), maxLines: 1),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class FollowedArtists extends StatelessWidget {
  const FollowedArtists({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final source = context.read<SourceManager>().current;
    if (!source.loggedIn && source.supports(SourceFeature.login)) return LoginPrompt(source: source);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: AsyncView<List<ArtistInfo>>(
        load: source.followedArtists,
        builder: (context, artists, _) {
          if (artists.isEmpty) {
            return YCard(child: StateView.empty(title: '还没有关注歌手', message: '在歌手页点关注，就会出现在这里。', icon: YIcons.user));
          }
          return CardList(indent: 78, children: [
            for (final a in artists)
              Pressable(
                onTap: () => go(context, ArtistRoute(a.id, name: a.name)),
                scale: 1,
                hoverColor: p.separator.withValues(alpha: 0.06),
                child: SizedBox(
                  height: 72,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Cover(a.avatar, size: 52, circle: true),
                      const SizedBox(width: 14),
                      Expanded(child: Text(a.name, style: ts(15, weight: w600, color: p.text))),
                      const YIcon(YIcons.chevronRight, size: 16, color: Color(0xFF8E8E93)),
                      const SizedBox(width: 6),
                    ]),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class DownloadedList extends StatelessWidget {
  const DownloadedList({super.key});

  @override
  Widget build(BuildContext context) {
    final dl = context.watch<DownloadManager>();
    final items = dl.items;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: items.isEmpty
          ? YCard(
              child: StateView.empty(
                title: '还没有下载的歌曲',
                message: '在歌单里点下载，没有网络也能听。',
                action: '去发现音乐',
                onAction: () => context.read<AppNav>().switchTab(1),
              ),
            )
          : CardList(indent: 70, children: [
              for (var i = 0; i < items.length; i++)
                SongRow(song: items[i], onTap: () => playAll(context, items, start: i, title: '已下载')),
            ]),
    );
  }
}
