import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/listen_stats.dart';
import '../../data/lx/lx_sources.dart';
import 'lx_page.dart';
import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/downloads.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (LayoutScope.isDesktop(context)) return const _DesktopSettings();
    return MobilePage(
      chrome: Chrome.navOnly,
      top: 78,
      overlay: [
        Positioned(
          left: 16,
          top: 20,
          child: GlassButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop()),
        ),
      ],
      children: const [PageTitle('设置'), SizedBox(height: 16), SettingsEntries(), GroupLabel('关于'), AboutEntry()],
    );
  }
}

/// “关于”入口：隐私政策、用户协议、权限管理、开源许可、意见反馈与版本信息。
class AboutEntry extends StatelessWidget {
  const AboutEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return CardList(
      indent: 56,
      children: [SettingsRow(icon: YIcons.info, tile: TileColor.blue, title: '关于云音', value: '协议与版本', onTap: () => go(context, SettingsMoreRoute()))],
    );
  }
}

String sleepText(DateTime? at) {
  if (at == null) return '关闭';
  final m = at.difference(DateTime.now()).inMinutes + 1;
  return '$m 分钟后';
}

class PlaybackGroup extends StatelessWidget {
  const PlaybackGroup({super.key, this.desktop = false});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final player = context.watch<PlayerController>();
    return CardList(
      indent: 56,
      children: [
        SettingsRow(
          icon: YIcons.equalizer,
          tile: TileColor.blue,
          title: '音质',
          value: s.quality.label,
          onTap: () async {
            final q = await showOptions<AudioQuality>(
              context,
              title: '在线播放音质',
              selected: s.quality,
              options: [for (final q in AudioQuality.values) (q, q.label)],
            );
            if (q != null) s.setQuality(q);
          },
        ),
        SettingsRow(
          icon: desktop ? YIcons.target : YIcons.crossfade,
          tile: TileColor.teal,
          title: '淡入淡出',
          trailing: YSwitch(value: s.crossfade, label: '淡入淡出', onChanged: (v) => s.setFlag('crossfade', v)),
        ),
        SettingsRow(
          icon: YIcons.next,
          tile: TileColor.blue,
          title: '自动切歌',
          value: s.autoNext ? null : '播放完停止',
          trailing: YSwitch(value: s.autoNext, label: '自动切歌', onChanged: (v) => s.setFlag('autoNext', v)),
        ),
        if (!kIsWeb && Platform.isAndroid)
          SettingsRow(
            icon: YIcons.equalizer,
            tile: TileColor.teal,
            title: '高解析输出',
            value: s.hiResOutput ? '32 位浮点' : null,
            trailing: YSwitch(value: s.hiResOutput, label: '高解析输出', onChanged: (v) => s.setFlag('hiResOutput', v)),
          ),
        if (!kIsWeb && (Platform.isWindows || Platform.isMacOS))
          SettingsRow(
            icon: YIcons.equalizer,
            tile: TileColor.teal,
            title: '独占音频输出',
            value: s.exclusiveAudio ? '原始采样率' : null,
            trailing: YSwitch(value: s.exclusiveAudio, label: '独占音频输出', onChanged: (v) => s.setFlag('exclusiveAudio', v)),
          ),
        // 个别 Android 设备（部分平板）上默认的 AudioTrack 输出没有声音，可改用 OpenSL ES。
        if (!kIsWeb && Platform.isAndroid)
          SettingsRow(
            icon: YIcons.volume,
            tile: TileColor.blue,
            title: '兼容音频输出',
            value: s.openSles ? 'OpenSL ES' : null,
            trailing: YSwitch(value: s.openSles, label: '兼容音频输出', onChanged: (v) => s.setFlag('openSles', v)),
          ),
        SettingsRow(
          icon: desktop ? YIcons.clock : YIcons.timer,
          tile: TileColor.orange,
          title: '睡眠定时',
          value: sleepText(player.sleepAt),
          onTap: () async {
            final v = await showOptions<int>(
              context,
              title: '睡眠定时',
              options: const [(0, '关闭'), (15, '15 分钟'), (30, '30 分钟'), (45, '45 分钟'), (60, '60 分钟'), (90, '90 分钟')],
            );
            if (v == null) return;
            player.setSleepTimer(v == 0 ? null : Duration(minutes: v));
          },
        ),
      ],
    );
  }
}

