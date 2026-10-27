// 液态玻璃（背景滤镜）。
//
// 光学模型移植自 iyinchao/liquid-glass-studio（MIT License, Copyright (c) 2024 Charles Yin）
// 的 fragment-main.glsl 最终合成步骤（STEP 9），颜色转换函数来自
// Rachmanin0xFF/GLSL-Color-Functions（MIT License, Copyright (c) 2022 Adam Lastowka）：
//   · 边缘厚度内按斯涅尔定律折射（折射率 1.4），RGB 三通道分别偏移形成色散；
//   · 菲涅尔边缘提亮；
//   · 按法线角度计算的高光（左上与右下最亮），在 LCH 空间提高亮度与彩度；
//   · 「柔和」材质叠加白色色调（模糊由 Dart 端在滤镜链中先行完成）。
//
// 与 WebGL 原版的差异只在宿主：输入纹理由 Flutter 背景滤镜提供（模糊已在前一层完成），
// 坐标为物理像素、y 轴向下，法线用中心差分计算。

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

#define PI 3.14159265359

uniform vec2 uSize;        // 输入纹理尺寸（由引擎填写）
uniform vec2 uShape;       // 玻璃宽高，物理像素
uniform float uRadius;     // 圆角半径，物理像素
uniform float uDpr;        // 设备像素比
uniform float uThickness;  // 边缘厚度，逻辑像素（原版默认 20）
uniform float uRefraction; // 折射强度（原版 refraction / 100）
uniform float uDispersion; // 色散（原版默认 7）
uniform float uGlare;      // 边缘高光（原版 glare / 100）
uniform float uTint;       // 白色色调强度（清透 0，柔和 0.11）
uniform float uRoundness;  // 圆角指数：2 为正圆弧（与普通圆角矩形一致）
uniform vec2 uOrigin;      // 玻璃在画面中的左上角，物理像素
uniform float uPad;        // 裁剪区域每边多出的物理像素

uniform sampler2D uTexture;

out vec4 fragColor;

const float N_R = 1.0 - 0.02;
const float N_G = 1.0;
const float N_B = 1.0 + 0.02;
const float REF_FACTOR = 1.4;

vec4 sampleBg(vec2 uv) {
  return texture(uTexture, uv);
}

float superellipseCornerSDF(vec2 p, float r, float n) {
  p = abs(p);
  float v = pow(pow(p.x, n) + pow(p.y, n), 1.0 / n);
  return v - r;
}

