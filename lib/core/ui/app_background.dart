import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../player/player_controller.dart';
import '../settings.dart';
import '../theme/cover_colors.dart';
import '../theme/palette.dart';
import 'glow_background.dart';

/// 界面背景：默认光晕、正在播放歌曲的封面取色，或用户选择的图片。
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, this.scale = 1, this.child});

  final double scale;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppSettings, BackgroundMode>((s) => s.background);
    final Widget bg = switch (mode) {
      BackgroundMode.glow => _Glow(scale: scale),
      BackgroundMode.cover => _CoverBackground(scale: scale),
      BackgroundMode.image => const _ImageBackground(),
    };
    if (child == null) return bg;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: bg),
        child!,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GlowBackground(color: p.bg, glows: p.glows, scale: scale);
  }
}

/// 封面取色背景：底色与三团光晕取自当前歌曲封面，切歌时平滑过渡；没有歌曲时使用默认光晕。
class _CoverBackground extends StatefulWidget {
  const _CoverBackground({required this.scale});

  final double scale;

  @override
  State<_CoverBackground> createState() => _CoverBackgroundState();
}

class _CoverBackgroundState extends State<_CoverBackground> {
  String? _url;
  CoverColors? _colors;

  Future<void> _load(String? url) async {
    _url = url;
    final c = await CoverColors.of(url);
    if (mounted && _url == url) setState(() => _colors = c);
  }

  @override
  Widget build(BuildContext context) {
    final cover = context.select<PlayerController, String?>((p) => p.current?.coverUrl);
    if (cover != _url) _load(cover);
    final p = Palette.of(context);
    final c = _colors;
    final (Color bg, List<Glow> glows) = c == null ? (p.bg, p.glows) : c.page(p.isDark);
    return TweenAnimationBuilder<double>(
      key: ValueKey(bg),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, t, _) {
        final from = _from ?? (bg, glows);
        if (t >= 1) _from = (bg, glows);
        return GlowBackground(
          color: Color.lerp(from.$1, bg, t)!,
          glows: [
            for (var i = 0; i < glows.length; i++)
              Glow(glows[i].cx, glows[i].cy, glows[i].rx, glows[i].ry, Color.lerp(i < from.$2.length ? from.$2[i].color : glows[i].color, glows[i].color, t)!),
          ],
          scale: widget.scale,
        );
      },
    );
  }

  (Color, List<Glow>)? _from;
}

/// 自定义图片背景：铺满并加一层与主题对应的蒙版，保证文字清晰；可选模糊。
class _ImageBackground extends StatelessWidget {
  const _ImageBackground();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.watch<AppSettings>();
    final path = s.backgroundImage;
    if (path == null || !File(path).existsSync()) return GlowBackground(color: p.bg, glows: p.glows);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = (MediaQuery.sizeOf(context).longestSide * dpr).round();
    Widget image = Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: s.backgroundBlur ? (width / 4).round() : width,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => GlowBackground(color: p.bg, glows: p.glows),
    );
    if (s.backgroundBlur) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24, tileMode: TileMode.clamp),
        child: image,
      );
    }
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: p.bg),
          image,
          ColoredBox(color: p.isDark ? const Color.fromRGBO(0, 0, 0, 0.45) : const Color.fromRGBO(255, 255, 255, 0.5)),
        ],
      ),
    );
  }
}

/// 选择背景图片并复制到应用数据目录，返回是否已设置。
Future<bool> pickBackgroundImage(AppSettings settings) async {
  final picked = await FilePicker.pickFiles(dialogTitle: '选择背景图片', type: FileType.image);
  final src = picked.isEmpty ? null : picked.first.path;
  if (src == null) return false;
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/background');
  await dir.create(recursive: true);
  final ext = src.contains('.') ? src.substring(src.lastIndexOf('.')) : '.jpg';
  final dest = '${dir.path}/bg_${DateTime.now().millisecondsSinceEpoch}$ext';
  await File(src).copy(dest);
  // 删除旧图片。
  for (final f in dir.listSync().whereType<File>()) {
    if (f.path != dest) await f.delete();
  }
  settings.setBackground(BackgroundMode.image, image: dest);
  return true;
}
