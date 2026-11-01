import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/lyrics_overlay.dart';
import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

/// 桌面歌词与状态栏歌词：开关、颜色、不透明度、锁定与状态栏歌词的位置。
class LyricsOverlayPage extends StatelessWidget {
  const LyricsOverlayPage({super.key});

  static bool get _android => !kIsWeb && Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.watch<AppSettings>();
    final desktop = LayoutScope.isDesktop(context);
    final color = s.lyricsDisplayColor;
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
        PageTitle(_android ? '桌面与状态栏歌词' : '桌面歌词', size: desktop ? 40 : 34),
        const SizedBox(height: 14),
        // 预览：深色底板上的当前句与下一句。
        Container(
          height: 92,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [Color(0xFF3B4252), Color(0xFF1E2430)]),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '故事的小黄花',
                style:
                    ts(
                      24,
                      weight: w700,
                      color: color.withValues(alpha: s.lyricsOpacity),
                    ).copyWith(
                      shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1))],
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '从出生那年就飘着',
                style: ts(14, color: Colors.white.withValues(alpha: 0.9 * s.lyricsOpacity)),
              ),
            ],
          ),
        ),
        const GroupLabel('桌面歌词'),
        CardList(
          indent: 14,
          children: [
            SettingsRow(
              title: '桌面歌词',
              value: desktop ? 'Ctrl+L' : null,
              trailing: YSwitch(value: s.desktopLyrics, label: '桌面歌词', onChanged: (v) => overlayFlag(context, 'desktopLyrics', v)),
            ),
            ColorChoiceRow(
              title: '颜色',
              value: s.lyricsColor,
              defaultColor: s.accent.base,
              defaultLabel: '主题',
              onChanged: (c) => s.setLyricsStyle(color: c),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text('不透明度', style: ts(16, color: p.text)),
                  ),
                  Expanded(
                    child: SeekBar(
                      value: (s.lyricsOpacity - 0.3) / 0.7,
                      height: 28,
                      onSeek: (v) => s.setLyricsStyle(opacity: 0.3 + v * 0.7),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${(s.lyricsOpacity * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: ts(14, color: p.text2, tabular: true),
                    ),
                  ),
                ],
              ),
            ),
            if (_android)
              SettingsRow(
                title: '锁定桌面歌词',
                value: s.lyricsLocked ? '点按穿透' : '可拖动位置',
                trailing: YSwitch(value: s.lyricsLocked, label: '锁定桌面歌词', onChanged: (v) => s.setFlag('lyricsLocked', v)),
              ),
          ],
        ),
        if (_android) ...[
          const GroupLabel('状态栏歌词'),
          CardList(
            indent: 14,
            children: [
              SettingsRow(
                title: '状态栏歌词',
                trailing: YSwitch(value: s.statusBarLyrics, label: '状态栏歌词', onChanged: (v) => overlayFlag(context, 'statusBarLyrics', v)),
              ),
              ColorChoiceRow(
                title: '颜色',
                value: s.statusLyricsColor,
                defaultColor: Colors.white,
                defaultLabel: '白色',
                onChanged: (c) => s.setLyricsStyle(statusColor: c),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text('位置', style: ts(16, color: p.text)),
                    ),
                    YIconButton(
                      YIcons.back,
                      size: 32,
                      iconSize: 18,
                      color: p.text2,
                      label: '左移',
                      onTap: () => s.setLyricsStyle(statusOffset: s.statusLyricsOffset - 0.02),
                    ),
                    Expanded(
                      child: SeekBar(
                        value: (s.statusLyricsOffset + 0.4) / 0.8,
                        height: 28,
                        onSeek: (v) => s.setLyricsStyle(statusOffset: v * 0.8 - 0.4),
                      ),
                    ),
                    YIconButton(
                      YIcons.forward,
                      size: 32,
                      iconSize: 18,
                      color: p.text2,
                      label: '右移',
                      onTap: () => s.setLyricsStyle(statusOffset: s.statusLyricsOffset + 0.02),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('左右拖动调整状态栏歌词的位置，避开时间、通知图标与摄像头挖孔。', style: ts(13, height: 1.5, color: p.text2)),
        ],
      ],
    );
  }
}

/// 开启桌面歌词 / 状态栏歌词：Android 需要“显示在其他应用上层”权限，没有时先打开系统设置。
Future<void> overlayFlag(BuildContext context, String key, bool v) async {
  final s = context.read<AppSettings>();
  if (v && !await LyricsOverlay.canDraw()) {
    if (!context.mounted) return;
    final ok = await showConfirm(context, title: '需要悬浮窗权限', message: '桌面歌词与状态栏歌词需要“显示在其他应用上层”权限。在系统设置中允许后，回到云音再打开开关。', confirm: '去设置', destructive: false);
    if (ok) await LyricsOverlay.requestPermission();
    return;
  }
  s.setFlag(key, v);
}

