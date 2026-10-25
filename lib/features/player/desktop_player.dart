import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../desktop/player_bar.dart';
import '../desktop/window_controls.dart';
import 'lyrics_view.dart';

/// 桌面端“正在播放”：左侧封面，右侧滚动歌词。
class DesktopPlayerPage extends StatelessWidget {
  const DesktopPlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final song = player.current;
    final btnShadow = p.glassButtonShadow;
    return Material(
      type: MaterialType.transparency,
      child: GlowBackground.player(
        context,
        scale: 2.4,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 64,
              child: WindowDragArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      const WindowControls(),
                      const SizedBox(width: 16),
                      GlassButton(
                        YIcons.chevronDown,
                        size: 40,
                        iconSize: 20,
                        strokeWidth: 1.9,
                        shadows: btnShadow,
                        label: '收起播放页',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '正在播放',
                              style: ts(11, weight: w600, em: 0.14, color: p.playerText2),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              player.queueTitle ?? song?.albumName ?? '',
                              style: ts(14, weight: w600, color: p.text),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 108),
                      GlassButton(
                        YIcons.more,
                        size: 40,
                        iconSize: 20,
                        shadows: btnShadow,
                        label: '更多',
                        onTap: song == null ? null : () => showSongMenu(context, song),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (song != null)
              Positioned(
                left: 0,
                right: 0,
                top: 64,
                bottom: 112,
                child: Row(
                  children: [
                    Expanded(
                      flex: 44,
                      child: Center(
                        child: SizedBox(
                          width: 360,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LayoutBuilder(
                                builder: (context, c) {
                                  final size = c.maxWidth.clamp(200.0, 360.0);
                                  return Cover(
                                    song.coverUrl,
                                    size: size,
                                    radius: 34,
                                    imageSize: 900,
                                    shadows: [
                                      Shadow2(0, 32, 64, CoverArt.tint(song.coverUrl).withValues(alpha: 0.35)),
                                      const Shadow2(0, 4, 10, Color.fromRGBO(0, 0, 0, 0.08)),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 28),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          song.name,
                                          style: ts(28, weight: w700, em: -0.02, height: 1.15, color: p.text),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          song.subtitle,
                                          style: ts(17, color: p.playerText2),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Pressable(
                                    onTap: () => player.toggleLike(song),
                                    scale: 0.9,
                                    semanticLabel: player.isLiked(song) ? '取消喜欢' : '喜欢',
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(color: p.translucentButton, shape: BoxShape.circle),
                                      alignment: Alignment.center,
                                      child: YIcon(player.isLiked(song) ? YIcons.heart : YIcons.heartOutline, size: 22, color: p.accentText),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Expanded(flex: 56, child: LyricsView(desktop: true, anchor: 0.32, padding: EdgeInsets.fromLTRB(24, 120, 72, 220))),
                  ],
                ),
              ),
            const Positioned(left: 40, right: 40, bottom: 20, child: DesktopPlayerBar(onPlayerPage: true)),
          ],
        ),
      ),
    );
  }
}
