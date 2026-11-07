import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../data/sources/source_manager.dart';
import '../../player/player_controller.dart';
import 'actions.dart';
import 'song_cover.dart';

/// 歌名中高亮搜索关键字（红色）。
Widget highlightText(String text, String? keyword, TextStyle style, Color accent) {
  final k = keyword?.trim() ?? '';
  if (k.isEmpty || !text.contains(k)) {
    return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
  final spans = <TextSpan>[];
  var start = 0;
  while (true) {
    final i = text.indexOf(k, start);
    if (i < 0) {
      spans.add(TextSpan(text: text.substring(start)));
      break;
    }
    if (i > start) spans.add(TextSpan(text: text.substring(start, i)));
    spans.add(
      TextSpan(
        text: k,
        style: TextStyle(color: accent),
      ),
    );
    start = i + k.length;
  }
  return Text.rich(
    TextSpan(style: style, children: spans),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

enum SongLead { cover, number, rank, none }

/// 移动端歌曲行（高 64，封面 46）。
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.song,
    required this.onTap,
    this.lead = SongLead.cover,
    this.number,
    this.subtitle,
    this.keyword,
    this.trailing = SongTrailing.more,
    this.height = 64,
  });

  final Song song;
  final VoidCallback onTap;
  final SongLead lead;
  final int? number;
  final String? subtitle;
  final String? keyword;
  final SongTrailing trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final isCurrent = context.select<PlayerController, bool>((c) => c.current == song);
    final playing = isCurrent && context.select<PlayerController, bool>((c) => c.playing);
    final titleColor = isCurrent && lead == SongLead.number ? p.accentText : p.text;

    Widget? leading;
    switch (lead) {
      case SongLead.cover:
        leading = SongCover(song, size: 46, radius: 10);
      case SongLead.number:
        leading = SizedBox(
          width: 28,
          child: Center(
            child: isCurrent ? NowPlayingBars(color: p.accentText, playing: playing) : _Number(number, style: ts(14, color: p.text2, tabular: true)),
          ),
        );
      case SongLead.rank:
        leading = SizedBox(
          width: 28,
          child: Center(
            child: _Number(number, style: ts(20, weight: w700, color: (number ?? 99) <= 3 ? p.accentText : p.muted)),
          ),
        );
      case SongLead.none:
        leading = null;
    }
    final gap = lead == SongLead.number ? 8.0 : (lead == SongLead.rank ? 10.0 : 12.0);

    return Pressable(
      onTap: song.playable ? onTap : () => _unavailable(context, song),
      onLongPress: () => showSongMenu(context, song),
      onSecondaryTap: () => showSongMenu(context, song),
      scale: 1,
      hoverColor: p.separator.withValues(alpha: 0.06),
      child: _Dim(
        dim: !song.playable,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.only(left: lead == SongLead.rank ? 8 : 12, right: 4),
            child: Row(
              children: [
                if (leading != null) ...[leading, SizedBox(width: gap)],
                if (lead == SongLead.rank) ...[SongCover(song, size: 46, radius: 10), const SizedBox(width: 10)],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      highlightText(song.name, keyword, ts(15, weight: w600, color: titleColor), p.accentText),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          SongBadges(song),
                          Flexible(
                            child: Text(
                              subtitle ?? song.artistText,
                              style: ts(13, color: p.text2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                switch (trailing) {
                  SongTrailing.more => YIconButton(YIcons.more, color: p.muted, label: '更多', onTap: () => showSongMenu(context, song)),
                  SongTrailing.play => YIconButton(YIcons.playOutline, color: p.text, label: '播放', onTap: onTap),
                  SongTrailing.none => const SizedBox(width: 8),
                  SongTrailing.likeMore => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (context) {
                          final liked = context.select<PlayerController, bool>((c) => c.isLiked(song));
                          return YIconButton(
                            liked ? YIcons.heart : YIcons.heartOutline,
                            color: liked ? p.accentText : p.muted,
                            label: liked ? '取消喜欢' : '喜欢',
                            onTap: () => context.read<PlayerController>().toggleLike(song),
                          );
                        },
                      ),
                      YIconButton(YIcons.more, color: p.muted, label: '更多', onTap: () => showSongMenu(context, song)),
                    ],
                  ),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum SongTrailing { more, play, none, likeMore }

/// 歌曲的标签，按各平台自己的规则与配色显示：
/// - 会员歌曲：网易云红色、QQ 音乐绿色、酷狗蓝色、酷我金色的“VIP”；
/// - 需要单独购买的付费歌曲（数字专辑、付费单曲）：“付费”；
/// - 平台提供的最高音质：无损“SQ”、Hi-Res（网易云“Hi-Res”，QQ 音乐与酷狗“HR”）。
class SongBadges extends StatelessWidget {
  const SongBadges(this.song, {super.key});

  final Song song;

  /// 歌曲实际所属的平台（洛雪曲库的歌曲 id 带有平台前缀，例如“kg/…”）。
  static String platformOf(Song song) {
    if (song.sourceId != 'lx') return song.sourceId;
    final i = song.id.indexOf('/');
    return switch (i > 0 ? song.id.substring(0, i) : 'kw') {
      'kg' => 'kugou',
      'tx' => 'qq',
      'wy' => 'netease',
      _ => 'kuwo',
    };
  }

  static Color colorOf(String platform) => switch (platform) {
    'qq' => const Color(0xFF1DB954),
    'kugou' => const Color(0xFF2CA2F9),
    'kuwo' => const Color(0xFFF2A100),
    _ => const Color(0xFFFF3A3A),
  };

  @override
  Widget build(BuildContext context) {
    final platform = platformOf(song);
    final color = colorOf(platform);
    final quality = switch (song.maxQuality) {
      AudioQuality.hires => platform == 'netease' ? 'Hi-Res' : 'HR',
      AudioQuality.lossless => 'SQ',
      _ => null,
    };
    if (song.fee == SongFee.free && quality == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (song.fee == SongFee.vip) _Badge('VIP', color: color, filled: platform == 'qq' || platform == 'kugou'),
        if (song.fee == SongFee.paid) _Badge('付费', color: platform == 'qq' ? const Color(0xFFFF8A00) : color),
        if (quality != null) _Badge(quality, color: color.withValues(alpha: 0.85)),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.color, this.filled = false});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
      decoration: BoxDecoration(
        color: filled ? color : null,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(text, style: ts(9.5, weight: w700, color: filled ? const Color(0xFFFFFFFF) : color, height: 1.25)),
    );
  }
}

/// 无法播放的歌曲：没有版权，或者是需要会员 / 购买的歌曲（按平台规则提示）。
void _unavailable(BuildContext context, Song song) {
  if (!song.vip) {
    Toast.show(context, '暂无播放版权', icon: YIcons.lock);
    return;
  }
  final source = context.read<SourceManager>().byId(song.sourceId);
  if (song.fee == SongFee.paid) {
    Toast.show(context, '付费歌曲，需要在${source.name}单独购买后播放', icon: YIcons.lock);
    return;
  }
  Toast.show(context, source.loggedIn ? '会员歌曲，开通${source.name}会员后可以播放' : '会员歌曲，登录有会员的${source.name}账号后播放', icon: YIcons.lock);
}

/// 桌面端表格行（高 56）：序号或封面 / 标题+歌手 / 专辑 / 时长 / 更多。
class DesktopSongRow extends StatelessWidget {
  const DesktopSongRow({super.key, required this.song, required this.onTap, this.number, this.cover = false, this.keyword, this.highlightCurrent = true});

  final Song song;
  final VoidCallback onTap;
  final int? number;
  final bool cover;
  final String? keyword;
  final bool highlightCurrent;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final isCurrent = highlightCurrent && context.select<PlayerController, bool>((c) => c.current == song);
    final playing = isCurrent && context.select<PlayerController, bool>((c) => c.playing);
    return Pressable(
      onTap: song.playable ? onTap : () => _unavailable(context, song),
      onSecondaryTap: () => showSongMenu(context, song),
      onLongPress: () => showSongMenu(context, song),
      scale: 1,
      hoverColor: p.separator.withValues(alpha: 0.35),
      child: _Dim(
        dim: !song.playable,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: EdgeInsets.fromLTRB(cover ? 12 : 16, 0, 12, 0),
            child: Row(
              children: [
                if (cover)
                  SongCover(song, size: 40, radius: 8)
                else
                  SizedBox(
                    width: 36,
                    child: Center(
                      child: isCurrent ? NowPlayingBars(color: p.accentText, playing: playing) : _Number(number, style: ts(14, color: p.text2, tabular: true)),
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 16,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      highlightText(song.name, keyword, ts(15, weight: w600, color: isCurrent ? p.accentText : p.text), p.accentText),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          SongBadges(song),
                          Flexible(
                            child: Text(
                              song.artistText,
                              style: ts(13, color: p.text2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 10,
                  child: Text(
                    song.albumName,
                    style: ts(14, color: p.text2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 56,
                  child: Text(
                    formatDuration(song.duration),
                    textAlign: TextAlign.right,
                    style: ts(14, color: p.text2, tabular: true),
                  ),
                ),
                const SizedBox(width: 14),
                YIconButton(YIcons.more, size: 36, iconSize: 20, color: p.muted, label: '更多', onTap: () => showSongMenu(context, song)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 桌面端表头。
class DesktopTableHeader extends StatelessWidget {
  const DesktopTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = ts(12, weight: w600, color: p.text2);
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text('#', textAlign: TextAlign.center, style: s),
            ),
            const SizedBox(width: 14),
            Expanded(flex: 16, child: Text('标题', style: s)),
            const SizedBox(width: 14),
            Expanded(flex: 10, child: Text('专辑', style: s)),
            const SizedBox(width: 14),
            SizedBox(
              width: 56,
              child: Text('时长', textAlign: TextAlign.right, style: s),
            ),
            const SizedBox(width: 14),
            const SizedBox(width: 36),
          ],
        ),
      ),
    );
  }
}

/// 歌单封面卡片（132 宽 / 网格）。
class PlaylistTile extends StatelessWidget {
  const PlaylistTile({super.key, required this.cover, required this.title, required this.subtitle, this.onTap, this.width, this.radius = 20});

  final String? cover;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, c) => Cover(cover, size: c.maxWidth, radius: radius, shadows: p.coverShadow),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              title,
              style: ts(14, weight: w600, color: p.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: ts(12, color: p.text2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

String playlistSubtitle(PlaylistInfo p) {
  final count = p.trackCount > 0 ? '${p.trackCount} 首' : '';
  final tag = p.genre.isNotEmpty ? p.genre : (p.creator ?? '');
  return [count, tag].where((s) => s.isNotEmpty).join(' · ');
}

/// 无法播放的歌曲行：文字变淡（通过调色板实现，不产生离屏图层）。
class _Dim extends StatelessWidget {
  const _Dim({required this.dim, required this.child});

  final bool dim;
  final Widget child;

  @override
  Widget build(BuildContext context) => dim ? PaletteScope(palette: Palette.of(context).dimmed(0.45), child: child) : child;
}

/// 序号：始终一行，位数多时按宽度缩小（三位、四位序号不会折成两行）。
class _Number extends StatelessWidget {
  const _Number(this.number, {required this.style});

  final int? number;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text('${number ?? ''}', maxLines: 1, softWrap: false, style: style),
  );
}
