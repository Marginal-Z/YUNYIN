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

  /// 可选的歌词颜色（0 为跟随主题色）。
  static const _colors = [0, 0xFFFFFFFF, 0xFFFFD45E, 0xFF5FE3FF, 0xFFFF7EB3, 0xFF7CF29C, 0xFFB794FF];

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
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text('颜色', style: ts(16, color: p.text)),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final c in _colors)
                          Pressable(
                            onTap: () => s.setLyricsStyle(color: c),
                            semanticLabel: c == 0 ? '跟随主题色' : '歌词颜色',
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c == 0 ? s.accent.base : Color(c),
                                border: Border.all(color: s.lyricsColor == c ? p.text : p.separator, width: s.lyricsColor == c ? 2.5 : 1),
                              ),
                              alignment: Alignment.center,
                              child: c == 0
                                  ? const Text(
                                      '主题',
                                      style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                                    )
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
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
