import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../player/player_page.dart';
import '../common/song_cover.dart';

/// 桌面端底部播放条（高 76）：无边框、透明，没有底板、圆角与阴影，控件直接融入页面背景。
class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({super.key, this.onPlayerPage = false});

  /// 在“正在播放”页内：封面不可点，歌词按钮高亮并用于收起。
  final bool onPlayerPage;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final song = player.current;
    final shuffle = player.mode == PlayMode.shuffle;
    final one = player.mode == PlayMode.repeatOne;
    return Container(
      height: 76,
      padding: const EdgeInsets.fromLTRB(12, 0, 20, 0),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Pressable(
              onTap: onPlayerPage || song == null ? null : () => openPlayer(context),
              scale: 1,
              child: Row(
                children: [
                  SongCover(song, size: 52, circle: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song?.name ?? '云音',
                          style: ts(14, weight: w600, color: p.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song?.subtitle ?? '听见好音乐',
                          style: ts(12, color: p.text4),
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
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    YIconButton(
                      YIcons.shuffle,
                      size: 32,
                      iconSize: 20,
                      color: shuffle ? p.accentText : p.text4,
                      label: '随机播放',
                      onTap: () => player.setMode(shuffle ? PlayMode.sequence : PlayMode.shuffle),
                    ),
                    const SizedBox(width: 22),
                    YIconButton(YIcons.prev, size: 32, iconSize: 22, label: '上一首', onTap: player.previous),
                    const SizedBox(width: 22),
                    const PlayButton(size: 40, iconSize: 20),
                    const SizedBox(width: 22),
                    YIconButton(YIcons.next, size: 32, iconSize: 22, label: '下一首', onTap: player.next),
                    const SizedBox(width: 22),
                    YIconButton(
                      one ? YIcons.repeatOne : YIcons.repeat,
                      size: 32,
                      iconSize: 20,
                      color: one ? p.accentText : p.text4,
                      label: '循环播放',
                      onTap: () => player.setMode(one ? PlayMode.sequence : PlayMode.repeatOne),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: player.position,
                    builder: (context, pos, _) {
                      final total = player.duration;
                      final f = total.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / total.inMilliseconds;
                      return Row(
                        children: [
                          Text(formatDuration(pos), style: ts(12, color: p.text4, tabular: true)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SeekBar(
                              value: f,
                              thumb: false,
                              onSeek: player.seekFraction,
                              style: context.select<AppSettings, ProgressStyle>((s) => s.progressStyle),
                              playing: player.playing,
                              seed: player.current?.key.hashCode ?? 0,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(formatDuration(total), style: ts(12, color: p.text4, tabular: true)),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 250,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                YIconButton(
                  YIcons.lyrics,
                  size: 36,
                  iconSize: 20,
                  color: onPlayerPage ? p.accentText : p.text3,
                  label: '歌词',
                  onTap: () {
                    onPlayerPage ? Navigator.of(context).maybePop() : openPlayer(context);
                  },
                ),
                const SizedBox(width: 6),
                YIconButton(YIcons.queue, size: 36, iconSize: 20, color: p.text3, label: '播放队列', onTap: () => openQueue(context)),
                const SizedBox(width: 12),
                YIconButton(
                  player.volume == 0 ? YIcons.volumeMute : YIcons.volume,
                  size: 28,
                  iconSize: 20,
                  color: p.text3,
                  label: '静音',
                  onTap: () => player.setVolume(player.volume == 0 ? 0.65 : 0),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 84,
                  child: SeekBar(value: player.volume, thumb: false, onSeek: player.setVolume),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 透明播放条后面的页面渐隐：页面内容滚到播放条下方时逐渐融入页面底色，播放控件始终清晰，又不需要底板。
class PlayerBarFade extends StatelessWidget {
  const PlayerBarFade({super.key});

  @override
  Widget build(BuildContext context) {
    final bg = Palette.of(context).bg;
    final image = context.select<AppSettings, bool>((s) => s.background != BackgroundMode.glow && s.uiStyle == UiStyle.glass);
    if (image) {
      // 自定义图片与封面取色背景：不用不透明的底色盖住背景，改为由上到下逐渐加强的模糊（分三段）加一层淡淡的底色，
      // 背景图片在播放控件后面依然可见，列表文字被模糊掉，不会和控件叠在一起。
      Widget blur(double top, double sigma) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        top: top,
        child: ClipRect(
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp), child: const SizedBox.expand()),
        ),
      );
      return IgnorePointer(
        child: LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight;
            return Stack(
              children: [
                blur(h * 0.3, 3),
                blur(h * 0.45, 8),
                blur(h * 0.6, 18),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.45), bg.withValues(alpha: 0.6)],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // 播放控件所在的下方 60% 几乎不透明，上方 40% 渐隐：控件后面不会透出列表文字。
            colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.97), bg],
            stops: const [0, 0.4, 1],
          ),
        ),
      ),
    );
  }
}