// 超椭圆圆角矩形的符号距离（物理像素，内部为负）。
float shapeSDF(vec2 p) {
  vec2 halfSize = uShape * 0.5;
  float cr = min(uRadius, min(halfSize.x, halfSize.y));
  vec2 d = abs(p) - halfSize;
  if (d.x > -cr && d.y > -cr) {
    vec2 cornerCenter = sign(p) * (halfSize - vec2(cr));
    return superellipseCornerSDF(p - cornerCenter, cr, uRoundness);
  }
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// ---- 颜色转换（sRGB ↔ LCH） ----
const vec3 WHITE = vec3(0.95045592705, 1.0, 1.08905775076);
const mat3 RGB_TO_XYZ_M = mat3(
  0.4124, 0.3576, 0.1805,
  0.2126, 0.7152, 0.0722,
  0.0193, 0.1192, 0.9505
);
const mat3 XYZ_TO_RGB_M = mat3(
   3.2406255, -1.537208 , -0.4986286,
  -0.9689307,  1.8757561,  0.0415175,
   0.0557101, -0.2040211,  1.0569959
);

float uncompand(float a) { return a > 0.04045 ? pow((a + 0.055) / 1.055, 2.4) : a / 12.92; }
float compand(float a) { return a <= 0.0031308 ? 12.92 * a : 1.055 * pow(max(a, 0.0), 0.41666666666) - 0.055; }
float labF(float x) { return x > 0.00885645167 ? pow(x, 0.333333333) : 7.78703703704 * x + 0.13793103448; }
float labFInv(float x) { return x > 0.206897 ? x * x * x : 0.12841854934 * (x - 0.137931034); }

vec3 srgbToLch(vec3 c) {
  vec3 rgb = vec3(uncompand(c.r), uncompand(c.g), uncompand(c.b));
  vec3 xyz = (rgb * RGB_TO_XYZ_M) / WHITE;
  xyz = vec3(labF(xyz.x), labF(xyz.y), labF(xyz.z));
  vec3 lab = vec3(116.0 * xyz.y - 16.0, 500.0 * (xyz.x - xyz.y), 200.0 * (xyz.y - xyz.z));
  return vec3(lab.x, sqrt(dot(lab.yz, lab.yz)), atan(lab.z, lab.y) * 57.2957795131);
}

vec3 lchToSrgb(vec3 lch) {
  vec3 lab = vec3(lch.x, lch.y * cos(lch.z * 0.01745329251), lch.y * sin(lch.z * 0.01745329251));
  float w = (lab.x + 16.0) / 116.0;
  vec3 xyz = WHITE * vec3(labFInv(w + lab.y / 500.0), labFInv(w), labFInv(w - lab.z / 200.0));
  vec3 rgb = xyz * XYZ_TO_RGB_M;
  return vec3(compand(rgb.r), compand(rgb.g), compand(rgb.b));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  // 输入纹理可能是玻璃自己的图层（尺寸 = 玻璃 + 两侧留边，玻璃居中），也可能是整个画面
  // （多块玻璃共享同一次背景截取时）；据尺寸判断坐标系。
  // 「柔和」材质的模糊层裁成玻璃形状后，纹理可能恰好等于玻璃尺寸（不含留边）。
  vec2 expected = uShape + vec2(2.0 * uPad);
  bool local = (abs(uSize.x - expected.x) < 4.0 && abs(uSize.y - expected.y) < 4.0) ||
      (abs(uSize.x - uShape.x) < 2.0 && abs(uSize.y - uShape.y) < 2.0);
  vec2 center = local ? uSize * 0.5 : uOrigin + uShape * 0.5;
  vec2 p = frag - center;

  // 玻璃以外输出透明：滤镜结果以 srcOver 叠回背景，这些像素保持原样（「柔和」的模糊不会溢出到圆角外）。
  if (abs(p.x) > uShape.x * 0.5 + 2.0 || abs(p.y) > uShape.y * 0.5 + 2.0) {
    fragColor = vec4(0.0);
    return;
  }

  float sd = shapeSDF(p);
  vec4 bg = sampleBg(uv);
  vec3 white = vec3(1.0);

  // 进入玻璃的深度（逻辑像素）。小尺寸控件限制厚度，避免整块都处在弯折区。
  float depth = -sd / uDpr;
  float thickness = min(uThickness, 0.4 * min(uShape.x, uShape.y) / uDpr);

  float edgeFactor = 0.0;
  if (depth < thickness) {
    float ratio = 1.0 - max(depth, 0.0) / thickness;
    float thetaI = asin(clamp(ratio * ratio, -1.0, 1.0));
    float thetaT = asin(clamp(sin(thetaI) / REF_FACTOR, -1.0, 1.0));
    edgeFactor = -1.0 * tan(thetaT - thetaI);
  }

  vec4 outColor;
  if (edgeFactor <= 0.0) {
    outColor = mix(bg, vec4(white, 1.0), uTint * 0.8);
  } else {
    // 外法线（y 向下）。
    vec2 e = vec2(1.0, 0.0);
    vec2 grad = vec2(shapeSDF(p + e.xy) - shapeSDF(p - e.xy), shapeSDF(p + e.yx) - shapeSDF(p - e.yx));
    vec2 normal = length(grad) > 0.0 ? normalize(grad) : vec2(0.0);

    // 原版位移：法线 × edgeFactor × 0.05 × 设备像素比，换算为像素约 70.7 × edgeFactor 逻辑像素。
    vec2 offset = -normal * edgeFactor * 70.7 * uRefraction * uDpr / uSize;
    float r = sampleBg(uv + offset * (1.0 - (N_R - 1.0) * uDispersion)).r;
    float g = sampleBg(uv + offset * (1.0 - (N_G - 1.0) * uDispersion)).g;
    float b = sampleBg(uv + offset * (1.0 - (N_B - 1.0) * uDispersion)).b;
    vec4 refracted = vec4(r, g, b, 1.0);
    outColor = mix(refracted, vec4(white, 1.0), uTint * 0.8);

    // 菲涅尔：边缘约 3 像素内提亮。
    float fresnel = clamp(pow(max(1.0 - depth / 1500.0 * pow(500.0 / 30.0, 2.0) + 0.2, 0.0), 5.0), 0.0, 1.0);
    vec3 fresnelLch = srgbToLch(white);
    fresnelLch.x = clamp(fresnelLch.x + 20.0 * fresnel * 0.2, 0.0, 100.0);
    outColor = mix(outColor, vec4(lchToSrgb(fresnelLch), 1.0), fresnel * 0.2 * 0.7);

    // 高光：按法线角度（换算到 y 向上的坐标系，与原版一致）。
    float glareGeo = fresnel;
    float angle = atan(-normal.y, normal.x);
    if (angle < 0.0) angle += 2.0 * PI;
    float glareAngle = (angle - PI / 4.0 - PI / 4.0) * 2.0;
    bool farside = (glareAngle > PI * 1.5 && glareAngle < PI * 3.5) || glareAngle < PI * -0.5;
    float glareFactor = (0.5 + sin(glareAngle) * 0.5) * (farside ? 1.2 * 0.8 : 1.2) * uGlare;
    glareFactor = clamp(pow(max(glareFactor, 0.0), 0.1 + 0.5 * 2.0), 0.0, 1.0);

    vec3 glareLch = srgbToLch(mix(refracted.rgb, white, uTint * 0.5));
    glareLch.x = clamp(glareLch.x + 150.0 * glareFactor * glareGeo, 0.0, 120.0);
    glareLch.y += 30.0 * glareFactor * glareGeo;
    outColor = mix(outColor, vec4(clamp(lchToSrgb(glareLch), 0.0, 1.0), 1.0), glareFactor * glareGeo);
  }

  // 形状边缘 1 像素抗锯齿；形状以外透明（预乘 alpha）。
  fragColor = outColor * (1.0 - smoothstep(-0.5, 0.5, sd));
}
