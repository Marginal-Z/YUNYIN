import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/listen_stats.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

/// 听歌统计：今日 / 本周 / 累计时长、最近 7 天、最常听的歌曲与歌手。
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final stats = context.watch<ListenStats>();
    final desktop = LayoutScope.isDesktop(context);
    final top = stats.topSongs(10);
    final artists = stats.topArtists(5);
    final summary = Row(
      children: [
        Expanded(
          child: _Figure(label: '今天', value: stats.today),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Figure(label: '本周', value: stats.thisWeek),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Figure(label: '累计', value: stats.total, note: '${stats.activeDays} 天'),
        ),
      ],
    );
    final chart = YCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: _WeekChart(days: stats.lastDays(7)),
      ),
    );
    final songs = top.isEmpty
        ? YCard(
            child: StateView.empty(title: '还没有收听记录', message: '播放歌曲后，这里会显示你最常听的歌曲与歌手。', icon: YIcons.equalizer),
          )
        : CardList(
            indent: 70,
            children: [
              for (var i = 0; i < top.length; i++)
                _RankRow(
                  rank: i + 1,
                  cover: top[i].song.coverUrl,
                  title: top[i].song.name,
                  subtitle: '${top[i].song.subtitle} · ${top[i].plays} 次',
                  value: formatListen(top[i].time),
                  onTap: () => playAll(context, [for (final e in top) e.song], start: i, title: '最常听的歌曲'),
                ),
            ],
          );
    final artistList = CardList(
      indent: 70,
      children: [
        for (var i = 0; i < artists.length; i++)
          _RankRow(rank: i + 1, cover: artists[i].$3, title: artists[i].$1, value: formatListen(artists[i].$2), circle: true),
      ],
    );
    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 78,
      overlay: [
        Positioned(
          left: 16,
          top: 20,
          child: GlassButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop()),
        ),
      ],
      children: [
        PageTitle('听歌统计', subtitle: '只统计实际播放的时长', size: desktop ? 40 : 36),
        const SizedBox(height: 16),
        summary,
        const SectionHeader('最近 7 天', top: 24),
        chart,
        if (desktop && artists.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const SectionHeader('最常听的歌曲'), songs]),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const SectionHeader('最常听的歌手'), artistList]),
              ),
            ],
          )
        else ...[
          const SectionHeader('最常听的歌曲'),
          songs,
          if (artists.isNotEmpty) ...[const SectionHeader('最常听的歌手'), artistList],
        ],
        SizedBox(height: desktop ? 24 : 12),
        Text(
          '统计数据只保存在本机。',
          style: ts(12, color: p.text2),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.note});

  final String label;
  final Duration value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final h = value.inHours;
    final m = value.inMinutes % 60;
    return YCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: ts(13, weight: w600, color: p.text2),
            ),
            const SizedBox(height: 6),
            // 数字自动缩小以适应卡片宽度，避免窄屏换行或截断。
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    if (h > 0) ...[
                      TextSpan(
                        text: '$h',
                        style: ts(28, weight: w700, color: p.text, tabular: true),
                      ),
                      TextSpan(
                        text: ' 时 ',
                        style: ts(13, weight: w600, color: p.text2),
                      ),
                    ],
                    TextSpan(
                      text: '$m',
                      style: ts(28, weight: w700, color: p.text, tabular: true),
                    ),
                    TextSpan(
                      text: ' 分',
                      style: ts(13, weight: w600, color: p.text2),
                    ),
                  ],
                ),
                maxLines: 1,
              ),
            ),
            if (note != null) Text(note!, style: ts(12, color: p.text2)),
          ],
        ),
      ),
    );
  }
}

/// 最近 7 天柱状图（扁平纯色）。
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days});

  final List<(DateTime, Duration)> days;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final max = days.fold<int>(0, (a, d) => d.$2.inMinutes > a ? d.$2.inMinutes : a);
    const w = '一二三四五六日';
    final today = DateTime.now();
    return SizedBox(
      height: 168,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (day, time) in days)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    time.inMinutes > 0 ? '${time.inMinutes}' : '',
                    style: ts(11, weight: w600, color: p.text2, tabular: true),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: FractionallySizedBox(
                      heightFactor: max == 0 ? 0.02 : (time.inMinutes / max).clamp(0.02, 1.0),
                      child: Container(
                        width: 22,
                        decoration: BoxDecoration(
                          color: day.day == today.day && day.month == today.month ? p.accentText : p.accentText.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    day.day == today.day && day.month == today.month ? '今天' : '周${w[day.weekday - 1]}',
                    style: ts(11, weight: w500, color: p.text2),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.cover, required this.title, required this.value, this.subtitle, this.onTap, this.circle = false});

  final int rank;
  final String? cover;
  final String title;
  final String? subtitle;
  final String value;
  final VoidCallback? onTap;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      scale: 1,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Cover(cover, size: 44, radius: 10, circle: circle),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$rank  $title',
                      style: ts(15, weight: w600, color: p.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: ts(12, color: p.text2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: ts(13, weight: w600, color: p.text2, tabular: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
