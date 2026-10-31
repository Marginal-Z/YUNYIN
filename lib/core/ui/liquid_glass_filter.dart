import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

import '../settings.dart';
import 'adaptive_scale.dart';

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
/// 「清透」是一层着色器滤镜；「柔和」是“模糊 → 着色器”组合成的一层滤镜。同一画面中的多块玻璃通过
/// [BackdropGroup] 共用一次背景截取。着色器按输入纹理尺寸判断坐标系，因此需要玻璃在画面中的位置：
/// 每次绘制时写入，位置因祖先变换变化时下一帧补绘。
class LiquidGlassBackdrop extends SingleChildRenderObjectWidget {
  const LiquidGlassBackdrop({super.key, required this.radius, required this.material, super.child});

  final double radius;
  final GlassMaterial material;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderLiquidGlass(radius, material, MediaQuery.devicePixelRatioOf(context), BackdropGroup.of(context)?.backdropKey, AdaptiveScale.of(context))
        ..dark = Theme.of(context).brightness == Brightness.dark;

  @override
  void updateRenderObject(BuildContext context, RenderLiquidGlass renderObject) {
    renderObject
      ..radius = radius
      ..material = material
      ..dpr = MediaQuery.devicePixelRatioOf(context)
      ..backdropKey = BackdropGroup.of(context)?.backdropKey
      ..uiScale = AdaptiveScale.of(context)
      ..dark = Theme.of(context).brightness == Brightness.dark;
  }
}

/// [LiquidGlassBackdrop] 的渲染对象。
class RenderLiquidGlass extends RenderProxyBox {
  RenderLiquidGlass(this._radius, this._material, this._dpr, this._backdropKey, this._uiScale);

  /// 裁剪区域比玻璃每边多出的逻辑像素。
  static const _pad = 1.0;

  double _radius;
  GlassMaterial _material;
  double _dpr;
  BackdropKey? _backdropKey;

  /// 界面缩放倍数：全局坐标是缩放后的屏幕坐标，换算物理像素时要除去这一倍数。
  double _uiScale;
  Offset? _painted;
  bool _checkScheduled = false;
  ui.FragmentShader? _shader;
  final _clip = LayerHandle<ClipRectLayer>();
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

  bool _dark = false;

  set dark(bool v) {
    if (v == _dark) return;
    _dark = v;
    markNeedsPaint();
  }

  set uiScale(double v) {
    if (v == _uiScale) return;
    _uiScale = v;
    markNeedsPaint();
  }

  set backdropKey(BackdropKey? v) {
    if (v == _backdropKey) return;
    _backdropKey = v;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void dispose() {
    _clip.layer = null;
    _glass.layer = null;
    _shader?.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final global = localToGlobal(Offset.zero);
    _painted = global;
    _scheduleCheck();

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
    // 边缘高光 90%；深色背景上同样强度的高光会形成一圈亮边、看起来像两层叠在一起，减到 55%。
    f(_dark ? 0.55 : 0.9);
    f(_dark ? (regular ? 0.75 : 0.55) : (regular ? 0.11 : 0)); // 色调强度
    // 圆角一律用正圆弧，与关闭液态玻璃时的圆角矩形完全一致（原版面板的超椭圆圆角看起来偏方）。
    f(2);
    f(global.dx * _dpr / _uiScale);
    f(global.dy * _dpr / _uiScale);
    f(_pad * _dpr);
    // 色调颜色：浅色模式白色；深色模式深灰（清透 / 柔和都带一层，避免深色背景上只剩边缘高光、看起来像几层轮廓叠在一起）。
    if (_dark) {
      f(0.11);
      f(0.11);
      f(0.12);
    } else {
      f(1);
      f(1);
      f(1);
    }

    // 每块玻璃只有一层背景滤镜，同一画面中的所有玻璃通过 [BackdropGroup] 共用一次背景截取：
    // 背景截取在移动端 GPU 上很昂贵，原先每块玻璃各截一次（「柔和」还要再截一次并按形状裁剪）。
    // 着色器在玻璃形状以外输出透明，滤镜结果以 srcOver 叠回背景，形状以外保持原样，无需按形状裁剪。
    final layer = _glass.layer ??= BackdropFilterLayer();
    final glass = ui.ImageFilter.shader(shader);
    layer
      ..filter = regular
          // 原版「柔和」：半径 16 的高斯模糊（sigma = 16 / 3），再由着色器读取模糊结果。原版以 1 倍屏像素设计，这里按逻辑像素换算。
          ? ui.ImageFilter.compose(
              outer: glass,
              inner: ui.ImageFilter.blur(sigmaX: 16 / 3, sigmaY: 16 / 3, tileMode: TileMode.clamp),
            )
          : glass
      ..backdropKey = _backdropKey;
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      (Offset.zero & size).inflate(_pad),
      (context, offset) => context.pushLayer(layer, super.paint, offset),
      oldLayer: _clip.layer,
    );
  }

  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!attached || _painted == null) return;
      if ((localToGlobal(Offset.zero) - _painted!).distanceSquared > 0.01) markNeedsPaint();
    });
  }
}
