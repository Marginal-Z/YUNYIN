import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import 'lyrics_view.dart';
import 'player_page.dart';

/// 移动端全屏歌词。
class LyricsPage extends StatelessWidget {
  const LyricsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final settings = context.watch<AppSettings>();
    final song = player.current;
    final pad = MediaQuery.paddingOf(context);
    if (song == null) return GlowBackground.player(context);
    final liked = player.isLiked(song);
    return GlowBackground.player(
      context,
      child: Stack(
        children: [
          Positioned(left: 28, right: 28, top: pad.top + 188, bottom: 22 + 150 + 10 + pad.bottom, child: const LyricsView(desktop: false, anchor: 0.22)),
          Positioned(
            left: 16,
            top: pad.top + 20,
            child: GlassButton(YIcons.chevronDown, label: '收起歌词', onTap: () => Navigator.of(context).maybePop()),
          ),
          Positioned(
            left: 76,
            right: 76,
            top: pad.top + 20,
            height: 44,
            child: Center(
              child: Text(
                '歌词',
                style: ts(11, weight: w700, em: 0.14, color: p.playerText2),
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: pad.top + 20,
            child: GlassButton(
              YIcons.more,
              label: '歌词选项',
              onTap: () async {
                final v = await showOptions<int>(context, title: '歌词选项', options: [(0, settings.showTranslation ? '隐藏翻译' : '显示翻译'), (1, '查看评论'), (2, '歌曲操作')]);
                if (!context.mounted) return;
                if (v == 0) settings.setFlag('showTranslation', !settings.showTranslation);
                if (v == 1) openComments(context, song);
                if (v == 2) showSongMenu(context, song);
              },
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: pad.top + 84,
            child: YBox(
              height: 72,
              radius: BorderRadius.circular(24),
              color: p.lyricsCard,
              shadows: p.cardShadow,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Cover(song.coverUrl, size: 48, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.name,
                          style: ts(16, weight: w700, color: p.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.subtitle,
                          style: ts(13, color: p.playerText2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Pressable(
                    onTap: () => player.toggleLike(song),
                    scale: 0.9,
                    semanticLabel: liked ? '取消喜欢' : '喜欢',
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: p.isDark ? p.translucentButton : Colors.white, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: YIcon(liked ? YIcons.heart : YIcons.heartOutline, size: 20, color: p.accentText),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 22 + pad.bottom,
            child: Glass(
              radius: 34,
              height: 150,
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
              child: Column(
                children: [
                  ValueListenableBuilder<Duration>(
                    valueListenable: player.position,
                    builder: (context, pos, _) {
                      final total = player.duration;
                      final f = total.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / total.inMilliseconds;
                      final remain = total - pos;
                      return Column(
                        children: [
                          SeekBar(value: f, onSeek: player.seekFraction),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                formatDuration(pos),
                                style: ts(12, weight: w500, color: p.playerText2, tabular: true),
                              ),
                              const Spacer(),
                              Text(
                                '-${formatDuration(remain.isNegative ? Duration.zero : remain)}',
                                style: ts(12, weight: w500, color: p.playerText2, tabular: true),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Pressable(
                        onTap: () => settings.setFlag('showTranslation', !settings.showTranslation),
                        scale: 0.9,
                        semanticLabel: '歌词翻译',
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Text(
                              '译',
                              style: ts(15, weight: w700, color: settings.showTranslation ? p.accentText : p.playerText2),
                            ),
                          ),
                        ),
                      ),
                      YIconButton(YIcons.prev, size: 52, iconSize: 30, label: '上一首', onTap: player.previous),
                      const PlayButton(size: 64, iconSize: 28, shadow: true, largePause: false),
                      YIconButton(YIcons.next, size: 52, iconSize: 30, label: '下一首', onTap: player.next),
                      YIconButton(YIcons.queue, size: 44, iconSize: 24, color: p.playerText2, label: '播放队列', onTap: () => openQueue(context)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
