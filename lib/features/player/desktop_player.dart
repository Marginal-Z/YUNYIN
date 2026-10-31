import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../desktop/player_bar.dart';
import '../desktop/window_controls.dart';
import 'artwork.dart';
import 'lyrics_view.dart';

/// 桌面端“正在播放”：左侧封面，右侧滚动歌词。
class DesktopPlayerPage extends StatelessWidget {
  const DesktopPlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final song = player.current;
    final style = context.select<AppSettings, PlayerStyle>((s) => s.playerStyle);
    return Material(
      type: MaterialType.transparency,
      child: GlowBackground.player(
        context,
        scale: 2.4,
        flow: player.playing,
        child: Stack(
          children: [
            if (style == PlayerStyle.immersive && song != null)
              Positioned.fill(
                child: ImmersiveBackdrop(url: song.coverUrl, dark: p.isDark),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 64,
              child: WindowDragArea(
                child: Padding(
                  // Windows 右上角留出标题栏按钮的位置。
                  padding: EdgeInsets.only(left: 24, right: useWindowsCaption ? 150 : 24),
                  child: Row(
                    children: [
                      const WindowControls(),
                      const SizedBox(width: 16),
                      YIconButton(
                        YIcons.chevronDown,
                        size: 40,
                        iconSize: 22,
                        strokeWidth: 1.9,
                        color: p.text,
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
                      YIconButton(
                        YIcons.more,
                        size: 40,
                        iconSize: 22,
                        color: p.text,
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
                                  // 沉浸样式在桌面端表现为封面铺满背景，封面本身使用大封面样式。
                                  return PlayerArtwork(song: song, size: size, style: style == PlayerStyle.immersive ? PlayerStyle.cover : style);
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
                    const Expanded(flex: 56, child: LyricsView(desktop: true, anchor: 0.32, padding: EdgeInsets.fromLTRB(24, 0, 72, 0))),
                  ],
                ),
              ),
            const Positioned(left: 40, right: 40, bottom: 20, child: DesktopPlayerBar(onPlayerPage: true)),
            if (useWindowsCaption) const Positioned(top: 0, right: 0, child: WindowsCaptionButtons()),
          ],
        ),
      ),
    );
  }
}
