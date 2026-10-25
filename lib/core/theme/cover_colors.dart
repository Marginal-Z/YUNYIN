import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings.dart';
import '../ui/cover.dart';
import '../../player/player_controller.dart';
import 'palette.dart';

/// 从封面提取的三种颜色。
@immutable
class CoverColors {
  const CoverColors(this.dominant, this.vibrant, this.secondary);

  /// 面积最大的颜色。
  final Color dominant;

  /// 面积与饱和度综合最高的颜色。
  final Color vibrant;

  /// 与 [vibrant] 色相相差较大的颜色，用作第二团光晕。
  final Color secondary;

  static final _cache = <String, CoverColors>{};

  /// 读取 48×48 的缩略图并做颜色量化。结果按封面地址缓存。
  static Future<CoverColors?> of(String? url) async {
    if (url == null || url.isEmpty) return null;
    final cached = _cache.remove(url);
    if (cached != null) return _cache[url] = cached;
    try {
      final ImageProvider base = isLocalPath(url)
          ? FileImage(File(url.startsWith('file://') ? Uri.parse(url).toFilePath() : url))
          : CachedNetworkImageProvider(url.contains('music.126.net') && !url.contains('?') ? '$url?param=100y100' : url);
      final image = await _resolve(ResizeImage(base, width: 48, height: 48));
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final c = _extract(data.buffer.asUint8List());
      _cache[url] = c;
      if (_cache.length > 64) _cache.remove(_cache.keys.first);
      return c;
    } catch (e) {
      debugPrint('cover colors: $e');
      return null;
    }
  }

  static Future<ui.Image> _resolve(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (e, st) {
        completer.completeError(e, st);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(const Duration(seconds: 10));
  }

  static CoverColors _extract(List<int> rgba) {
    // 每通道取高 4 位做直方图量化。
    final count = <int, int>{}, sr = <int, int>{}, sg = <int, int>{}, sb = <int, int>{};
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 128) continue;
      final key = (rgba[i] >> 4) << 8 | (rgba[i + 1] >> 4) << 4 | (rgba[i + 2] >> 4);
      count[key] = (count[key] ?? 0) + 1;
      sr[key] = (sr[key] ?? 0) + rgba[i];
      sg[key] = (sg[key] ?? 0) + rgba[i + 1];
      sb[key] = (sb[key] ?? 0) + rgba[i + 2];
    }
    if (count.isEmpty) return const CoverColors(Color(0xFF3BB7A5), Color(0xFF3BB7A5), Color(0xFFFFD45E));
    final buckets = [for (final k in count.keys) (Color.fromARGB(255, sr[k]! ~/ count[k]!, sg[k]! ~/ count[k]!, sb[k]! ~/ count[k]!), count[k]!)]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final dominant = buckets.first.$1;
    double score((Color, int) b) {
      final h = HSLColor.fromColor(b.$1);
      final mid = 1 - (h.lightness - 0.5).abs() * 1.6;
      return b.$2 * (h.saturation * h.saturation + 0.04) * math.max(mid, 0.05);
    }