/// 颜色选择：默认色 + 预设色 + 自定义（色相、饱和度、亮度滑块与十六进制）。[value] 为 0 表示默认色。
class ColorChoiceRow extends StatelessWidget {
  const ColorChoiceRow({super.key, required this.title, required this.value, required this.defaultColor, required this.defaultLabel, required this.onChanged});

  final String title;
  final int value;
  final Color defaultColor;
  final String defaultLabel;
  final ValueChanged<int> onChanged;

  static const presets = [0xFFFFFFFF, 0xFFFFD45E, 0xFF5FE3FF, 0xFFFF7EB3, 0xFF7CF29C, 0xFFB794FF, 0xFFFF8A3D];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final custom = value != 0 && !presets.contains(value);
    Widget dot({required Color color, required bool selected, Widget? child, required VoidCallback onTap, required String label}) => Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: selected ? p.text : p.separator, width: selected ? 2.5 : 1),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(title, style: ts(16, color: p.text)),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                dot(
                  color: defaultColor,
                  selected: value == 0,
                  label: defaultLabel,
                  onTap: () => onChanged(0),
                  child: Text(
                    defaultLabel.characters.first,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: defaultColor.computeLuminance() > 0.6 ? Colors.black87 : Colors.white),
                  ),
                ),
                for (final c in presets) dot(color: Color(c), selected: value == c, label: '颜色', onTap: () => onChanged(c)),
                dot(
                  color: custom ? Color(value) : p.field,
                  selected: custom,
                  label: '自定义颜色',
                  onTap: () async {
                    final picked = await pickColor(context, initial: value == 0 ? defaultColor : Color(value));
                    if (picked != null) onChanged(picked.toARGB32());
                  },
                  child: custom ? null : YIcon(YIcons.plus, size: 16, color: p.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 自定义颜色：色相、饱和度与亮度滑块，也可以直接输入十六进制颜色。
Future<Color?> pickColor(BuildContext context, {required Color initial}) {
  var hsl = HSLColor.fromColor(initial);
  String hexOf(Color c) => c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
  final hex = TextEditingController(text: hexOf(initial));
  return showDialog<Color>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final p = Palette.of(ctx);
        final color = hsl.toColor();
        void update(HSLColor v) => setState(() {
          hsl = v;
          hex.text = hexOf(v.toColor());
        });
        Widget slider(String label, double value, ValueChanged<double> onChanged, Gradient gradient) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(label, style: ts(14, color: p.text2)),
              ),
              Expanded(
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: gradient),
                  child: SeekBar(value: value, height: 28, track: Colors.transparent, fill: Colors.white, onSeek: onChanged),
                ),
              ),
            ],
          ),
        );
        return AlertDialog(
          backgroundColor: p.bg,
          title: Text(
            '自定义颜色',
            style: ts(18, weight: w700, color: p.text),
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: const Color(0xFF1E2430)),
                  child: Text(
                    '故事的小黄花',
                    style: ts(22, weight: w700, color: color),
                  ),
                ),
                slider(
                  '色相',
                  hsl.hue / 360,
                  (v) => update(hsl.withHue((v * 360).clamp(0, 360))),
                  LinearGradient(colors: [for (var h = 0; h <= 360; h += 60) HSLColor.fromAHSL(1, h.toDouble(), 1, 0.5).toColor()]),
                ),
                slider(
                  '饱和度',
                  hsl.saturation,
                  (v) => update(hsl.withSaturation(v)),
                  LinearGradient(colors: [hsl.withSaturation(0).toColor(), hsl.withSaturation(1).toColor()]),
                ),
                slider(
                  '亮度',
                  hsl.lightness,
                  (v) => update(hsl.withLightness(v)),
                  LinearGradient(colors: [Colors.black, hsl.withLightness(0.5).toColor(), Colors.white]),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Text('#', style: ts(15, color: p.text2)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: hex,
                          maxLength: 6,
                          style: ts(15, color: p.text),
                          decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, counterText: ''),
                          onChanged: (t) {
                            final v = int.tryParse(t, radix: 16);
                            if (t.length == 6 && v != null) setState(() => hsl = HSLColor.fromColor(Color(0xFF000000 | v)));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(hsl.toColor()), child: const Text('确定')),
          ],
        );
      },
    ),
  );
}
