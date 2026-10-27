import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

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
/// 「清透」只有一层着色器滤镜，直接读取当前画面；「柔和」先做一层模糊（同一画面中的多块玻璃通过
/// [BackdropGroup] 共用一次背景截取与模糊），再由着色器读取模糊结果。着色器按输入纹理尺寸判断
/// 坐标系，因此需要玻璃在画面中的位置：每次绘制时写入，位置因祖先变换变化时下一帧补绘。
class LiquidGlassBackdrop extends SingleChildRenderObjectWidget {
  const LiquidGlassBackdrop({super.key, required this.radius, required this.material, super.child});

  final double radius;
  final GlassMaterial material;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderLiquidGlass(radius, material, MediaQuery.devicePixelRatioOf(context), BackdropGroup.of(context)?.backdropKey, AdaptiveScale.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderLiquidGlass renderObject) {
    renderObject
      ..radius = radius
      ..material = material
      ..dpr = MediaQuery.devicePixelRatioOf(context)
      ..backdropKey = BackdropGroup.of(context)?.backdropKey
      ..uiScale = AdaptiveScale.of(context);
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
  final _blur = LayerHandle<BackdropFilterLayer>();
  final _glass = LayerHandle<BackdropFilterLayer>();
  final _shapeClip = LayerHandle<ClipPathLayer>();

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
    _blur.layer = null;
    _glass.layer = null;
    _shapeClip.layer = null;
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
    f(0.9); // 边缘高光 90%
    f(regular ? 0.11 : 0); // 色调
    // 圆角达到短边一半（圆形、胶囊）时用正圆弧，否则用原版面板的超椭圆圆角。
    f(_radius >= size.shortestSide / 2 - 0.5 ? 2 : 5);
    f(global.dx * _dpr / _uiScale);
    f(global.dy * _dpr / _uiScale);
    f(_pad * _dpr);

    void glass(PaintingContext context, Offset offset) {
      final layer = _glass.layer ??= BackdropFilterLayer();
      layer.filter = ui.ImageFilter.shader(shader);
      context.pushLayer(layer, super.paint, offset);
    }

    _clip.layer = context.pushClipRect(needsCompositing, offset, (Offset.zero & size).inflate(_pad), (context, offset) {
      if (!regular) {
        // 「清透」原版只有半径 1 的模糊，肉眼不可见，省去这一层。
        _blur.layer = null;
        _shapeClip.layer = null;
        glass(context, offset);
        return;
      }
      // 原版「柔和」：半径 16 的高斯模糊（sigma = 16 / 3）。原版以 1 倍屏像素设计，这里按逻辑像素换算。
      // 模糊层必须裁成玻璃的形状：否则圆角外、裁剪留边内的背景也被模糊，玻璃周围会露出一块方形。
      final blur = _blur.layer ??= BackdropFilterLayer();
      blur
        ..filter = ui.ImageFilter.blur(sigmaX: 16 / 3, sigmaY: 16 / 3, tileMode: TileMode.clamp)
        ..backdropKey = _backdropKey;
      _shapeClip.layer = context.pushClipPath(needsCompositing, offset, Offset.zero & size, _shapePath(), (context, offset) {
        context.pushLayer(blur, glass, offset);
      }, oldLayer: _shapeClip.layer);
    }, oldLayer: _clip.layer);
  }

  Path? _path;
  Size? _pathSize;
  double? _pathRadius;

  /// 与着色器 shapeSDF 一致的轮廓：圆角为指数 n 的超椭圆（圆形、胶囊 n = 2，面板 n = 5）。
  Path _shapePath() {
    if (_path != null && _pathSize == size && _pathRadius == _radius) return _path!;
    final n = _radius >= size.shortestSide / 2 - 0.5 ? 2.0 : 5.0;
    final r = math.min(_radius, size.shortestSide / 2);
    final path = Path();
    // 四个角各取 16 段，从右上角开始顺时针。
    const steps = 16;
    final corners = [
      (Offset(size.width - r, r), 1.0, -1.0),
      (Offset(size.width - r, size.height - r), 1.0, 1.0),
      (Offset(r, size.height - r), -1.0, 1.0),
      (Offset(r, r), -1.0, -1.0),
    ];
    var first = true;
    for (var c = 0; c < 4; c++) {
      final (center, sx, sy) = corners[c];
      for (var i = 0; i <= steps; i++) {
        // 右上角从顶边走到右边，其余角依次旋转。
        final t = (c + i / steps) * math.pi / 2 - math.pi / 2;
        final cx = math.cos(t), sy0 = math.sin(t);
        final x = center.dx + sx * r * math.pow(cx.abs(), 2 / n);
        final y = center.dy + sy * r * math.pow(sy0.abs(), 2 / n);
        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
    }
    path.close();
    _path = path;
    _pathSize = size;
    _pathRadius = _radius;
    return path;
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
