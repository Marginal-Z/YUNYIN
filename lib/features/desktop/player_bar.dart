import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/box.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../player/player_page.dart';

/// 桌面端底部玻璃播放条（高 76，圆角 38）。
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
    return Glass(
      radius: 38,
      height: 76,
      padding: const EdgeInsets.fromLTRB(12, 0, 20, 0),
      shadows: onPlayerPage ? const [Shadow2(0, 10, 30, Color.fromRGBO(0, 0, 0, 0.12)), Shadow2(0, 1, 3, Color.fromRGBO(0, 0, 0, 0.08))] : null,
      child: Row(children: [
        SizedBox(
          width: 260,
          child: Pressable(
            onTap: onPlayerPage || song == null ? null : () => openPlayer(context),
            scale: 1,
            child: Row(children: [
              Cover(song?.coverUrl, size: 52, circle: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(song?.name ?? '云音', style: ts(14, weight: w600, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(song?.subtitle ?? '听见好音乐', style: ts(12, color: p.text4), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              YIconButton(YIcons.shuffle, size: 32, iconSize: 20, color: shuffle ? p.accentText : p.text4, label: '随机播放',
                  onTap: () => player.setMode(shuffle ? PlayMode.sequence : PlayMode.shuffle)),
              const SizedBox(width: 22),
              YIconButton(YIcons.prev, size: 32, iconSize: 22, label: '上一首', onTap: player.previous),
              const SizedBox(width: 22),
              const PlayButton(size: 40, iconSize: 20),
              const SizedBox(width: 22),
              YIconButton(YIcons.next, size: 32, iconSize: 22, label: '下一首', onTap: player.next),
              const SizedBox(width: 22),
              YIconButton(one ? YIcons.repeatOne : YIcons.repeat, size: 32, iconSize: 20, color: one ? p.accentText : p.text4, label: '循环播放',
                  onTap: () => player.setMode(one ? PlayMode.sequence : PlayMode.repeatOne)),
            ]),
            const SizedBox(height: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ValueListenableBuilder<Duration>(
                valueListenable: player.position,
                builder: (context, pos, _) {
                  final total = player.duration;
                  final f = total.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / total.inMilliseconds;
                  return Row(children: [
                    Text(formatDuration(pos), style: ts(12, color: p.text4, tabular: true)),
                    const SizedBox(width: 10),
                    Expanded(child: SeekBar(value: f, thumb: false, onSeek: player.seekFraction)),
                    const SizedBox(width: 10),
                    Text(formatDuration(total), style: ts(12, color: p.text4, tabular: true)),
                  ]);
                },
              ),
            ),
          ]),
        ),
        const SizedBox(width: 20),
        SizedBox(
          width: 250,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            YIconButton(YIcons.lyrics, size: 36, iconSize: 20, color: onPlayerPage ? p.accentText : p.text3, label: '歌词', onTap: () {
              onPlayerPage ? Navigator.of(context).maybePop() : openPlayer(context);
            }),
            const SizedBox(width: 6),
            YIconButton(YIcons.queue, size: 36, iconSize: 20, color: p.text3, label: '播放队列', onTap: () => openQueue(context)),
            const SizedBox(width: 12),
            YIconButton(player.volume == 0 ? YIcons.volumeMute : YIcons.volume, size: 28, iconSize: 20, color: p.text3, label: '静音',
                onTap: () => player.setVolume(player.volume == 0 ? 0.65 : 0)),
            const SizedBox(width: 6),
            SizedBox(width: 84, child: SeekBar(value: player.volume, thumb: false, onSeek: player.setVolume)),
          ]),
        ),
      ]),
    );
  }
}
