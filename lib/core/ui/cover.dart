import 'dart:io';
import 'dart:ui' as ui;

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
  const CoverImage(this.url, {super.key, this.imageSize = 400, this.radius});

  final String? url;
  final int imageSize;

  /// 指定时把图片直接画成抗锯齿的圆角矩形（见 [kSoftClip]），由 [YBox] 在需要时设置。
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final u = url;
    final r = radius;
    if (u == null || u.isEmpty) return r == null ? const _Placeholder() : SoftClipRRect(radius: r, child: const _Placeholder());
    if (r != null) {
      final ImageProvider provider = isLocalPath(u)
          ? ResizeImage(FileImage(File(u.startsWith('file://') ? Uri.parse(u).toFilePath() : u)), width: imageSize, policy: ResizeImagePolicy.fit)
          : CachedNetworkImageProvider(_sized(u, imageSize), maxWidth: _px(imageSize));
      return _ShapedImage(provider: provider, radius: r);
    }
    if (isLocalPath(u)) {
      return Image.file(
        File(u.startsWith('file://') ? Uri.parse(u).toFilePath() : u),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: imageSize,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const _Placeholder(),
      );
    }
    final px = _px(imageSize);
    return CachedNetworkImage(
      imageUrl: _sized(u, imageSize),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: px,
      // 已在内存中的图片直接显示；切换地址（换歌）时保留旧图直到新图就绪，避免闪成灰色占位。
      fadeInDuration: const Duration(milliseconds: 140),
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (_, _) => const _Placeholder(),
      errorWidget: (_, _, _) => const _Placeholder(),
    );
  }
}

/// 模糊的封面 / 图片背景：图片加载后按显示尺寸的四分之一预先模糊一次，之后每帧只画这张小图（放大后与实时模糊看起来一样）。
/// 实时的 ImageFiltered 在 Impeller 上每一帧都要重新模糊整块区域，滚动时开销很大。
/// [scale] 为模糊前的放大倍数（让模糊后的边缘仍然铺满），[sigma] 为显示尺寸下的模糊半径。
class BlurredImage extends StatefulWidget {
  const BlurredImage({super.key, required this.url, this.sigma = 28, this.scale = 1.3, this.imageSize = 240});

  final String? url;
  final double sigma;
  final double scale;
  final int imageSize;

  @override
  State<BlurredImage> createState() => _BlurredImageState();
}

class _BlurredImageState extends State<BlurredImage> {
  ImageStream? _stream;
  ui.Image? _source;
  ui.Image? _blurred;
  Size? _builtFor;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    if (!mounted) return;
    setState(() {
      _source?.dispose();
      _source = info.image.clone();
      _clearBlurred();
    });
    info.dispose();
  }, onError: (_, _) {});

  void _clearBlurred() {
    _blurred?.dispose();
    _blurred = null;
    _builtFor = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(BlurredImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.imageSize != widget.imageSize) _resolve();
    if (old.sigma != widget.sigma || old.scale != widget.scale) _clearBlurred();
  }

  void _resolve() {
    final u = widget.url;
    if (u == null || u.isEmpty) return;
    final ImageProvider provider = isLocalPath(u)
        ? ResizeImage(FileImage(File(u.startsWith('file://') ? Uri.parse(u).toFilePath() : u)), width: widget.imageSize, policy: ResizeImagePolicy.fit)
        : CachedNetworkImageProvider(_sized(u, widget.imageSize), maxWidth: _px(widget.imageSize));
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  /// 在显示尺寸的 1/4 上画出放大并模糊后的图片。
  ui.Image _render(ui.Image src, Size size) {
    const k = 0.25;
    final w = (size.width * k).ceil().clamp(1, 2048), h = (size.height * k).ceil().clamp(1, 2048);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final iw = src.width.toDouble(), ih = src.height.toDouble();
    final cover = (w / iw > h / ih ? w / iw : h / ih) * widget.scale;
    final dst = Rect.fromCenter(center: Offset(w / 2, h / 2), width: iw * cover, height: ih * cover);
    final sigma = widget.sigma * k;
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
    );
    canvas.drawImageRect(src, Rect.fromLTWH(0, 0, iw, ih), dst, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    return image;
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _source?.dispose();
    _blurred?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final src = _source;
        final size = c.biggest;
        if (src == null || size.isEmpty || !size.isFinite) return const SizedBox.expand();
        if (_blurred == null || _builtFor != size) {
          _blurred?.dispose();
          _blurred = _render(src, size);
          _builtFor = size;
        }
        return RawImage(image: _blurred, fit: BoxFit.fill, width: size.width, height: size.height, filterQuality: FilterQuality.medium);
      },
    );
  }
}

