import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/palette.dart';
import 'box.dart';
import 'icons.dart';

/// 封面投影的色调（设计稿中播放页封面使用青绿色彩色投影）。
abstract final class CoverArt {
  static Color tint(String? url) => const Color.fromRGBO(31, 133, 118, 1);
}

/// 网络封面。按显示尺寸请求缩略图并按该尺寸解码，避免大图解码拖慢滚动。
class Cover extends StatelessWidget {
  const Cover(this.url, {super.key, required this.size, this.radius = 10, this.shadows = const [], this.circle = false, this.imageSize});

  final String? url;
  final double size;
  final double radius;
  final List<Shadow2> shadows;
  final bool circle;

  /// 网络图片请求尺寸（像素）。默认按设备像素比计算。
  final int? imageSize;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(circle ? size / 2 : radius);
    final px = imageSize ?? (size * MediaQuery.devicePixelRatioOf(context)).round();
    return YBox(
      clip: true,
      width: size,
      height: size,
      radius: r,
      shadows: shadows,
      child: CoverImage(url, imageSize: px),
    );
  }
}

/// 填满父级的封面图像本体。
class CoverImage extends StatelessWidget {
  const CoverImage(this.url, {super.key, this.imageSize = 400});

  final String? url;
  final int imageSize;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return const _Placeholder();
    // 网易云图片服务按 param 返回对应尺寸的缩略图；取 50 的倍数以提高缓存命中率。
    final px = ((imageSize / 50).ceil() * 50).clamp(50, 1200);
    final sized = u.contains('music.126.net') && !u.contains('?') ? '$u?param=${px}y$px' : u;
    return CachedNetworkImage(
      imageUrl: sized,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: px,
      fadeInDuration: const Duration(milliseconds: 160),
      placeholder: (_, _) => const _Placeholder(),
      errorWidget: (_, _, _) => const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Palette.of(context).skeleton, child: const SizedBox.expand());
  }
}

/// 用户头像；没有头像时显示通用的人像图标。
class Avatar extends StatelessWidget {
  const Avatar(this.url, {super.key, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) return Cover(url, size: size, circle: true);
    final p = Palette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: p.skeleton),
      alignment: Alignment.center,
      child: YIcon(YIcons.user, size: size * 0.55, color: p.text2),
    );
  }
}
