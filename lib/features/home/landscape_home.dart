
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/app_background.dart';
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
import '../shell/nav.dart';
import 'home_page.dart';

/// 横屏极简首页（类似车机界面）：顶部日期问候与设置、个人中心入口，每日推荐卡片与三个快捷入口，一排推荐歌单。
/// 整页按设计尺寸排版后等比缩放到可用区域，任何屏幕上都正好一屏、不需要滚动。
/// 左侧导航与底部播放条由外壳提供（见 LandscapeNavRail、LandscapePlayerBar）。
class LandscapeHome extends StatelessWidget {
  const LandscapeHome({super.key, required this.load});

  final Future<HomeFeed> Function() load;

  /// 设计高度：内容按这个高度排版，再整体缩放到实际高度。
  static const designHeight = 330.0;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sources = context.watch<SourceManager>();
    final source = sources.current;
    final user = source.user;
    final mq = MediaQuery.of(context);
    return Stack(
      children: [
        const Positioned.fill(child: AppBackground()),
        Padding(
          padding: EdgeInsets.fromLTRB(4, mq.padding.top + 6, 16 + mq.padding.right, chromeClearance(context, Chrome.full) - 6),
          child: LayoutBuilder(
            builder: (context, c) {
              final scale = c.maxHeight / designHeight;
              final width = c.maxWidth / scale;
              return FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: designHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 40,
                        child: Row(
                          children: [
                            Text(
                              greeting(),
                              style: ts(22, weight: w700, em: -0.02, color: p.text),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              todayText(),
                              style: ts(12, weight: w600, color: p.text2),
                            ),
                            const Spacer(),
                            CircleButton(YIcons.sliders, size: 36, iconSize: 18, color: p.text2, label: '设置', onTap: () => go(context, SettingsRoute())),
                            const SizedBox(width: 10),
                            if (user?.avatar != null)
                              Pressable(onTap: () => go(context, ProfileRoute()), semanticLabel: '个人中心', child: Cover(user!.avatar, size: 36, circle: true))
                            else
                              CircleButton(YIcons.user, size: 36, iconSize: 18, color: p.text2, label: '个人中心', onTap: () => go(context, ProfileRoute())),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: AsyncView<HomeFeed>(
                          keyValue: sources.generation,
                          cacheKey: DataCache.homeKey(source.id),
                          load: load,
                          loading: const SizedBox.shrink(),
                          builder: (context, feed, _) => _Body(feed: feed),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
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
    final p = Palette.of(context);
    final source = context.read<SourceManager>().current;
    final daily = dailyPlaylist(source, feed.daily);
    // 有歌单推荐的平台显示推荐歌单；洛雪曲库没有歌单，改为热门歌曲。
    final playlists = feed.playlists;
    final shelf = playlists.isNotEmpty
        ? [for (final pl in playlists) (pl.cover, pl.name, () => openPlaylist(context, pl))]
        : [
            for (var i = 0; i < feed.daily.length; i++)
              (feed.daily[i].coverUrl, feed.daily[i].name, () => playAll(context, feed.daily, start: i, title: '热门歌曲')),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 118,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 9,
                child: _FeatureCard(
                  songs: feed.daily,
                  onOpen: () => openPlaylist(context, daily),
                  onPlay: () => playAll(context, feed.daily, title: '每日推荐'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _QuickTile(icon: YIcons.heart, label: '我喜欢', onTap: () => go(context, CollectionRoute(PlaylistKind.liked))),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _QuickTile(icon: YIcons.clock, label: '最近播放', onTap: () => go(context, CollectionRoute(PlaylistKind.recent))),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _QuickTile(icon: YIcons.download, label: '本地音乐', onTap: () => go(context, CollectionRoute(PlaylistKind.local))),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              playlists.isNotEmpty ? '推荐歌单' : '热门歌曲',
              style: ts(15, weight: w700, color: p.text),
            ),
            const Spacer(),
            if (playlists.isNotEmpty)
              Pressable(
                onTap: () => context.read<AppNav>().switchTab(1),
                child: Text(
                  '全部',
                  style: ts(13, weight: w600, color: p.accentText),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _Shelf(items: shelf)),
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
    // 卡片本身与播放按钮分开处理点按：外层不能再套一层点按，否则会抢走播放按钮的点按（变成打开歌单）。
    return YBox(
      clip: true,
      radius: BorderRadius.circular(24),
      color: p.skeleton,
      shadows: const [Shadow2(0, 12, 28, Color.fromRGBO(0, 0, 0, 0.18))],
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (covers.isNotEmpty)
            BlurredImage(url: covers.first, sigma: 26, imageSize: (120 * dpr).round()),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xA6000000), Color(0x40000000)], begin: Alignment.centerLeft, end: Alignment.centerRight),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Pressable(
                    onTap: onOpen,
                    scale: 0.99,
                    semanticLabel: '打开每日推荐',
                    child: Row(
                      children: [
                        if (covers.isNotEmpty) ...[Cover(covers.first, size: 84, radius: 16, imageSize: (168 * dpr).round()), const SizedBox(width: 16)],
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DAILY MIX',
                                style: ts(11, weight: w700, em: 0.1, color: const Color(0xCCFFFFFF)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '每日推荐',
                                style: ts(24, weight: w700, em: -0.02, color: Colors.white),
                              ),
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
                      ],
                    ),
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
            Text(
              label,
              style: ts(15, weight: w600, color: p.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 一排封面卡片：每屏 6 张，可以横向滑动查看更多；卡片高度跟随可用高度。
class _Shelf extends StatelessWidget {
  const _Shelf({required this.items});

  final List<(String?, String, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final width = (c.maxWidth - gap * 5) / 6;
        final cover = c.maxHeight - 22;
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: gap),
          itemBuilder: (context, i) {
            final (url, title, onTap) = items[i];
            return Pressable(
              onTap: onTap,
              scale: 0.97,
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    YBox(
                      clip: true,
                      width: width,
                      height: cover,
                      radius: BorderRadius.circular(14),
                      shadows: p.coverShadow,
                      child: CoverImage(url, imageSize: (width * MediaQuery.devicePixelRatioOf(context) * 1.5).round()),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      style: ts(12, weight: w600, color: p.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
