import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/downloads.dart';
import '../../data/models.dart';
import '../../data/sources/music_source.dart';
import '../../data/sources/source_manager.dart';
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
      children: const [
        PageTitle('设置'),
        SizedBox(height: 16),
        AccountCard(),
        GroupLabel('播放'),
        PlaybackGroup(),
        GroupLabel('外观'),
        AppearanceEntry(),
        GroupLabel('播放源'),
        SourceGroup(),
        GroupLabel('下载与缓存'),
        StorageGroup(),
      ],
    );
  }
}

/// 账号卡片（头像 56 + 昵称）。
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final source = context.watch<SourceManager>().current;
    final user = source.user;
    return Pressable(
      onTap: () => go(context, user == null && source.supports(SourceFeature.login) ? LoginRoute() : SettingsMoreRoute()),
      child: YCard(
        child: SizedBox(
          height: 80,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
            child: Row(
              children: [
                Avatar(user?.avatar, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.nickname ?? '未登录',
                        style: ts(18, weight: w600, color: p.text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(user == null ? '登录${source.name}账号' : '账号与安全', style: ts(13, color: p.text2)),
                    ],
                  ),
                ),
                const YIcon(YIcons.chevronRight, size: 16, color: Color(0xFF8E8E93)),
              ],
            ),
          ),
        ),
      ),
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
          icon: YIcons.volume,
          tile: TileColor.graphite,
          title: '音量均衡',
          trailing: YSwitch(value: s.normalize, label: '音量均衡', onChanged: (v) => s.setFlag('normalize', v)),
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

/// 设置首页里的“外观”入口，进入二级页面。
class AppearanceEntry extends StatelessWidget {
  const AppearanceEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final mode = switch (s.themeMode) {
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
      ThemeMode.system => '跟随系统',
    };
    return CardList(
      indent: 56,
      children: [
        SettingsRow(
          icon: YIcons.sparkle,
          tile: TileColor.values[s.accent.index],
          title: '外观',
          value: '$mode · ${s.accent.label}',
          onTap: () => go(context, AppearanceRoute()),
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

class SourceGroup extends StatelessWidget {
  const SourceGroup({super.key});

  @override
  Widget build(BuildContext context) {
    final sm = context.watch<SourceManager>();
    return CardList(
      indent: 56,
      children: [SettingsRow(icon: YIcons.source, tile: TileColor.red, title: '播放源', value: sm.current.name, onTap: () => pickSource(context))],
    );
  }
}

Future<void> pickSource(BuildContext context) async {
  final sm = context.read<SourceManager>();
  final id = await showOptions<String>(
    context,
    title: '选择播放源',
    selected: sm.current.id,
    options: [for (final s in sm.selectable) (s.id, '${s.name}  ·  ${s.description}')],
  );
  if (id == null || !context.mounted) return;
  await sm.select(id);
  if (context.mounted) Toast.show(context, '已切换到${sm.current.name}');
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
          SettingsRow(
            icon: YIcons.refresh,
            tile: TileColor.teal,
            title: '自动清理',
            trailing: YSwitch(value: s.autoClean, label: '自动清理', onChanged: (v) => s.setFlag('autoClean', v)),
          ),
        ],
      );
    }
    return CardList(
      indent: 56,
      children: [
        SettingsRow(
          icon: YIcons.wifi,
          tile: TileColor.blue,
          title: '仅 Wi-Fi 下载',
          trailing: YSwitch(value: s.wifiOnlyDownload, label: '仅 Wi-Fi 下载', onChanged: (v) => s.setFlag('wifiOnlyDownload', v)),
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
                  const GroupLabel('播放', top: 14),
                  const PlaybackGroup(desktop: true),
                  const GroupLabel('外观'),
                  const AppearanceEntry(),
                  const GroupLabel('账号与播放源'),
                  const SourceGroup(),
                  const SizedBox(height: 12),
                  const AccountCard(),
                ],
              ),
            ),
            const SizedBox(width: 24),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [GroupLabel('快捷键', top: 14), _ShortcutsGroup(), GroupLabel('下载与缓存'), StorageGroup(desktop: true)],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
