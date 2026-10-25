import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';
import 'actions.dart';

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
        leading = Cover(song.coverUrl, size: 46, radius: 10);
      case SongLead.number:
        leading = SizedBox(
          width: 28,
          child: Center(
            child: isCurrent ? NowPlayingBars(color: p.accentText, playing: playing) : Text('${number ?? ''}', style: ts(14, color: p.text2, tabular: true)),
          ),
        );
      case SongLead.rank:
        leading = SizedBox(
          width: 28,
          child: Text(
            '${number ?? ''}',
            textAlign: TextAlign.center,
            style: ts(20, weight: w700, color: (number ?? 99) <= 3 ? p.accentText : p.muted),
          ),
        );
      case SongLead.none:
        leading = null;
    }
    final gap = lead == SongLead.number ? 8.0 : (lead == SongLead.rank ? 10.0 : 12.0);

    return Pressable(
      onTap: song.playable ? onTap : () => _unavailable(context),
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
                if (lead == SongLead.rank) ...[Cover(song.coverUrl, size: 46, radius: 10), const SizedBox(width: 10)],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      highlightText(song.name, keyword, ts(15, weight: w600, color: titleColor), p.accentText),
                      const SizedBox(height: 2),
                      Text(
                        subtitle ?? song.artistText,
                        style: ts(13, color: p.text2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                switch (trailing) {
                  SongTrailing.more => YIconButton(YIcons.more, color: p.muted, label: '更多', onTap: () => showSongMenu(context, song)),
                  SongTrailing.play => YIconButton(YIcons.playOutline, color: p.text, label: '播放', onTap: onTap),
                  SongTrailing.none => const SizedBox(width: 8),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum SongTrailing { more, play, none }

void _unavailable(BuildContext context) => Toast.show(context, '暂无播放版权', icon: YIcons.lock);

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
      onTap: onTap,
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
                  Cover(song.coverUrl, size: 40, radius: 8)
                else
                  SizedBox(
                    width: 28,
                    child: Center(
                      child: isCurrent
                          ? NowPlayingBars(color: p.accentText, playing: playing)
                          : Text('${number ?? ''}', style: ts(14, color: p.text2, tabular: true)),
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
                      Text(
                        song.artistText,
                        style: ts(13, color: p.text2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
              width: 28,
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