    final vibrant = buckets.reduce((a, b) => score(a) >= score(b) ? a : b).$1;
    final vh = HSLColor.fromColor(vibrant).hue;
    (Color, int)? second;
    for (final b in buckets) {
      final h = HSLColor.fromColor(b.$1);
      final d = (h.hue - vh).abs();
      if (math.min(d, 360 - d) > 40 && h.saturation > 0.15 && (second == null || score(b) > score(second))) second = b;
    }
    return CoverColors(dominant, vibrant, second?.$1 ?? Color.lerp(vibrant, dominant, 0.5)!);
  }

  /// 生成播放页的配色：浅色模式为柔和的浅色底，深色模式为深色底；文字颜色保证对比度。
  Palette apply(Palette p) {
    final v = HSLColor.fromColor(vibrant);
    final hue = v.hue;
    final sat = v.saturation.clamp(0.0, 0.6);
    Color hsl(double s, double l) => HSLColor.fromAHSL(1, hue, s, l).toColor();
    if (p.isDark) {
      return p.withPlayer(
        playerBg: Color.lerp(dominant, Colors.black, 0.86)!,
        playerGlows: [
          Glow(0.08, 0, 380, 320, vibrant.withValues(alpha: 0.40)),
          Glow(1, 0.08, 340, 300, secondary.withValues(alpha: 0.20)),
          Glow(0.5, 1, 420, 380, Color.lerp(vibrant, dominant, 0.5)!.withValues(alpha: 0.26)),
        ],
        playerText2: hsl(sat * 0.6, 0.78),
        lyricDim: hsl(sat * 0.4, 0.62),
        lyricActive: hsl(sat * 0.3, 0.97),
      );
    }
    return p.withPlayer(
      playerBg: Color.lerp(dominant, Colors.white, 0.86)!,
      playerGlows: [
        Glow(0.08, 0, 380, 320, vibrant.withValues(alpha: 0.38)),
        Glow(1, 0.08, 340, 300, secondary.withValues(alpha: 0.34)),
        Glow(0.5, 1, 420, 380, Color.lerp(vibrant, dominant, 0.5)!.withValues(alpha: 0.24)),
      ],
      playerText2: hsl(sat * 0.7, 0.27),
      lyricDim: hsl(sat * 0.45, 0.36),
      lyricActive: hsl(sat * 0.4, 0.07),
    );
  }

  /// 封面投影颜色。
  Color get shadow => vibrant;
}

/// 根据封面为子树提供播放页配色，切换歌曲时颜色平滑过渡。
class CoverThemed extends StatefulWidget {
  const CoverThemed({super.key, required this.cover, required this.child});

  final String? cover;
  final Widget child;

  /// 当前封面的投影颜色（在 [CoverThemed] 之下使用）。
  static Color shadowOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_CoverShadow>()?.color ?? const Color.fromRGBO(31, 133, 118, 1);

  @override
  State<CoverThemed> createState() => _CoverThemedState();
}

class _CoverThemedState extends State<CoverThemed> {
  CoverColors? _colors;
  String? _loading;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CoverThemed old) {
    super.didUpdateWidget(old);
    if (old.cover != widget.cover) _load();
  }

  Future<void> _load() async {
    final url = widget.cover;
    _loading = url;
    final c = await CoverColors.of(url);
    if (!mounted || _loading != url) return;
    setState(() => _colors = c);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<AppSettings, bool>((s) => s.coverColors);
    final base = Palette.of(context);
    final target = enabled && _colors != null ? _colors!.apply(base) : base;
    final shadow = enabled && _colors != null ? _colors!.shadow : const Color.fromRGBO(31, 133, 118, 1);
    return TweenAnimationBuilder<double>(
      key: ValueKey(target.playerBg),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      builder: (context, t, child) {
        final from = _previous ?? target;
        final p = t >= 1 ? target : _lerp(from, target, t);
        if (t >= 1) _previous = target;
        return PaletteScope(
          palette: p,
          child: _CoverShadow(color: shadow, child: child!),
        );
      },
      child: widget.child,
    );
  }

  Palette? _previous;

  Palette _lerp(Palette a, Palette b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    final glows = [
      for (var i = 0; i < b.playerGlows.length; i++)
        Glow(
          b.playerGlows[i].cx,
          b.playerGlows[i].cy,
          b.playerGlows[i].rx,
          b.playerGlows[i].ry,
          c(i < a.playerGlows.length ? a.playerGlows[i].color : b.playerGlows[i].color, b.playerGlows[i].color),
        ),
    ];
    return b.withPlayer(
      playerBg: c(a.playerBg, b.playerBg),
      playerGlows: glows,
      playerText2: c(a.playerText2, b.playerText2),
      lyricDim: c(a.lyricDim, b.lyricDim),
      lyricActive: c(a.lyricActive, b.lyricActive),
    );
  }
}

class _CoverShadow extends InheritedWidget {
  const _CoverShadow({required this.color, required super.child});

  final Color color;

  @override
  bool updateShouldNotify(_CoverShadow old) => old.color != color;
}

/// 以当前播放歌曲的封面取色。
class PlayerThemed extends StatelessWidget {
  const PlayerThemed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cover = context.select<PlayerController, String?>((p) => p.current?.coverUrl);
    return CoverThemed(cover: cover, child: child);
  }
}
