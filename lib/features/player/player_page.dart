import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/cover_colors.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';

/// 移动端“正在播放”。
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final song = player.current;
    final pad = MediaQuery.paddingOf(context);
    if (song == null) {
      return GlowBackground.player(context);
    }
    final glassShadow = [const Shadow2(0, 6, 18, Color.fromRGBO(0, 0, 0, 0.1)), p.glassButtonShadow.last];
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 600) Navigator.of(context).maybePop();
      },
      child: GlowBackground.player(
        context,
        child: LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight - pad.top - pad.bottom;
            final extra = h - 844;
            final double coverSize = math.min(c.maxWidth - 80, math.max(200.0, 310 + math.min(0.0, extra)));
            final double topGap = 28 + math.max(0.0, extra * 0.25);
            return Padding(
              padding: EdgeInsets.only(top: pad.top),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        GlassButton(YIcons.chevronDown, label: '收起播放页', shadows: glassShadow, onTap: () => Navigator.of(context).maybePop()),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '正在播放',
                                style: ts(11, weight: w600, em: 0.14, color: p.playerText2),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                player.queueTitle ?? song.albumName,
                                style: ts(14, weight: w600, color: p.text),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        GlassButton(YIcons.more, label: '更多', shadows: glassShadow, onTap: () => showSongMenu(context, song)),
                      ],
                    ),
                  ),
                  SizedBox(height: topGap),
                  Hero(
                    tag: 'cover',
                    child: Cover(
                      song.coverUrl,
                      size: coverSize,
                      radius: 30,
                      imageSize: 800,
                      shadows: [
                        Shadow2(0, 28, 56, CoverThemed.shadowOf(context).withValues(alpha: 0.35)),
                        const Shadow2(0, 4, 10, Color.fromRGBO(0, 0, 0, 0.08)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        _TitleRow(song: song),
                        const SizedBox(height: 36),
                        const _Progress(),
                        const SizedBox(height: 28),
                        const _Controls(),
                        const SizedBox(height: 20),
                        const _LyricPreview(),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, math.max(22, pad.bottom + 8) - pad.bottom),
                    child: _PlayerTabs(song: song),
                  ),
                  SizedBox(height: pad.bottom),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final liked = player.isLiked(song);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.name,
                style: ts(26, weight: w700, em: -0.02, height: 1.15, color: p.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Pressable(
                onTap: song.artists.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).maybePop();
                        openArtist(context, song.artists.first);
                      },
                pressedOpacity: 0.6,
                scale: 1,
                child: Text(
                  song.subtitle,
                  style: ts(17, color: p.playerText2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Pressable(
          onTap: () => player.toggleLike(song),
          scale: 0.9,
          semanticLabel: liked ? '取消喜欢' : '喜欢',
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: p.translucentButton, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: YIcon(liked ? YIcons.heart : YIcons.heartOutline, size: 22, color: p.accentText),
          ),
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.read<PlayerController>();
    final total = context.select<PlayerController, Duration>((c) => c.duration);
    return ValueListenableBuilder<Duration>(
      valueListenable: player.position,
      builder: (context, pos, _) {
        final f = total.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / total.inMilliseconds;
        final remain = total - pos;
        return Column(
          children: [
            SeekBar(value: f, onSeek: player.seekFraction),
            const SizedBox(height: 8),
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
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final shuffle = player.mode == PlayMode.shuffle;
    final one = player.mode == PlayMode.repeatOne;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        YIconButton(
          YIcons.shuffle,
          size: 48,
          iconSize: 24,
          color: shuffle ? p.accentText : p.playerText2,
          label: '随机播放',
          onTap: () => player.setMode(shuffle ? PlayMode.sequence : PlayMode.shuffle),
        ),
        YIconButton(YIcons.prev, size: 56, iconSize: 32, color: p.text, label: '上一首', onTap: player.previous),
        PlayButton(size: 72, iconSize: 30),
        YIconButton(YIcons.next, size: 56, iconSize: 32, color: p.text, label: '下一首', onTap: player.next),
        YIconButton(
          one ? YIcons.repeatOne : YIcons.repeat,
          size: 48,
          iconSize: 24,
          color: one ? p.accentText : p.playerText2,
          label: '循环播放',
          onTap: () => player.setMode(one ? PlayMode.sequence : PlayMode.repeatOne),
        ),
      ],
    );
  }
}

/// 圆形播放 / 暂停按钮。
class PlayButton extends StatelessWidget {
  const PlayButton({super.key, required this.size, required this.iconSize, this.shadow = false, this.largePause = true});

  final double size;
  final double iconSize;
  final bool shadow;

  /// 设计稿中播放页 / 桌面端使用较粗的暂停图标，歌词页使用标准图标。
  final bool largePause;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    return Pressable(
      onTap: player.toggle,
      scale: 0.94,
      semanticLabel: player.playing ? '暂停' : '播放',
      child: YBox(
        width: size,
        height: size,
        radius: BorderRadius.circular(size / 2),
        color: p.primaryButton,
        shadows: shadow ? const [Shadow2(0, 10, 22, Color.fromRGBO(29, 29, 31, 0.28))] : const [],
        alignment: Alignment.center,
        child: player.buffering && !player.playing
            ? SizedBox(
                width: iconSize * 0.8,
                height: iconSize * 0.8,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: p.primaryButtonText),
              )
            : YIcon(player.playing ? (largePause ? YIcons.pauseLarge : YIcons.pause) : YIcons.play, size: iconSize, color: p.primaryButtonText),
      ),
    );
  }
}

class _LyricPreview extends StatelessWidget {
  const _LyricPreview();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.read<PlayerController>();
    final lyrics = context.select<PlayerController, Lyrics>((c) => c.lyrics);
    return Pressable(
      onTap: () => openLyrics(context),
      scale: 1,
      child: SizedBox(
        height: 54,
        width: double.infinity,
        child: ValueListenableBuilder<Duration>(
          valueListenable: player.position,
          builder: (context, pos, _) {
            final i = lyrics.indexAt(pos);
            final line = i >= 0 ? lyrics.lines[i].text : (lyrics.lines.isEmpty ? '暂无歌词' : lyrics.lines.first.text);
            final next = i + 1 < lyrics.lines.length ? lyrics.lines[i + 1].text : '';
            return Column(
              children: [
                Text(
                  line,
                  textAlign: TextAlign.center,
                  style: ts(20, weight: w700, em: -0.01, height: 1.35, color: p.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  next,
                  textAlign: TextAlign.center,
                  style: ts(16, weight: w600, height: 1.35, color: p.lyricDim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlayerTabs extends StatelessWidget {
  const _PlayerTabs({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget item(YIconData icon, String label, VoidCallback onTap, {bool active = false}) {
      final color = active ? p.accentText : p.text3;
      return Expanded(
        child: Pressable(
          onTap: onTap,
          scale: 0.96,
          semanticLabel: label,
          child: Container(
            decoration: BoxDecoration(color: active ? p.navActive : Colors.transparent, borderRadius: BorderRadius.circular(27)),
            child: CustomPaint(
              foregroundPainter: active ? InsetShadowPainter(BorderRadius.circular(27), [Shadow2(0, 0.5, 1, p.navActiveInset)]) : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  YIcon(icon, size: 22, color: color),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: ts(11, weight: active ? w600 : w500, color: color, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Glass(
      radius: 32,
      height: 64,
      padding: const EdgeInsets.all(5),
      shadows: [const Shadow2(0, 10, 30, Color.fromRGBO(0, 0, 0, 0.12)), const Shadow2(0, 1, 3, Color.fromRGBO(0, 0, 0, 0.08))],
      child: Row(
        children: [
          item(YIcons.lyrics, '歌词', () => openLyrics(context), active: true),
          item(YIcons.comment, '评论', () => openComments(context, song)),
          item(YIcons.download, '下载', () => downloadSongs(context, [song])),
          item(YIcons.queue, '队列', () => openQueue(context)),
        ],
      ),
    );
  }
}