class AppearanceGroup extends StatelessWidget {
  const AppearanceGroup({super.key, this.desktop = false});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.watch<AppSettings>();
    final modes = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];
    return CardList(
      indent: 14,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Segmented(labels: const ['浅色', '深色', '跟随系统'], index: modes.indexOf(s.themeMode), onChanged: (i) => s.setThemeMode(modes[i])),
        ),
        SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text('主题色', style: ts(16, color: p.text)),
                ),
                for (final a in AccentColor.values) ...[
                  SizedBox(width: desktop ? 8 : (a == AccentColor.values.first ? 0 : (s.accent.index == a.index - 1 ? 18 : 12))),
                  _Swatch(accent: a, selected: s.accent == a, gradient: desktop, onTap: () => s.setAccent(a)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.accent, required this.selected, required this.onTap, this.gradient = false});

  final AccentColor accent;
  final bool selected;

  /// 桌面端色块带渐变与光泽。
  final bool gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tile = TileColor.values[accent.index];
    return Pressable(
      onTap: onTap,
      scale: 0.9,
      semanticLabel: accent.label,
      child: CustomPaint(
        foregroundPainter: selected ? _RingPainter(p.swatchRingInner, p.swatchRingOuter) : null,
        child: YBox(
          width: 26,
          height: 26,
          radius: BorderRadius.circular(13),
          color: gradient ? null : accent.base,
          gradient: gradient ? CssGradient(160, colors: [tile.top, tile.bottom]) : null,
          shadows: gradient ? [Shadow2(0, 4, 10, tile.glow.withValues(alpha: 0.30))] : const [],
          insets: gradient ? const [Shadow2(0, 1, 1, Color.fromRGBO(255, 255, 255, 0.45))] : const [],
        ),
      ),
    );
  }
}

/// 选中色块外的双层描边（CSS: 0 0 0 2px 背景色, 0 0 0 4px 前景色）。
class _RingPainter extends CustomPainter {
  _RingPainter(this.inner, this.outer);

  final Color inner;
  final Color outer;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(c, r + 1, paint..color = inner);
    canvas.drawCircle(c, r + 3, paint..color = outer);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.inner != inner || old.outer != outer;
}

/// 设置首页的入口列表：每一项进入一个二级页面。
class SettingsEntries extends StatelessWidget {
  const SettingsEntries({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final lx = context.watch<LxSources>();
    final android = !kIsWeb && Platform.isAndroid;
    final mode = switch (s.themeMode) {
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
      ThemeMode.system => '跟随系统',
    };
    return CardList(
      indent: 56,
      children: [
        SettingsRow(
          icon: YIcons.play,
          tile: TileColor.red,
          title: '播放',
          value: '${s.quality.label} · ${s.crossfade ? '淡入淡出' : '直接切换'}',
          onTap: () => go(context, PlaybackSettingsRoute()),
        ),
        SettingsRow(
          icon: YIcons.sliders,
          tile: TileColor.graphite,
          title: '音效',
          value: [
            if (s.eqEnabled) '均衡器 · ${s.eqPreset.label}',
            if (s.normalize) '音量均衡',
            if (s.volumeBoost > 0) '+${s.volumeBoost} dB',
          ].join(' · ').ifEmpty('关闭'),
          onTap: () => go(context, AudioEffectsRoute()),
        ),
        SettingsRow(
          icon: YIcons.lyrics,
          tile: TileColor.orange,
          title: android ? '桌面与状态栏歌词' : '桌面歌词',
          value: [if (s.desktopLyrics) '桌面', if (s.statusBarLyrics) '状态栏'].join(' · ').ifEmpty('关闭'),
          onTap: () => go(context, LyricsOverlayRoute()),
        ),
        SettingsRow(
          icon: YIcons.sparkle,
          tile: TileColor.values[s.accent.index],
          title: '外观',
          value: '$mode · ${s.accent.label}',
          onTap: () => go(context, AppearanceRoute()),
        ),
        SettingsRow(icon: YIcons.code, tile: TileColor.teal, title: '洛雪音源', value: lxSummary(lx), onTap: () => go(context, LxSourcesRoute())),
        SettingsRow(icon: YIcons.download, tile: TileColor.blue, title: '下载与缓存', onTap: () => go(context, StorageSettingsRoute())),
        SettingsRow(
          icon: YIcons.equalizer,
          tile: TileColor.teal,
          title: '听歌统计',
          value: context.select<ListenStats, int>((st) => st.today.inMinutes) > 0 ? '今日 ${context.select<ListenStats, int>((st) => st.today.inMinutes)} 分钟' : null,
          onTap: () => go(context, StatsRoute()),
        ),
      ],
    );
  }
}

/// 设置的二级页面外框：返回按钮 + 标题。
class SettingsSubPage extends StatelessWidget {
  const SettingsSubPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final desktop = LayoutScope.isDesktop(context);
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
        PageTitle(title, size: desktop ? 40 : 36),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

/// 播放设置（二级页面）。
class PlaybackSettingsPage extends StatelessWidget {
  const PlaybackSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => SettingsSubPage(
    title: '播放',
    children: [PlaybackGroup(desktop: LayoutScope.isDesktop(context))],
  );
}

/// 下载与缓存（二级页面）。
class StorageSettingsPage extends StatelessWidget {
  const StorageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => SettingsSubPage(
    title: '下载与缓存',
    children: [StorageGroup(desktop: LayoutScope.isDesktop(context))],
  );
}

class StorageGroup extends StatefulWidget {
  const StorageGroup({super.key, this.desktop = false});

