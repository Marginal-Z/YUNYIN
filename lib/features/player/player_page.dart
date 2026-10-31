import 'dart:math' as math;

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
import '../../data/models.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import 'artwork.dart';

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
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // 收起与更多按钮不加背景，只保留图标。
          YIconButton(YIcons.chevronDown, size: 44, iconSize: 26, color: p.text, label: '收起播放页', onTap: () => Navigator.of(context).maybePop()),
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
          YIconButton(YIcons.more, size: 44, iconSize: 24, color: p.text, label: '更多', onTap: () => showSongMenu(context, song)),
        ],
      ),
    );
    final style = context.select<AppSettings, PlayerStyle>((s) => s.playerStyle);
    // 下拉收起由 SheetRoute 处理（页面跟随手指）。
    return GlowBackground.player(
      context,
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth > c.maxHeight * 1.3) return _landscape(context, c, header);
          if (style == PlayerStyle.immersive) return _immersive(context, c, header);
          final h = c.maxHeight - pad.top - pad.bottom;
          final extra = h - 844;
          final double topGap = 28 + math.max(0.0, extra * 0.25);
          // 封面以外的内容约占 500 高度；矮屏缩小封面（不小于 120），仍放不下（横屏）时整页可滚动。
          const fixed = 500.0;
          final double coverSize = math.max(120.0, math.min(math.min(c.maxWidth - 80, 310.0), h - fixed - (topGap - 28)));
          final scroll = h < fixed + 120;
          final page = Padding(
            padding: EdgeInsets.only(top: pad.top),
            child: Column(
              children: [
                const SizedBox(height: 20),
                header,
                SizedBox(height: topGap),
                PlayerArtwork(song: song, size: coverSize, style: style),
                const SizedBox(height: 22),
                // 封面下方两行歌词；歌名、进度与播放控件放在下方，靠近功能卡片。
                const Padding(padding: EdgeInsets.symmetric(horizontal: 28), child: _LyricPreview()),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      _TitleRow(song: song),
                      const SizedBox(height: 20),
                      const _Progress(),
                      const SizedBox(height: 18),
                      const _Controls(),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, math.max(22, pad.bottom + 8) - pad.bottom),
                  child: _PlayerTabs(song: song),
                ),
                SizedBox(height: pad.bottom),
              ],
            ),
          );
          if (!scroll) return page;
          return SingleChildScrollView(
            child: SizedBox(height: fixed + coverSize + pad.top + pad.bottom, child: page),
          );
        },
      ),
    );
  }

  /// 沉浸：封面铺满上半屏、底边渐隐，下面是柔化的封面背景与播放控件。
  Widget _immersive(BuildContext context, BoxConstraints c, Widget header) {
    final p = Palette.of(context);
    final pad = MediaQuery.paddingOf(context);
    final song = context.read<PlayerController>().current!;
    final w = c.maxWidth;
    final imageH = math.min(w * 1.05, c.maxHeight * 0.56);
    return Stack(
      children: [
        Positioned.fill(
          child: ImmersiveBackdrop(url: song.coverUrl, dark: p.isDark),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: imageH,
          child: Pressable(
            onTap: () => openLyrics(context),
            onLongPress: () => pickPlayerStyle(context),
            scale: 1,
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.62, 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: CoverImage(song.coverUrl, imageSize: 1000),
            ),
          ),
        ),
        // 顶部渐暗，保证状态栏与按钮清晰。
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: pad.top + 96,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x59000000), Color(0x00000000)]),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // 标题栏压在封面上：无论深浅色模式都用浅色文字与图标。
              PaletteScope(palette: context.read<AppSettings>().palette(true), child: header),
              const Spacer(),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 28), child: _LyricPreview()),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    _TitleRow(song: song),
                    const SizedBox(height: 16),
                    const _Progress(),
                    const SizedBox(height: 14),
                    const _Controls(),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, math.max(22, pad.bottom + 8) - pad.bottom),
                child: _PlayerTabs(song: song),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 横屏：左侧封面，右侧歌名、进度、播放控件与功能卡片。
  Widget _landscape(BuildContext context, BoxConstraints c, Widget header) {
    final pad = MediaQuery.paddingOf(context);
    final song = context.read<PlayerController>().current!;
    final h = c.maxHeight - pad.top - pad.bottom;
    final double cover = (h - 100).clamp(120.0, c.maxWidth * 0.4);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad.left, pad.top + 12, pad.right, pad.bottom + 12),
      child: Column(
        children: [
          header,
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: 28),
                PlayerArtwork(
                  song: song,
                  size: cover,
                  style: context.select<AppSettings, PlayerStyle>((s) => s.playerStyle == PlayerStyle.immersive ? PlayerStyle.cover : s.playerStyle),
                ),
                const SizedBox(width: 28),
                Expanded(
                  // 内容高度超出时整体缩小，保证完整显示。
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 420,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TitleRow(song: song),
                          const SizedBox(height: 12),
                          const _Progress(),
                          const SizedBox(height: 8),
                          const _Controls(),
                          const SizedBox(height: 12),
                          _PlayerTabs(song: song),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
              ],
            ),
          ),
        ],
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
            // 换行时新歌词自下而上滑入。
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
              child: Column(
                key: ValueKey(i),
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
              ),
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
      );
    }

    // 功能栏透明、无背景框，当前项以主题色区分。
    return SizedBox(
      height: 64,
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