/// 网易云图片服务按 param 返回对应尺寸的缩略图；取 50 的倍数以提高缓存命中率。
int _px(int imageSize) => ((imageSize / 50).ceil() * 50).clamp(50, 1200);

String _sized(String u, int imageSize) {
  final px = _px(imageSize);
  // 早先缓存的网易云地址可能带有缩成 140×140 的处理参数：去掉后按显示尺寸请求。
  final base = u.contains('music.126.net') && u.contains('thumbnail=') ? u.substring(0, u.indexOf('?')) : u;
  return base.contains('music.126.net') && !base.contains('?') ? '$base?param=${px}y$px' : base;
}

/// 把图片按 cover 方式画进抗锯齿的圆角矩形（图片着色器 + 圆角矩形几何，不用裁剪）。加载前与失败时显示占位图。
class _ShapedImage extends StatefulWidget {
  const _ShapedImage({required this.provider, required this.radius});

  final ImageProvider provider;
  final BorderRadius radius;

  @override
  State<_ShapedImage> createState() => _ShapedImageState();
}

class _ShapedImageState extends State<_ShapedImage> with SingleTickerProviderStateMixin {
  ImageStream? _stream;
  ImageInfo? _info;
  // 加载失败时保持占位图。
  late final ImageStreamListener _listener = ImageStreamListener(_onImage, onError: (_, _) {});
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_ShapedImage old) {
    super.didUpdateWidget(old);
    if (old.provider != widget.provider) _resolve();
  }

  void _resolve() {
    final stream = widget.provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool sync) {
    if (!mounted) {
      info.dispose();
      return;
    }
    final first = _info == null;
    setState(() {
      _info?.dispose();
      _info = info;
    });
    // 已在内存中的图片直接显示；新加载的图片淡入。换图时不再淡入（保留旧图直到新图就绪）。
    if (sync || !first) {
      _fade.value = 1;
    } else {
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final placeholder = SoftClipRRect(radius: widget.radius, child: const _Placeholder());
    if (info == null) return placeholder;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_fade.value < 1) placeholder,
        AnimatedBuilder(
          animation: _fade,
          builder: (context, _) => CustomPaint(painter: _ShapedImagePainter(info.image, widget.radius, _fade.value)),
        ),
      ],
    );
  }
}

class _ShapedImagePainter extends CustomPainter {
  _ShapedImagePainter(this.image, this.radius, this.opacity);

  final ui.Image image;
  final BorderRadius radius;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    // BoxFit.cover：等比放大到铺满，居中裁去多余部分。
    final scale = size.width / iw > size.height / ih ? size.width / iw : size.height / ih;
    final dx = (size.width - iw * scale) / 2, dy = (size.height - ih * scale) / 2;
    final matrix = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, opacity)
      ..shader = ImageShader(image, TileMode.clamp, TileMode.clamp, matrix.storage, filterQuality: FilterQuality.medium);
    canvas.drawRRect(radius.toRRect(Offset.zero & size), paint);
  }

  @override
  bool shouldRepaint(_ShapedImagePainter old) => old.image != image || old.radius != radius || old.opacity != opacity;
}

/// 没有封面（或封面加载失败）时的占位图：柔和的渐变底色上一个音符图标，而不是一块空白。
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final side = c.biggest.shortestSide.isFinite ? c.biggest.shortestSide : 48.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [p.skeleton, Color.alphaBlend(p.accentText.withValues(alpha: 0.10), p.skeleton)],
            ),
          ),
          child: SizedBox.expand(
            child: side < 18
                ? null
                : Center(
                    child: YIcon(YIcons.note, size: (side * 0.38).clamp(10, 96).toDouble(), color: p.text2.withValues(alpha: 0.55)),
                  ),
          ),
        );
      },
    );
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

/// 本地文件路径（导入的本地音乐封面）。
bool isLocalPath(String u) => u.startsWith('/') || u.startsWith('file://') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(u);

/// 把平台封面地址换成大尺寸版本（沉浸式页头整屏显示时使用）：QQ 音乐 T00xR300x300 → 800，
/// QQ 音乐歌单封面 /300 → /600，酷狗 /400/ → /800/。其他地址原样返回（网易云按 imageSize 请求）。
String hiResCover(String url) {
  if (url.contains('y.gtimg.cn')) return url.replaceFirstMapped(RegExp(r'T00(\d)R\d+x\d+'), (m) => 'T00${m[1]}R800x800');
  if (url.contains('qpic.y.qq.com')) return url.replaceFirst(RegExp(r'/(150|300)(\?|$)'), '/600\$2');
  if (url.contains('kugou.com') || url.contains('kgimg.com')) return url.replaceFirst(RegExp(r'/(150|240|400|480)/'), '/800/');
  return url;
}