  final bool desktop;

  @override
  State<StorageGroup> createState() => _StorageGroupState();
}

class _StorageGroupState extends State<StorageGroup> {
  int? _bytes;
  String? _dir;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final dl = context.read<DownloadManager>();
    final b = await dl.cacheBytes();
    final d = dl.supported ? await dl.displayDir() : '—';
    if (mounted) {
      setState(() {
        _bytes = b;
        _dir = d;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final dl = context.read<DownloadManager>();
    final clear = SettingsRow(
      icon: widget.desktop ? YIcons.trash : YIcons.trashSimple,
      tile: widget.desktop ? TileColor.red : TileColor.graphite,
      title: '清除缓存',
      value: _bytes == null ? '…' : formatBytes(_bytes!),
      onTap: () async {
        final ok = await showConfirm(context, title: '清除缓存？', message: '将删除已缓存的封面图片，已下载的歌曲不受影响。', confirm: '清除');
        if (!ok) return;
        await dl.clearCache();
        await _refresh();
        if (context.mounted) Toast.show(context, '缓存已清除');
      },
    );
    if (widget.desktop) {
      return CardList(
        indent: 56,
        children: [
          SettingsRow(
            icon: YIcons.download,
            tile: TileColor.blue,
            title: '下载目录',
            value: _dir ?? '…',
            onTap: () => Toast.show(context, '下载目录：${_dir ?? ''}', icon: YIcons.folder),
          ),
          clear,
        ],
      );
    }
    return CardList(
      indent: 56,
      children: [
        SettingsRow(
          icon: YIcons.wifi,
          tile: TileColor.blue,
          title: '下载网络',
          value: '使用当前网络',
        ),
        SettingsRow(
          icon: YIcons.download,
          tile: TileColor.teal,
          title: '下载音质',
          value: s.downloadQuality.label,
          onTap: () async {
            final q = await showOptions<AudioQuality>(
              context,
              title: '下载音质',
              selected: s.downloadQuality,
              options: [for (final q in AudioQuality.values) (q, q.label)],
            );
            if (q != null) s.setDownloadQuality(q);
          },
        ),
        clear,
      ],
    );
  }
}

class _ShortcutsGroup extends StatelessWidget {
  const _ShortcutsGroup();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget key(String k) => Container(
      constraints: const BoxConstraints(minWidth: 26),
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: CustomPaint(
        foregroundPainter: InsetShadowPainter(BorderRadius.circular(8), const [Shadow2(0, -1, 0, Color.fromRGBO(60, 60, 67, 0.18))]),
        child: Text(
          k,
          style: ts(12, weight: w600, color: p.text3),
        ),
      ),
    );
    Widget row(String label, List<String> keys) => SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: ts(15, color: p.text)),
            ),
            for (var i = 0; i < keys.length; i++) ...[if (i > 0) const SizedBox(width: 6), key(keys[i])],
          ],
        ),
      ),
    );
    return CardList(
      indent: 14,
      children: [
        row('播放 / 暂停', ['空格']),
        row('上一首', ['Ctrl', '←']),
        row('下一首', ['Ctrl', '→']),
        row('音量增减', ['Ctrl', '↑ / ↓']),
        row('搜索', ['Ctrl', 'F']),
        row('迷你模式', ['Ctrl', 'M']),
        row('桌面歌词', ['Ctrl', 'L']),
      ],
    );
  }
}

class _DesktopSettings extends StatelessWidget {
  const _DesktopSettings();

  @override
  Widget build(BuildContext context) {
    return DesktopPage(
      children: [
        const PageTitle('设置', size: 40),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const GroupLabel('设置', top: 14),
                  const SettingsEntries(),
                  const GroupLabel('关于'),
                  const AboutEntry(),
                ],
              ),
            ),
            const SizedBox(width: 24),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [GroupLabel('快捷键', top: 14), _ShortcutsGroup()]),
            ),
          ],
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
