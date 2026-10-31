import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/app_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../common/layout.dart';
import '../shell/nav.dart';
import 'settings_page.dart';

/// 外观设置（二级页面）。
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.watch<AppSettings>();
    final desktop = LayoutScope.isDesktop(context);
    const scales = [0.85, 1.0, 1.15];
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
        PageTitle('外观', size: desktop ? 40 : 36),
        const SizedBox(height: 8),
        // 图标预览：跟随主题色时与系统中的应用图标一致。
        YCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                const AppLogo(size: 64, gradient: true),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '应用图标',
                        style: ts(17, weight: w600, color: p.text),
                      ),
                      const SizedBox(height: 3),
                      Text(s.iconFollowsAccent ? '跟随主题色：${s.accent.label}' : '固定为朱红', style: ts(13, color: p.text2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const GroupLabel('主题'),
        AppearanceGroup(desktop: desktop),
        const GroupLabel('液态玻璃'),
        CardList(
          indent: 14,
          children: [
            SettingsRow(
              title: '液态玻璃效果',
              trailing: YSwitch(value: s.glass, label: '液态玻璃效果', onChanged: (v) => s.setFlag('glass', v)),
            ),
            if (s.glass)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Segmented(
                      labels: [for (final m in GlassMaterial.values) m.label],
                      index: s.glassMaterial.index,
                      onChanged: (i) => s.setGlassMaterial(GlassMaterial.values[i]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.glassMaterial == GlassMaterial.clear ? '清透：几乎不模糊，边缘折射与高光最明显。' : '柔和：轻度模糊并带一层白色色调，文字更易阅读。',
                      style: ts(13, height: 1.45, color: p.text2),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const GroupLabel('界面背景'),
        CardList(
          indent: 14,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Segmented(
                labels: [for (final m in BackgroundMode.values) m.label],
                index: s.background.index,
                onChanged: (i) async {
                  final mode = BackgroundMode.values[i];
                  if (mode == BackgroundMode.image && s.backgroundImage == null) {
                    await pickBackgroundImage(s);
                  } else {
                    s.setBackground(mode);
                  }
                },
              ),
            ),
            if (s.background == BackgroundMode.cover)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Text('界面底色与光晕取自正在播放歌曲的封面，切歌时平滑过渡。', style: ts(13, height: 1.45, color: p.text2)),
              ),
            if (s.background == BackgroundMode.image) ...[
              SettingsRow(title: '更换图片', value: '从相册或文件选择', onTap: () => pickBackgroundImage(s)),
              SettingsRow(
                title: '背景模糊',
                trailing: YSwitch(value: s.backgroundBlur, label: '背景模糊', onChanged: (v) => s.setFlag('backgroundBlur', v)),
              ),
            ],
          ],
        ),
        const GroupLabel('播放样式'),
        YCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Row(
              children: [
                for (final st in PlayerStyle.values)
                  Expanded(
                    child: _StyleTile(style: st, selected: s.playerStyle == st, onTap: () => s.setPlayerStyle(st)),
                  ),
              ],
            ),
          ),
        ),
        const GroupLabel('图标与播放页'),
        CardList(
          indent: 56,
          children: [
            SettingsRow(
              icon: YIcons.sparkle,
              tile: TileColor.values[s.accent.index],
              title: '应用图标跟随主题色',
              trailing: YSwitch(value: s.iconFollowsAccent, label: '应用图标跟随主题色', onChanged: (v) => s.setFlag('iconFollowsAccent', v)),
            ),
            SettingsRow(
              icon: YIcons.target,
              tile: TileColor.teal,
              title: '播放页背景跟随封面取色',
              trailing: YSwitch(value: s.coverColors, label: '播放页背景跟随封面取色', onChanged: (v) => s.setFlag('coverColors', v)),
            ),
          ],
        ),
        const GroupLabel('歌词'),
        CardList(
          indent: 14,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Segmented(
                labels: const ['小', '标准', '大'],
                index: scales.indexWhere((x) => (x - s.lyricScale).abs() < 0.01).clamp(0, 2),
                onChanged: (i) => s.setLyricScale(scales[i]),
              ),
            ),
            SettingsRow(
              title: '显示歌词翻译',
              trailing: YSwitch(value: s.showTranslation, label: '显示歌词翻译', onChanged: (v) => s.setFlag('showTranslation', v)),
            ),
          ],
        ),
      ],
    );
  }
}

/// 播放样式预览。
class _StyleTile extends StatelessWidget {
  const _StyleTile({required this.style, required this.selected, required this.onTap});

  final PlayerStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      semanticLabel: '播放样式：${style.label}',
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 64,
            height: 84,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? p.accentText : p.separator, width: selected ? 2 : 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CustomPaint(painter: _StylePreview(style, p.isDark, p.accent.base)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            style.label,
            style: ts(13, weight: selected ? w600 : w500, color: selected ? p.accentText : p.text2),
          ),
        ],
      ),
    );
  }
}

class _StylePreview extends CustomPainter {
  _StylePreview(this.style, this.dark, this.accent);

  final PlayerStyle style;
  final bool dark;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7));
    final art = Rect.fromCenter(center: Offset(w / 2, h * 0.36), width: w * 0.7, height: w * 0.7);
    final cover = Paint()..shader = LinearGradient(colors: [accent, Color.lerp(accent, const Color(0xFFFFD45E), 0.6)!]).createShader(art);
    switch (style) {
      case PlayerStyle.cover:
        canvas.drawRRect(RRect.fromRectAndRadius(art, const Radius.circular(6)), cover);
      case PlayerStyle.vinyl:
        canvas.drawCircle(art.center, art.width / 2, Paint()..color = const Color(0xFF111113));
        for (var i = 1; i < 5; i++) {
          canvas.drawCircle(
            art.center,
            art.width / 2 * (0.5 + i * 0.11),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.6
              ..color = const Color(0x22FFFFFF),
          );
        }
        canvas.drawCircle(art.center, art.width * 0.2, cover);
        canvas.drawLine(
          Offset(art.right + 2, art.top - 2),
          Offset(art.right - 8, art.center.dy),
          Paint()
            ..color = const Color(0xFFC7C7CC)
            ..strokeWidth = 2,
        );
      case PlayerStyle.disc:
        canvas.drawCircle(art.center, art.width / 2, cover);
        canvas.drawCircle(
          art.center,
          art.width / 2,
          Paint()..shader = const SweepGradient(colors: [Color(0x00FFFFFF), Color(0x66B78CFF), Color(0x665AA9F0), Color(0x00FFFFFF)]).createShader(art),
        );
        canvas.drawCircle(art.center, art.width * 0.12, Paint()..color = dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7));
      case PlayerStyle.immersive:
        final top = Rect.fromLTWH(0, 0, w, h * 0.58);
        canvas.drawRect(top, cover);
        canvas.drawRect(
          top,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7)],
              stops: const [0.55, 1],
            ).createShader(top),
        );
    }
    // 歌名与进度条示意。
    final line = Paint()..color = dark ? const Color(0x66FFFFFF) : const Color(0x33000000);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.15, h * 0.74, w * 0.5, 3), const Radius.circular(2)), line);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.15, h * 0.84, w * 0.7, 2), const Radius.circular(1)), line);
  }

  @override
  bool shouldRepaint(_StylePreview old) => old.style != style || old.dark != dark || old.accent != accent;
}
