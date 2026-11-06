import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../core/image_share.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/motion.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/listen_stats.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../common/song_cover.dart';
import '../shell/nav.dart';

/// 统计的时间范围。
enum StatsPeriod {
  week('近 7 天', 7),
  month('近 30 天', 30),
  all('全部', null);

  const StatsPeriod(this.label, this.days);
  final String label;
  final int? days;
}

/// 平台名称（统计里按歌曲所属平台汇总）。
String platformName(String id) => switch (id) {
  'netease' => '网易云音乐',
  'qq' => 'QQ 音乐',
  'kugou' => '酷狗音乐',
  'lx' => '洛雪曲库',
  'local' => '本地音乐',
  _ => id,
};

/// 时段的说法。
String hourText(int h) => switch (h) {
  < 5 => '深夜',
  < 9 => '清晨',
  < 12 => '上午',
  < 14 => '午间',
  < 18 => '下午',
  < 22 => '晚上',
  _ => '深夜',
};

/// 听歌统计：总览、每日时长、一天中的分布、平台分布、最常听的歌曲与歌手，可以生成听歌海报分享。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatsPeriod _period = StatsPeriod.week;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final stats = context.watch<ListenStats>();
    final desktop = LayoutScope.isDesktop(context);
    final top = stats.topSongs(10);
    final artists = stats.topArtists(5);
    final chartDays = _period == StatsPeriod.week ? 7 : 30;
    final favorite = stats.favoriteHour;

    var i = 0;
    Widget reveal(Widget child) => Reveal(index: i++, child: child);

    final songs = top.isEmpty
        ? YCard(
            child: StateView.empty(title: '还没有收听记录', message: '播放歌曲后，这里会显示你最常听的歌曲与歌手。', icon: YIcons.equalizer),
          )
        : CardList(
            indent: 70,
            children: [
              for (var n = 0; n < top.length; n++)
                _RankRow(
                  rank: n + 1,
                  cover: SongCover(top[n].song, size: 44, radius: 10),
                  title: top[n].song.name,
                  subtitle: '${top[n].song.artistText} · ${top[n].plays} 次',
                  value: formatListen(top[n].time),
                  share: top[n].ms / top.first.ms,
                  onTap: () => playAll(context, [for (final e in top) e.song], start: n, title: '最常听的歌曲'),
                ),
            ],
          );
    final artistList = CardList(
      indent: 70,
      children: [
        for (var n = 0; n < artists.length; n++)
          _RankRow(
            rank: n + 1,
            cover: Cover(artists[n].$3, size: 44, circle: true),
            title: artists[n].$1,
            value: formatListen(artists[n].$2),
            share: artists.first.$2.inMilliseconds == 0 ? 0 : artists[n].$2.inMilliseconds / artists.first.$2.inMilliseconds,
          ),
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
        Positioned(
          right: 16,
          top: 20,
          child: GlassButton(YIcons.image, label: '生成听歌海报', onTap: stats.isEmpty ? null : () => showListenPoster(context, _period)),
        ),
      ],
      children: [
        PageTitle('听歌统计', subtitle: '只统计实际播放的时长', size: desktop ? 40 : 36),
        const SizedBox(height: 14),
        Segmented(labels: [for (final v in StatsPeriod.values) v.label], index: _period.index, onChanged: (v) => setState(() => _period = StatsPeriod.values[v])),
        const SizedBox(height: 16),
        reveal(_Hero(stats: stats, period: _period)),
        const SizedBox(height: 12),
        reveal(
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth >= 640 ? (c.maxWidth - 36) / 4 : (c.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (label, value, unit) in [
                    ('今天', formatListen(stats.today), ''),
                    ('完整播放', '${stats.playCount}', '次'),
                    ('听过的歌', '${stats.songCount}', '首'),
                    ('最长连续', '${stats.longestStreak}', '天'),
                  ])
                    SizedBox(
                      width: w,
                      child: _Tile(label: label, value: value, unit: unit),
                    ),
                ],
              );
            },
          ),
        ),
        SectionHeader(_period == StatsPeriod.week ? '每日时长' : '近 30 天每日时长', top: 24),
        reveal(
          YCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: _DayChart(key: ValueKey(chartDays), days: stats.lastDays(chartDays)),
            ),
          ),
        ),
        const SectionHeader('一天中的收听'),
        reveal(
          YCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    favorite == null ? '还没有收听记录' : '你最常在${hourText(favorite)}（$favorite 点前后）听歌',
                    style: ts(14, weight: w600, color: p.text),
                  ),
                  const SizedBox(height: 12),
                  _HourChart(hours: stats.hourly),
                ],
              ),
            ),
          ),
        ),
        if (stats.bySource.isNotEmpty) ...[
          const SectionHeader('平台分布'),
          reveal(_SourceBars(sources: stats.bySource)),
        ],
        if (desktop && artists.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const SectionHeader('最常听的歌曲'), reveal(songs)]),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const SectionHeader('最常听的歌手'), reveal(artistList)]),
              ),
            ],
          )
        else ...[
          const SectionHeader('最常听的歌曲'),
          reveal(songs),
          if (artists.isNotEmpty) ...[const SectionHeader('最常听的歌手'), reveal(artistList)],
        ],
        SizedBox(height: desktop ? 24 : 12),
        Text(
          '统计数据只保存在本机。完整播放：单次连续收听超过 30 秒。',
          style: ts(12, color: p.text2),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 入场动画：按顺序依次从下方弹入并淡入（每项晚 60 毫秒）。
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.page);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _delay = Timer(Duration(milliseconds: 40 + 60 * widget.index.clamp(0, 8)), _c.forward);
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Motion.spring.transform(_c.value);
        return Opacity(
          opacity: Curves.easeOut.transform(_c.value),
          child: Transform.translate(offset: Offset(0, 22 * (1 - t)), child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// 总览：所选时间范围内的总时长（主题色渐变卡片）。
class _Hero extends StatelessWidget {
  const _Hero({required this.stats, required this.period});

  final ListenStats stats;
  final StatsPeriod period;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final total = stats.since(period.days);
    final active = stats.activeIn(period.days);
    final streak = stats.streak;
    const white = Color(0xFFFFFFFF);
    return YCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [p.accent.buttonTop, Color.lerp(p.accent.base, const Color(0xFF000000), 0.35)!],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${period.label}收听', style: ts(14, weight: w600, color: white.withValues(alpha: 0.82))),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              key: ValueKey(period),
              tween: Tween(begin: 0, end: total.inMinutes.toDouble()),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) {
                final m = v.round();
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (m >= 60) ...[
                          TextSpan(text: '${m ~/ 60}', style: ts(46, weight: w700, color: white, tabular: true)),
                          TextSpan(text: ' 小时 ', style: ts(16, weight: w600, color: white.withValues(alpha: 0.85))),
                        ],
                        TextSpan(text: '${m % 60}', style: ts(46, weight: w700, color: white, tabular: true)),
                        TextSpan(text: ' 分钟', style: ts(16, weight: w600, color: white.withValues(alpha: 0.85))),
                      ],
                    ),
                    maxLines: 1,
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              [
                '$active 天有收听',
                if (streak > 0) '已连续 $streak 天',
                if (period.days != null && active > 0) '日均 ${formatListen(Duration(milliseconds: total.inMilliseconds ~/ active))}',
              ].join(' · '),
              style: ts(13, color: white.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return YCard(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: ts(12, weight: w600, color: p.text2)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: value, style: ts(24, weight: w700, color: p.text, tabular: true)),
                    if (unit.isNotEmpty) TextSpan(text: ' $unit', style: ts(12, weight: w600, color: p.text2)),
                  ],
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 柱状图的公共部分：单一系列（主题色），柱子从底部弹起，点按某根柱子显示它的数值。
class _Bars extends StatefulWidget {
  const _Bars({required this.values, required this.labels, required this.valueText, required this.highlight, this.height = 150, this.labelEvery = 1});

  final List<double> values;
  final List<String> labels;
  final String Function(int i) valueText;
  final int? highlight;
  final double height;

  /// 每隔几根柱子显示一个横轴标签（柱子多时避免标签挤在一起）。
  final int labelEvery;

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final max = widget.values.fold<double>(0, (a, v) => v > a ? v : a);
    final n = widget.values.length;
    final selected = _selected ?? widget.highlight;
    return Column(
      children: [
        SizedBox(
          height: 20,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: Motion.quick,
              switchInCurve: Motion.bouncy,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), alignment: Alignment.centerLeft, child: child),
              ),
              child: Text(
                selected == null ? '' : '${widget.labels[selected]} · ${widget.valueText(selected)}',
                key: ValueKey(selected),
                style: ts(12, weight: w600, color: p.text2, tabular: true),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: widget.height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 760),
            curve: Motion.spring,
            builder: (context, grow, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => setState(() => _selected = i),
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _selected = i),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: n > 12 ? 1 : 5),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: AnimatedContainer(
                              duration: Motion.quick,
                              curve: Motion.spring,
                              height: (widget.height * (max == 0 ? 0 : widget.values[i] / max) * grow).clamp(3, widget.height).toDouble(),
                              constraints: const BoxConstraints(maxWidth: 22),
                              decoration: BoxDecoration(
                                color: i == selected ? p.accentText : p.accentText.withValues(alpha: widget.values[i] > 0 ? 0.42 : 0.14),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Container(height: 1, color: p.separator.withValues(alpha: 0.5)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: Text(
                  i % widget.labelEvery == 0 || i == n - 1 ? widget.labels[i] : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: ts(10.5, weight: w500, color: p.text2),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayChart extends StatelessWidget {
  const _DayChart({super.key, required this.days});

  final List<(DateTime, Duration)> days;

  @override
  Widget build(BuildContext context) {
    const w = '一二三四五六日';
    final today = DateTime.now();
    bool isToday(DateTime d) => d.day == today.day && d.month == today.month;
    final short = days.length <= 7;
    return _Bars(
      values: [for (final d in days) d.$2.inSeconds / 60],
      labels: [
        for (final d in days)
          isToday(d.$1)
              ? '今天'
              : short
              ? '周${w[d.$1.weekday - 1]}'
              : '${d.$1.month}/${d.$1.day}',
      ],
      valueText: (i) => formatListen(days[i].$2),
      highlight: days.length - 1,
      labelEvery: short ? 1 : 6,
    );
  }
}

class _HourChart extends StatelessWidget {
  const _HourChart({required this.hours});

  final List<Duration> hours;

  @override
  Widget build(BuildContext context) {
    return _Bars(
      values: [for (final h in hours) h.inSeconds / 60],
      labels: [for (var h = 0; h < 24; h++) '$h 点'],
      valueText: (i) => formatListen(hours[i]),
      highlight: null,
      height: 96,
      labelEvery: 6,
    );
  }
}

/// 平台分布：每个平台一行，平台名称 + 比例条 + 时长（单一色相，平台身份由文字标明）。
class _SourceBars extends StatelessWidget {
  const _SourceBars({required this.sources});

  final List<(String, Duration)> sources;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final total = sources.fold<int>(0, (a, s) => a + s.$2.inMilliseconds);
    return YCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          children: [
            for (final (id, time) in sources)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 78,
                      child: Text(platformName(id), style: ts(13, weight: w600, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) => Stack(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(4)),
                            ),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: total == 0 ? 0 : time.inMilliseconds / total),
                              duration: const Duration(milliseconds: 800),
                              curve: Motion.spring,
                              builder: (context, f, _) => Container(
                                width: (c.maxWidth * f).clamp(0, c.maxWidth).toDouble(),
                                height: 8,
                                decoration: BoxDecoration(color: p.accentText, borderRadius: BorderRadius.circular(4)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: Text(
                        '${total == 0 ? 0 : (time.inMilliseconds * 100 / total).round()}% · ${formatListen(time)}',
                        textAlign: TextAlign.right,
                        style: ts(12, color: p.text2, tabular: true),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.cover, required this.title, required this.value, required this.share, this.subtitle, this.onTap});

  final int rank;
  final Widget cover;
  final String title;
  final String? subtitle;
  final String value;

  /// 与第一名相比的比例（行底部的细条）。
  final double share;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: SizedBox(
        height: 66,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: ts(rank <= 3 ? 17 : 14, weight: w700, color: rank <= 3 ? p.accentText : p.text2, tabular: true),
                ),
              ),
              const SizedBox(width: 8),
              cover,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: ts(15, weight: w600, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null) Text(subtitle!, style: ts(12, color: p.text2), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    FractionallySizedBox(
                      widthFactor: share.clamp(0.02, 1.0),
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(color: p.accentText.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(value, style: ts(13, weight: w600, color: p.text2, tabular: true)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 听歌海报 ──────────────────────────────────────────

/// 打开听歌海报预览：可以保存到相册或分享。
Future<void> showListenPoster(BuildContext context, StatsPeriod period) async {
  final stats = context.read<ListenStats>();
  // 先把海报上的封面载入缓存，导出时不会是空白占位。
  final covers = [
    for (final e in stats.topSongs(5)) e.song.coverUrl,
    for (final a in stats.topArtists(1)) a.$3,
  ].nonNulls.toSet();
  await Future.wait([for (final u in covers) precacheImage(CachedNetworkImageProvider(u), context).catchError((Object _) {})]).timeout(const Duration(seconds: 4), onTimeout: () => const []);
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0xB3000000),
    transitionDuration: Motion.page,
    pageBuilder: (context, _, _) => _PosterDialog(stats: stats, period: period),
    transitionBuilder: (context, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: ScaleTransition(scale: Tween(begin: 0.88, end: 1.0).animate(CurvedAnimation(parent: a, curve: Motion.spring, reverseCurve: Curves.easeIn)), child: child),
    ),
  );
}

class _PosterDialog extends StatefulWidget {
  const _PosterDialog({required this.stats, required this.period});

  final ListenStats stats;
  final StatsPeriod period;

  @override
  State<_PosterDialog> createState() => _PosterDialogState();
}

class _PosterDialogState extends State<_PosterDialog> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _export({required bool share}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await captureBoundary(boundary);
      final name = 'yunyin-listen-${DateTime.now().millisecondsSinceEpoch}.png';
      final msg = share ? await shareImage(png, name: name, text: '我的云音听歌报告') : await saveImage(png, name: name);
      if (mounted && msg.isNotEmpty) Toast.show(context, msg, icon: YIcons.check);
    } catch (e) {
      if (mounted) Toast.show(context, errorText(e), icon: YIcons.info);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {},
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _key,
                    child: ListenPoster(stats: widget.stats, period: widget.period),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: mq.size.width.clamp(0, 420).toDouble()),
              child: Row(
                children: [
                  Expanded(
                    child: SecondaryButton(label: '保存图片', icon: YIcons.download, height: 48, fontSize: 15, iconSize: 18, onTap: _busy ? null : () => _export(share: false)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(label: '分享', icon: YIcons.share, height: 48, fontSize: 15, iconSize: 18, onTap: _busy ? null : () => _export(share: true)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Pressable(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('关闭', style: ts(15, weight: w600, color: const Color(0xCCFFFFFF))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 听歌海报（固定 360 × 640 逻辑像素，导出为 1080 × 1920）。
class ListenPoster extends StatelessWidget {
  const ListenPoster({super.key, required this.stats, required this.period});

  final ListenStats stats;
  final StatsPeriod period;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const white = Color(0xFFFFFFFF);
    final dim = white.withValues(alpha: 0.72);
    final total = stats.since(period.days);
    final top = stats.topSongs(5);
    final artist = stats.topArtists(1).firstOrNull;
    final hour = stats.favoriteHour;
    final now = DateTime.now();
    final h = total.inHours, m = total.inMinutes % 60;
    return SizedBox(
      width: 360,
      height: 640,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.accent.buttonTop, Color.lerp(p.accent.base, const Color(0xFF0B0B10), 0.55)!, const Color(0xFF0B0B10)],
            stops: const [0, 0.55, 1],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 30, 26, 22),
          child: DefaultTextStyle(
            style: ts(13, color: white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('云音 · 听歌报告', style: ts(13, weight: w600, color: dim, em: 0.08)),
                const SizedBox(height: 4),
                Text(period == StatsPeriod.all ? '我的全部收听' : '我的${period.label}', style: ts(24, weight: w700, color: white)),
                const SizedBox(height: 18),
                Text.rich(
                  TextSpan(
                    children: [
                      if (h > 0) ...[
                        TextSpan(text: '$h', style: ts(56, weight: w700, color: white, tabular: true)),
                        TextSpan(text: ' 小时 ', style: ts(16, weight: w600, color: dim)),
                      ],
                      TextSpan(text: '$m', style: ts(56, weight: w700, color: white, tabular: true)),
                      TextSpan(text: ' 分钟', style: ts(16, weight: w600, color: dim)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    '${stats.activeIn(period.days)} 天有收听',
                    '${stats.songCount} 首歌',
                    if (hour != null) '最爱${hourText(hour)}听歌',
                  ].join(' · '),
                  style: ts(13, color: dim),
                ),
                const SizedBox(height: 22),
                Text(period == StatsPeriod.all ? '最常听的歌曲' : '累计最常听的歌曲', style: ts(12, weight: w600, color: dim)),
                const SizedBox(height: 10),
                for (var i = 0; i < top.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text('${i + 1}', style: ts(15, weight: w700, color: i < 3 ? white : dim, tabular: true)),
                        ),
                        Cover(top[i].song.coverUrl, size: 40, radius: 9, imageSize: 160),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(top[i].song.name, style: ts(14, weight: w600, color: white), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(top[i].song.artistText, style: ts(11.5, color: dim), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Text('${top[i].plays} 次', style: ts(12, color: dim, tabular: true)),
                      ],
                    ),
                  ),
                const Spacer(),
                if (artist != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      children: [
                        Cover(artist.$3, size: 44, circle: true, imageSize: 160),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('最常听的歌手', style: ts(11, weight: w600, color: dim)),
                              Text(artist.$1, style: ts(16, weight: w700, color: white), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Text(formatListen(artist.$2), style: ts(12, color: dim)),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('云音 YunYin', style: ts(12, weight: w700, color: white)),
                    const Spacer(),
                    Text('${now.year}.${now.month}.${now.day} 生成', style: ts(11, color: dim)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
