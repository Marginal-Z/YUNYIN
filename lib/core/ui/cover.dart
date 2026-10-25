import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/palette.dart';
import 'box.dart';

/// 演示数据使用的插画封面（来自设计稿）。地址形如 `art:teal`。
abstract final class CoverArt {
  static const _art = <String, String>{
    'teal': '<rect width="100" height="100" fill="#3BB7A5"/><circle cx="50" cy="58" r="24" fill="#FFD45E"/>'
        '<rect y="58" width="100" height="42" fill="#1F8576"/>',
    'tealLarge': '<rect width="100" height="100" fill="#3BB7A5"/><circle cx="50" cy="58" r="24" fill="#FFD45E"/>'
        '<rect y="58" width="100" height="42" fill="#1F8576"/><rect x="18" y="70" width="64" height="2.4" rx="1.2" fill="#3BB7A5"/>'
        '<rect x="28" y="78" width="44" height="2.4" rx="1.2" fill="#3BB7A5"/>',
    'coral': '<rect width="100" height="100" fill="#FF6A57"/><circle cx="50" cy="50" r="27" fill="none" stroke="#FFF4E8" stroke-width="7"/>'
        '<circle cx="50" cy="50" r="8" fill="#1D1D1F"/>',
    'sage': '<rect width="100" height="100" fill="#A9C7A0"/><rect x="24" y="24" width="52" height="52" rx="4" fill="#F7F3EA" transform="rotate(45 50 50)"/>'
        '<circle cx="50" cy="50" r="12" fill="#A9C7A0"/>',
    'dots': '<rect width="100" height="100" fill="#FFD45E"/><circle cx="50" cy="26" r="8" fill="#1D1D1F"/><circle cx="26" cy="50" r="8" fill="#1D1D1F"/>'
        '<circle cx="74" cy="50" r="8" fill="#1D1D1F"/><circle cx="50" cy="74" r="8" fill="#1D1D1F"/><circle cx="50" cy="50" r="11" fill="#FF6A57"/>',
    'arch': '<rect width="100" height="100" fill="#5AA9F0"/><path d="M28 100V50a22 22 0 0 1 44 0V100Z" fill="#F7F3EA"/>'
        '<circle cx="50" cy="48" r="9" fill="#FFC83D"/>',
    'moon': '<rect width="100" height="100" fill="#1D1D1F"/><circle cx="50" cy="50" r="30" fill="#FFD45E"/><circle cx="60" cy="44" r="28" fill="#1D1D1F"/>'
        '<circle cx="78" cy="24" r="3" fill="#F7F3EA"/>',
    'stripes': '<rect width="100" height="100" fill="#F2E8D5"/><rect x="12" width="10" height="100" fill="#1D1D1F"/>'
        '<rect x="28" width="4" height="100" fill="#1D1D1F"/><rect x="38" width="4" height="100" fill="#1D1D1F"/>'
        '<circle cx="68" cy="50" r="16" fill="#FF6A57"/>',
    'avatarCoral': '<rect width="100" height="100" fill="#FF6A57"/><circle cx="50" cy="40" r="15" fill="#FFF4E8"/>'
        '<path d="M20 100a30 30 0 0 1 60 0z" fill="#FFF4E8"/>',
    'avatarBlue': '<rect width="100" height="100" fill="#5AA9F0"/><circle cx="50" cy="40" r="15" fill="#F7F3EA"/>'
        '<path d="M20 100a30 30 0 0 1 60 0z" fill="#F7F3EA"/>',
    'avatarYellow': '<rect width="100" height="100" fill="#FFD45E"/><circle cx="50" cy="40" r="15" fill="#1D1D1F"/>'
        '<path d="M20 100a30 30 0 0 1 60 0z" fill="#1D1D1F"/>',
    'avatarTeal': '<rect width="100" height="100" fill="#3BB7A5"/><circle cx="50" cy="40" r="15" fill="#E8FAF6"/>'
        '<path d="M20 100a30 30 0 0 1 60 0z" fill="#E8FAF6"/>',
  };

  static const _shadowTint = <String, Color>{
    'teal': Color.fromRGBO(31, 133, 118, 1),
    'tealLarge': Color.fromRGBO(31, 133, 118, 1),
  };

  static String? svg(String key) {
    final body = _art[key];
    if (body == null) return null;
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">$body</svg>';
  }

  /// 封面主色调，用于彩色投影（如播放页封面的青绿投影）。
  static Color tint(String? url) {
    if (url != null && url.startsWith('art:')) {
      return _shadowTint[url.substring(4)] ?? const Color.fromRGBO(28, 44, 92, 1);
    }
    return const Color.fromRGBO(31, 133, 118, 1);
  }
}

/// 封面：支持 `art:` 插画、网络图片与本地占位。
class Cover extends StatelessWidget {
  const Cover(
    this.url, {
    super.key,
    required this.size,
    this.radius = 10,
    this.shadows = const [],
    this.circle = false,
    this.imageSize,
  });

  final String? url;
  final double size;
  final double radius;
  final List<Shadow2> shadows;
  final bool circle;

  /// 网络图片请求尺寸（像素），用于网易云 `?param=` 缩略图。
  final int? imageSize;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(circle ? size / 2 : radius);
    // 大尺寸时使用带细节的插画（设计稿播放页封面）。
    final u = url == 'art:teal' && size >= 200 ? 'art:tealLarge' : url;
    return YBox(
      width: size,
      height: size,
      radius: r,
      shadows: shadows,
      child: CoverImage(u, imageSize: imageSize ?? (size * 3).round()),
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
    if (u != null && u.startsWith('art:')) {
      final svg = CoverArt.svg(u.substring(4));
      if (svg != null) {
        return SvgPicture.string(svg, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
      }
    }
    if (u == null || u.isEmpty) return const _Placeholder();
    final sized = u.contains('music.126.net') && !u.contains('?') ? '$u?param=${imageSize}y$imageSize' : u;
    return CachedNetworkImage(
      imageUrl: sized,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: const Duration(milliseconds: 180),
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
