import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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
/// 着色器需要知道玻璃在当前画面中的位置，所以每次绘制时把全局坐标写入 uniform；
/// 位置因祖先变换（滚动、转场）而变化但自身没有重绘时，下一帧会自动补绘一次。
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

  double _radius;
  GlassMaterial _material;
  double _dpr;
  Offset? _painted;
  bool _checkScheduled = false;
  ui.FragmentShader? _shader;
  final _clip = LayerHandle<ClipRectLayer>();
  final _backdrop = LayerHandle<BackdropFilterLayer>();

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
    _backdrop.layer = null;
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
    f(global.dx * _dpr);
    f(global.dy * _dpr);
    f(size.width * _dpr);
    f(size.height * _dpr);
    f(_radius * _dpr);
    f(_dpr);
    f(20); // 边缘厚度
    f(1); // 折射强度 100%
    f(7); // 色散
    f(0.9); // 边缘高光 90%
    f(regular ? 0.11 : 0); // 色调
    ui.ImageFilter filter = ui.ImageFilter.shader(shader);
    if (regular) {
      // 原版「柔和」材质先做半径 16 物理像素（sigma = 半径 / 3）的高斯模糊。
      final sigma = 16 / 3 / _dpr;
      filter = ui.ImageFilter.compose(
        outer: filter,
        inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
      );
    }

    _clip.layer = context.pushClipRect(needsCompositing, offset, (Offset.zero & size).inflate(1), (context, offset) {
      final layer = _backdrop.layer ??= BackdropFilterLayer();
      layer.filter = filter;
      context.pushLayer(layer, super.paint, offset);
    }, oldLayer: _clip.layer);
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
