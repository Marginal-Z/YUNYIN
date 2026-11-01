import 'dart:ui' as ui;

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
import '../../data/sources/source_manager.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../common/song_row.dart';
import '../shell/nav.dart';
import 'home_page.dart';

/// 横屏极简首页：顶部日期与问候、每日推荐卡片与三个快捷入口（我喜欢、最近播放、本地音乐）、横向滚动的推荐歌单。
/// 左侧导航与底部播放条由外壳提供（见 LandscapeNavRail、LandscapePlayerBar）。
class LandscapeHome extends StatelessWidget {
  const LandscapeHome({super.key, required this.load});

  final Future<HomeFeed> Function() load;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sources = context.watch<SourceManager>();
    final source = sources.current;
    final user = source.user;
    return MobilePage(
      top: 14,
      horizontal: 16,
      wide: true,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(todayText(), style: ts(12, weight: w600, color: p.text2)),
                  Text(greeting(), style: ts(26, weight: w700, em: -0.02, height: 1.15, color: p.text)),
                ],
              ),
            ),
            CircleButton(YIcons.sliders, size: 40, iconSize: 19, color: p.text2, label: '设置', onTap: () => go(context, SettingsRoute())),
            const SizedBox(width: 10),
            if (user?.avatar != null)
              Pressable(onTap: () => go(context, ProfileRoute()), semanticLabel: '个人中心', child: Cover(user!.avatar, size: 40, circle: true))
            else
              CircleButton(YIcons.user, size: 40, iconSize: 20, color: p.text2, label: '个人中心', onTap: () => go(context, ProfileRoute())),
          ],
        ),
        const SizedBox(height: 14),
        AsyncView<HomeFeed>(
          keyValue: sources.generation,
          cacheKey: DataCache.homeKey(source.id),
          load: load,
          loading: const SkeletonList(),
          builder: (context, feed, _) => _Body(feed: feed),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.feed});

  final HomeFeed feed;

  @override
  Widget build(BuildContext context) {
    final source = context.read<SourceManager>().current;
    final daily = dailyPlaylist(source, feed.daily);
    const cardHeight = 136.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: cardHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 9,
                child: _FeatureCard(songs: feed.daily, onOpen: () => openPlaylist(context, daily), onPlay: () => playAll(context, feed.daily, title: '每日推荐')),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: _QuickTile(icon: YIcons.heart, label: '我喜欢', onTap: () => go(context, CollectionRoute(PlaylistKind.liked)))),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: _QuickTile(icon: YIcons.clock, label: '最近播放', onTap: () => go(context, CollectionRoute(PlaylistKind.recent)))),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: _QuickTile(icon: YIcons.download, label: '本地音乐', onTap: () => go(context, CollectionRoute(PlaylistKind.local)))),
            ],
          ),
        ),
        // 有歌单推荐的平台显示推荐歌单；洛雪曲库没有歌单，改为热门歌曲。
        if (feed.playlists.isNotEmpty) ...[
          SectionHeader('推荐歌单', top: 20, action: '全部', onAction: () => context.read<AppNav>().switchTab(1)),
          _Shelf(
            count: feed.playlists.length,
            builder: (context, i, width) {
              final pl = feed.playlists[i];
              return PlaylistTile(width: width, cover: pl.cover, title: pl.name, subtitle: playlistSubtitle(pl), radius: 16, onTap: () => openPlaylist(context, pl));
            },
          ),
        ] else if (feed.daily.isNotEmpty) ...[
          const SectionHeader('热门歌曲', top: 20),
          _Shelf(
            count: feed.daily.length,
            builder: (context, i, width) {
              final s = feed.daily[i];
              return PlaylistTile(width: width, cover: s.coverUrl, title: s.name, subtitle: s.artistText, radius: 16, onTap: () => playAll(context, feed.daily, start: i, title: '热门歌曲'));
            },
          ),
        ],
      ],
    );
  }
}

/// 每日推荐卡片：模糊的封面底色、标题与播放按钮。
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.songs, required this.onOpen, required this.onPlay});

  final List<Song> songs;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final covers = [for (final s in songs) ?s.coverUrl];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Pressable(
      onTap: onOpen,
      scale: 0.99,
      child: YBox(
        clip: true,
        radius: BorderRadius.circular(24),
        color: p.skeleton,
        shadows: const [Shadow2(0, 12, 28, Color.fromRGBO(0, 0, 0, 0.18))],
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (covers.isNotEmpty)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26, tileMode: TileMode.clamp),
                child: Transform.scale(scale: 1.3, child: CoverImage(covers.first, imageSize: (120 * dpr).round())),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xA6000000), Color(0x40000000)], begin: Alignment.centerLeft, end: Alignment.centerRight),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
              child: Row(
                children: [
                  if (covers.isNotEmpty) ...[
                    Cover(covers.first, size: 92, radius: 16, imageSize: (184 * dpr).round()),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('DAILY MIX', style: ts(11, weight: w700, em: 0.1, color: const Color(0xCCFFFFFF))),
                        const SizedBox(height: 4),
                        Text('每日推荐', style: ts(24, weight: w700, em: -0.02, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(
                          songs.isEmpty ? '新歌与老朋友，每天更新' : songs.take(3).map((s) => s.name).join(' · '),
                          style: ts(13, color: const Color(0xD9FFFFFF)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Pressable(
                    onTap: onPlay,
                    semanticLabel: '播放全部',
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const YIcon(YIcons.play, size: 20, color: Color(0xFF1D1D1F)),
                    ),
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

/// 快捷入口卡片：图标与名称。
class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.label, required this.onTap});

  final YIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      semanticLabel: label,
      child: YCard(
        radius: 24,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            YIcon(icon, size: 30, strokeWidth: 2, color: p.accentText),
            const SizedBox(height: 10),
            Text(label, style: ts(15, weight: w600, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// 横向滚动的一排封面：按可用宽度每屏放 6 张。
class _Shelf extends StatelessWidget {
  const _Shelf({required this.count, required this.builder});

  final int count;
  final Widget Function(BuildContext context, int index, double width) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final width = ((c.maxWidth - gap * 5) / 6).clamp(96.0, 150.0);
        return SizedBox(
          height: width + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: gap),
            itemBuilder: (context, i) => builder(context, i, width),
          ),
        );
      },
    );
  }
}
