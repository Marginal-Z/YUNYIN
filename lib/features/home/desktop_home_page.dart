import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/feedback.dart';
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
import 'home_page.dart';

/// 网易云“私人雷达”歌单。
const kRadarPlaylistId = '3136952023';

class DesktopHomePage extends StatelessWidget {
  const DesktopHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sources = context.watch<SourceManager>();
    final source = sources.current;
    return DesktopPage(
      top: 74,
      children: [
        Text(
          todayText(),
          style: ts(13, weight: w600, color: p.text2),
        ),
        const SizedBox(height: 2),
        Text(
          greeting(),
          style: ts(40, weight: w700, em: -0.02, height: 1.1, color: p.text),
        ),
        const SizedBox(height: 18),
        AsyncView<HomeFeed>(
          keyValue: sources.generation,
          cacheKey: DataCache.homeKey(source.id),
          load: () async {
            final feed = await source.homeFeed();
            DataCache.saveHome(source.id, source.user?.id, feed);
            return feed;
          },
          builder: (context, feed, _) {
            final player = context.watch<PlayerController>();
            final recent = player.history.take(4).toList();
            final daily = dailyPlaylist(source, feed.daily);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DailyCard(
                        height: 208,
                        desktop: true,
                        songs: feed.daily,
                        onOpen: () => openPlaylist(context, daily),
                        onPlay: () => playAll(context, feed.daily, title: '每日推荐'),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: RadarCard(
                        // 网易云“私人雷达”歌单需要登录；未登录时引导登录。
                        onTap: () => source.loggedIn ? go(context, PlaylistRoute(kRadarPlaylistId, sourceId: source.id)) : go(context, LoginRoute()),
                      ),
                    ),
                  ],
                ),
                SectionHeader('歌单精选', top: 26, action: '全部', onAction: () => go(context, DiscoverRoute())),
                PlaylistGrid(items: feed.playlists.take(6).toList()),
                SectionHeader('最近播放', top: 24, action: '更多', onAction: () => go(context, CollectionRoute(PlaylistKind.recent))),
                if (recent.isEmpty)
                  const EmptyRecent()
                else
                  CardList(
                    indent: 66,
                    children: [
                      for (var i = 0; i < recent.length; i++)
                        DesktopSongRow(
                          song: recent[i],
                          cover: true,
                          onTap: () => playAll(context, recent, start: i, title: '最近播放'),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
