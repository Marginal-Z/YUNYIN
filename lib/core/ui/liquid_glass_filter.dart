import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../settings.dart';

/// 液态玻璃着色器（shaders/liquid_glass.frag）。只在 Impeller 下可用，其他渲染后端退回普通毛玻璃。
abstract final class LiquidGlassShader {
  static ui.FragmentProgram? _program;

  static bool get available => _program != null;

  static Future<void> init() async {
    if (kIsWeb || !ui.ImageFilter.isShaderFilterSupported) return;
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
    } catch (e) {
      debugPrint('liquid glass shader: $e');
    }
  }
}

/// 在子组件背后用液态玻璃着色器处理背景。
///
/// 两层背景滤镜：外层先按材质模糊（清透半径 1、柔和半径 16 物理像素，与原版一致），并把背景截取到
/// 玻璃自己的图层里；内层着色器读取这张以玻璃为中心的纹理，因此不依赖玻璃在屏幕上的位置。
class LiquidGlassBackdrop extends SingleChildRenderObjectWidget {
  const LiquidGlassBackdrop({super.key, required this.radius, required this.material, super.child});

  final double radius;
  final GlassMaterial material;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderLiquidGlass(radius, material, MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(BuildContext context, RenderLiquidGlass renderObject) {
    renderObject
      ..radius = radius
      ..material = material
      ..dpr = MediaQuery.devicePixelRatioOf(context);
  }
}

/// [LiquidGlassBackdrop] 的渲染对象。
class RenderLiquidGlass extends RenderProxyBox {
  RenderLiquidGlass(this._radius, this._material, this._dpr);

  /// 裁剪区域比玻璃每边多出的逻辑像素，着色器据此在纹理中居中定位玻璃。
  static const _pad = 1.0;

  double _radius;
  GlassMaterial _material;
  double _dpr;
  ui.FragmentShader? _shader;
  final _clip = LayerHandle<ClipRectLayer>();
  final _blur = LayerHandle<BackdropFilterLayer>();
  final _glass = LayerHandle<BackdropFilterLayer>();

  set radius(double v) {
    if (v == _radius) return;
    _radius = v;
    markNeedsPaint();
  }

  set material(GlassMaterial v) {
    if (v == _material) return;
    _material = v;
    markNeedsPaint();
  }

  set dpr(double v) {
    if (v == _dpr) return;
    _dpr = v;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void dispose() {
    _clip.layer = null;
    _blur.layer = null;
    _glass.layer = null;
    _shader?.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _shader?.dispose();
    final shader = _shader = LiquidGlassShader._program!.fragmentShader();
    final regular = _material == GlassMaterial.regular;
    var i = 2; // 0、1 是输入纹理尺寸，由引擎填写。
    void f(double v) => shader.setFloat(i++, v);
    f(size.width * _dpr);
    f(size.height * _dpr);
    f(_radius * _dpr);
    f(_dpr);
    f(20); // 边缘厚度
    f(1); // 折射强度 100%
    f(7); // 色散
    f(0.9); // 边缘高光 90%
    f(regular ? 0.11 : 0); // 色调
    // 原版模糊：半径 r 的高斯核，sigma = r / 3。原版以 1 倍屏的像素设计，这里按逻辑像素换算，
    // 使高分屏手机上的模糊程度与原版观感一致。
    final sigma = (regular ? 16 : 1) / 3;

    _clip.layer = context.pushClipRect(needsCompositing, offset, (Offset.zero & size).inflate(_pad), (context, offset) {
      final blur = _blur.layer ??= BackdropFilterLayer();
      blur.filter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp);
      context.pushLayer(blur, (context, offset) {
        final glass = _glass.layer ??= BackdropFilterLayer();
        glass.filter = ui.ImageFilter.shader(shader);
        context.pushLayer(glass, super.paint, offset);
      }, offset);
    }, oldLayer: _clip.layer);
  }
}
