import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// 阻尼弹簧的阶跃响应，归一化到 0–1 的时间：[damping] 小于 1 时略微越过终点再回弹（Q 弹），
/// 等于 1 时为临界阻尼（干脆、没有回弹）。在 t = 1 时已经静止（误差小于 0.3%）。
class SpringCurve extends Curve {
  const SpringCurve({this.damping = 0.78});

  final double damping;

  @override
  double transformInternal(double t) {
    final z = damping.clamp(0.3, 1.0);
    // 包络 e^(-ζωt) 在 t = 1 时衰减到约 0.2%。
    final w = 6.2 / z;
    if (z >= 0.999) return 1 - math.exp(-w * t) * (1 + w * t);
    final wd = w * math.sqrt(1 - z * z);
    return 1 - math.exp(-z * w * t) * (math.cos(wd * t) + z * w / wd * math.sin(wd * t));
  }
}

/// 全局动效参数：所有页面切换、弹出层与列表入场共用，保证节奏一致。
abstract final class Motion {
  /// 默认弹簧：约 1.5% 的轻微回弹。
  static const spring = SpringCurve(damping: 0.8);

  /// 柔和：几乎没有回弹，用于大面积的页面位移。
  static const gentle = SpringCurve(damping: 0.92);

  /// 明显的 Q 弹：用于小元素的出现（标签、按钮、数字）。
  static const bouncy = SpringCurve(damping: 0.62);

  static const page = Duration(milliseconds: 520);
  static const tab = Duration(milliseconds: 340);
  static const quick = Duration(milliseconds: 320);
}
