import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../player/player_page.dart';
import 'nav.dart';
import 'tab_bar.dart';
import '../common/song_cover.dart';

/// 横屏极简布局的左侧竖向导航：首页、发现、乐库与搜索。
class LandscapeNavRail extends StatelessWidget {
  const LandscapeNavRail({super.key});

  static const _items = [TabBarItem(YIcons.home, '首页'), TabBarItem(YIcons.discover, '发现'), TabBarItem(YIcons.library, '乐库')];

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    final searching = nav.top is SearchRoute || nav.top is SearchResultRoute;
    return Semantics(
      label: '主导航',
      container: true,
      child: Glass(
        radius: kLandscapeRailWidth / 2,
        width: kLandscapeRailWidth,
        legible: true,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _items.length; i++) _RailItem(item: _items[i], selected: !searching && nav.tab == i, onTap: () => nav.switchTab(i)),
            _RailItem(item: const TabBarItem(YIcons.search, '搜索'), selected: searching, onTap: () => searching ? null : nav.push(SearchRoute())),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.item, required this.selected, required this.onTap});

  final TabBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = selected ? p.accentText : p.text;
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      semanticLabel: item.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 62,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: selected ? p.accentText.withValues(alpha: p.isDark ? 0.22 : 0.12) : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YIcon(item.icon, size: 22, strokeWidth: 2.2, color: color),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: ts(11, weight: w600, color: color, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 横屏极简布局的底部播放控制条：封面与歌名、喜欢、进度、切歌、循环模式与播放队列。
class LandscapePlayerBar extends StatelessWidget {
  const LandscapePlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final song = player.current;
    final liked = song != null && player.isLiked(song);
    final one = player.mode == PlayMode.repeatOne;
    final shuffle = player.mode == PlayMode.shuffle;
    final style = context.select<AppSettings, ProgressStyle>((s) => s.progressStyle);
    return Glass(
      radius: kLandscapeBarHeight / 2,
      height: kLandscapeBarHeight,
      legible: true,
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      child: Row(
        children: [
          Flexible(
            flex: 5,
            child: Pressable(
              onTap: song == null ? null : () => openPlayer(context),
              scale: 1,
              child: Row(
                children: [
                  SongCover(song, size: 48, radius: 12),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song?.name ?? '',
                          style: ts(14, weight: w600, color: p.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song?.artistText ?? '',
                          style: ts(12, color: p.text2),
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
          YIconButton(
            liked ? YIcons.heart : YIcons.heartOutline,
            size: 36,
            iconSize: 20,
            color: liked ? p.accentText : p.text2,
            label: liked ? '取消喜欢' : '喜欢',
            onTap: song == null ? null : () => player.toggleLike(song),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 6,
            child: ValueListenableBuilder<Duration>(
              valueListenable: player.position,
              builder: (context, pos, _) {
                final total = player.duration;
                final f = total.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / total.inMilliseconds;
                return Row(
                  children: [
                    Expanded(
                      child: SeekBar(value: f, onSeek: player.seekFraction, style: style, playing: player.playing, seed: song?.key.hashCode ?? 0),
                    ),
                    const SizedBox(width: 10),
                    Text('${formatDuration(pos)} / ${formatDuration(total)}', style: ts(11, color: p.text2, tabular: true)),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          YIconButton(YIcons.prev, size: 36, iconSize: 22, label: '上一首', onTap: player.previous),
          const PlayButton(size: 42, iconSize: 19),
          YIconButton(YIcons.next, size: 36, iconSize: 22, label: '下一首', onTap: player.next),
          YIconButton(
            shuffle ? YIcons.shuffle : (one ? YIcons.repeatOne : YIcons.repeat),
            size: 36,
            iconSize: 19,
            color: p.accentText,
            label: '播放模式',
            onTap: player.cycleMode,
          ),
          YIconButton(YIcons.queue, size: 36, iconSize: 20, color: p.text2, label: '播放队列', onTap: () => openQueue(context)),
        ],
      ),
    );
  }
}
