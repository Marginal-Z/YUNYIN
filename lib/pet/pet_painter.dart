import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'pet_rig.dart';

/// 眼睛的画法：原图（可带眼皮）、笑眼（^ ^）、闭眼（睡觉）、亮晶晶（原图加高光）。
enum EyeMode { normal, happy, closed, sparkle }

/// 嘴的画法：原图、微笑、张嘴（说话，[PetPose.open] 控制大小）、小圆嘴、一字嘴、委屈嘴。
enum MouthMode { original, smile, open, o, flat, frown }

/// 某一时刻的姿态：整体的位移、旋转与挤压，以及五官。
class PetPose {
  double dy = 0;
  double rot = 0;
  double sx = 1, sy = 1;

  /// 眼皮闭合程度（0 睁开，1 闭上），只用于 [EyeMode.normal] / [EyeMode.sparkle]。
  double lid = 0;
  EyeMode eye = EyeMode.normal;
  MouthMode mouth = MouthMode.original;

  /// 张嘴程度（0..1）。
  double open = 0;

  /// 额外的腮红（0..1）。
  double blush = 0;
}

enum ParticleKind { note, heart, z, sparkle }

class _Particle {
  _Particle(this.kind, this.born, this.life, this.origin, this.drift, this.size, this.seed);

  final ParticleKind kind;
  final double born, life;
  final Offset origin, drift;
  final double size, seed;
}

/// 根据状态与时间计算姿态：随机眨眼、呼吸、各状态的动作，以及飘出的特效。
///
/// 时间 [t] 以秒为单位，由外部的计时器提供（同一个动画器只能单调前进）。
class PetAnimator {
  PetAnimator(this.kind, {int? seed}) : _rand = math.Random(seed);

  PetKind kind;
  final math.Random _rand;

  PetMood _mood = PetMood.idle;
  double _moodStart = 0;
  double _now = 0;

  /// 被拖动时的水平速度（逻辑像素 / 秒），用来让桌宠跟着晃。
  double dragVelocity = 0;

  double _nextBlink = 1.5;
  double _blinkStart = -10;
  bool _doubleBlink = false;

  double _nextAction = 8;
  double _actionStart = -10;
  int _action = 0;

  double _nextParticle = 0;
  final List<_Particle> _particles = [];

  // 状态切换时平滑过渡的整体动作。
  double _dy = 0, _rot = 0, _sx = 1, _sy = 1;
  double _lastFrame = 0;

  PetMood get mood => _mood;

  void setMood(PetMood m) {
    if (m == _mood) return;
    _mood = m;
    _moodStart = _now;
    _nextParticle = _now;
  }

  /// 点按时的小反应：蹦一下并冒出爱心。
  void poke() {
    _action = 1;
    _actionStart = _now;
    for (var i = 0; i < 3; i++) {
      _spawn(ParticleKind.heart, delay: i * 0.12);
    }
  }

  double _blinkLid(double t) {
    final d = t - _blinkStart;
    double one(double d) {
      if (d < 0 || d > 0.17) return 0;
      if (d < 0.06) return d / 0.06;
      if (d < 0.09) return 1;
      return 1 - (d - 0.09) / 0.08;
    }

    var v = one(d);
    if (_doubleBlink) v = math.max(v, one(d - 0.22));
    if (t >= _nextBlink) {
      _blinkStart = t;
      _doubleBlink = _rand.nextDouble() < 0.2;
      _nextBlink = t + 2.2 + _rand.nextDouble() * 3.4;
    }
    return v;
  }

  /// 说话时的口型：大约每秒四五个音节，偶尔停顿换气。
  static double syllable(double t) {
    final s = math.sin(2 * math.pi * 4.4 * t + 1.3 * math.sin(2 * math.pi * 0.7 * t));
    final env = 0.55 + 0.45 * math.sin(2 * math.pi * 1.37 * t + 2).abs();
    var a = math.max(0.0, s) * env;
    if (math.sin(2 * math.pi * 0.31 * t) > 0.88) a *= 0.15;
    return a.clamp(0.0, 1.0);
  }

  void _spawn(ParticleKind k, {double delay = 0}) {
    final r = kind.rig;
    final jitter = Offset((_rand.nextDouble() - 0.5) * r.width * 0.5, (_rand.nextDouble() - 0.5) * 40);
    final drift = switch (k) {
      ParticleKind.z => Offset(60 + _rand.nextDouble() * 30, -150),
      ParticleKind.sparkle => Offset((_rand.nextDouble() - 0.5) * 120, -40 - _rand.nextDouble() * 60),
      _ => Offset((_rand.nextDouble() - 0.5) * 90, -180 - _rand.nextDouble() * 60),
    };
    final origin = switch (k) {
      ParticleKind.z => r.head + Offset(r.width * 0.18, 10),
      _ => r.head + jitter,
    };
    final size = switch (k) {
      ParticleKind.note => 70.0 + _rand.nextDouble() * 20,
      ParticleKind.heart => 48.0 + _rand.nextDouble() * 16,
      ParticleKind.z => 52.0,
      ParticleKind.sparkle => 30.0 + _rand.nextDouble() * 18,
    };
    _particles.add(_Particle(k, _now + delay, k == ParticleKind.z ? 2.6 : 1.8, origin, drift, size, _rand.nextDouble()));
  }

  /// 当前时刻的姿态（同时推进眨眼、特效与小动作的计时）。
  PetPose pose(double t) {
    _now = t;
    final dt = (t - _lastFrame).clamp(0.0, 0.1);
    _lastFrame = t;
    final p = PetPose();
    final since = t - _moodStart;
    var lid = _blinkLid(t);
    double dy = 0, rot = 0, sx = 1, sy = 1;
    final breathe = math.sin(2 * math.pi * t / 3.2);

    // 粒子：按状态定时生成。
    ParticleKind? emit;
    var every = 0.0;

    switch (_mood) {
      case PetMood.idle:
        sy = 1 + 0.012 * breathe;
        sx = 1 - 0.006 * breathe;
        rot = 0.018 * math.sin(2 * math.pi * t / 5.3);
        // 待机时偶尔做个小动作：笑一下、歪头或者蹦一下。
        if (t >= _nextAction) {
          _action = 2 + _rand.nextInt(3);
          _actionStart = t;
          _nextAction = t + 9 + _rand.nextDouble() * 8;
        }
      case PetMood.listening:
        final b = math.sin(2 * math.pi * t / 1.6);
        sy = 1.02 + 0.012 * b;
        sx = 0.995;
        rot = 0.05 * math.min(1, since / 0.3);
        dy = -3;
        p.eye = EyeMode.sparkle;
        p.mouth = MouthMode.o;
        p.open = 0.35;
      case PetMood.thinking:
        sy = 1 + 0.01 * breathe;
        rot = 0.06 * math.sin(2 * math.pi * t / 2.6);
        lid = math.max(lid, 0.32);
        p.mouth = MouthMode.flat;
      case PetMood.speaking:
        final a = syllable(t);
        p.mouth = MouthMode.open;
        p.open = a;
        dy = -3 * a;
        sy = 1 + 0.015 * a;
        rot = 0.022 * math.sin(2 * math.pi * t / 2.1);
        p.blush = 0.25;
      case PetMood.happy:
        final hop = since < 1.4 ? math.max(0.0, math.sin(2 * math.pi * since * 1.6)) : 0.0;
        dy = -16 * hop;
        sy = 1 + 0.04 * hop - (hop == 0 && since < 1.4 ? 0.025 : 0);
        sx = 1 - 0.02 * hop;
        rot = 0.03 * math.sin(2 * math.pi * t / 1.8);
        p.eye = EyeMode.happy;
        p.mouth = MouthMode.open;
        p.open = 0.55;
        p.blush = 0.6;
        emit = since < 2 ? ParticleKind.sparkle : null;
        every = 0.25;
      case PetMood.dancing:
        final beat = math.sin(math.pi * 2 * t).abs();
        dy = -9 * beat;
        rot = 0.07 * math.sin(math.pi * 2 * t);
        sy = 1 - 0.03 * (1 - beat);
        sx = 1 + 0.015 * (1 - beat);
        p.eye = (t % 4) < 2.4 ? EyeMode.happy : EyeMode.normal;
        p.mouth = MouthMode.smile;
        p.blush = 0.3;
        emit = ParticleKind.note;
        every = 0.9;
      case PetMood.sleepy:
        final slow = math.sin(2 * math.pi * t / 4.5);
        sy = 1 + 0.022 * slow;
        sx = 1 - 0.01 * slow;
        rot = 0.035;
        p.eye = EyeMode.closed;
        p.mouth = MouthMode.o;
        p.open = 0.15 + 0.1 * (slow + 1) / 2;
        emit = ParticleKind.z;
        every = 1.3;
      case PetMood.sad:
        sy = 0.975 + 0.008 * breathe;
        sx = 1.01;
        rot = -0.03;
        lid = math.max(lid, 0.42);
        p.mouth = MouthMode.frown;
      case PetMood.dragged:
        final wobble = math.sin(2 * math.pi * t * 3) * 0.02;
        rot = (-dragVelocity / 2500).clamp(-0.28, 0.28) + wobble;
        sy = 1.05;
        sx = 0.965;
        p.eye = EyeMode.sparkle;
        p.mouth = MouthMode.o;
        p.open = 0.6;
        lid = 0;
    }

    // 小动作（点按与待机时的随机动作）叠加在当前状态上。
    final ad = t - _actionStart;
    switch (_action) {
      case 1 when ad < 0.6: // 被戳：蹦一下
        final h = math.sin(math.pi * ad / 0.6);
        dy -= 18 * h;
        sy += 0.05 * h;
        if (_mood == PetMood.idle || _mood == PetMood.dancing) {
          p.eye = EyeMode.happy;
          p.mouth = MouthMode.open;
          p.open = 0.6;
        }
        p.blush = math.max(p.blush, 0.6);
      case 2 when ad < 1.4 && _mood == PetMood.idle: // 笑一下
        p.eye = EyeMode.happy;
        p.mouth = MouthMode.smile;
        p.blush = 0.5;
      case 3 when ad < 1.8 && _mood == PetMood.idle: // 歪头
        rot += 0.08 * math.sin(math.pi * ad / 1.8);
      case 4 when ad < 0.5 && _mood == PetMood.idle: // 蹦一下
        final h = math.sin(math.pi * ad / 0.5);
        dy -= 10 * h;
        sy += 0.03 * h;
    }

    if (emit != null && t >= _nextParticle) {
      _spawn(emit);
      _nextParticle = t + every * (0.7 + _rand.nextDouble() * 0.6);
    }
    _particles.removeWhere((q) => t - q.born > q.life);

    // 整体动作平滑过渡（状态切换时不跳）。
    final k = 1 - math.exp(-dt * 14);
    _dy += (dy - _dy) * k;
    _rot += (rot - _rot) * k;
    _sx += (sx - _sx) * k;
    _sy += (sy - _sy) * k;
    p
      ..dy = _dy
      ..rot = _rot
      ..sx = _sx
      ..sy = _sy
      ..lid = lid;
    return p;
  }

  Iterable<_Particle> get _alive => _particles.where((q) => _now >= q.born);
}

/// 画出桌宠：原图 + 表情 + 特效。[image] 为 [PetRig.asset] 解码后的图片。
///
/// 画布上方与两侧留出空白放特效，桌宠的脚底贴着画布底部。
class PetPainter extends CustomPainter {
  PetPainter({required this.image, required this.animator, required this.time, required this.accent}) : super(repaint: time);

  final ui.Image image;
  final PetAnimator animator;
  final ValueListenable<double> time;
  final Color accent;

  /// 画布中桌宠以外的留白比例（上、左右）。
  static const topRoom = 0.22, sideRoom = 0.08;

  /// 给定桌宠高度时画布的大小。
  static Size canvasSize(PetKind kind, double petHeight) {
    final r = kind.rig;
    final w = petHeight * r.width / r.height;
    return Size(w * (1 + 2 * sideRoom), petHeight * (1 + topRoom));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final pose = animator.pose(t);
    final rig = animator.kind.rig;
    final petH = size.height / (1 + topRoom);
    final scale = petH / rig.height;
    final petW = rig.width * scale;
    final foot = Offset(size.width / 2, size.height - 2);

    canvas.save();
    canvas.translate(foot.dx, foot.dy + pose.dy * scale * 2);
    canvas.rotate(pose.rot);
    canvas.scale(pose.sx, pose.sy);
    canvas.translate(-petW / 2, -petH);
    canvas.scale(scale);

    if (animator.mood == PetMood.listening) _rings(canvas, rig, t);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, rig.width, rig.height),
      Paint()..filterQuality = FilterQuality.medium,
    );
    _blush(canvas, rig, pose.blush);
    for (final e in rig.eyes) {
      _eye(canvas, rig, e, pose);
    }
    _mouth(canvas, rig, pose);
    if (animator.mood == PetMood.sad) _sweat(canvas, rig, t);
    if (animator.mood == PetMood.thinking) _thinking(canvas, rig, t);
    for (final q in animator._alive) {
      _particle(canvas, q, t);
    }
    canvas.restore();
  }

  void _blush(Canvas canvas, PetRig rig, double amount) {
    if (amount <= 0.01) return;
    final paint = Paint()
      ..color = const Color(0xFFFF8FA3).withValues(alpha: 0.45 * amount)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (final r in rig.blush) {
      canvas.drawOval(r.inflate(4), paint);
    }
  }

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  void _cover(Canvas canvas, PetRig rig, Rect r) {
    canvas.drawOval(r, Paint()..color = rig.skin);
  }

  void _eye(Canvas canvas, PetRig rig, EyeRig e, PetPose pose) {
    final box = Rect.fromCenter(center: e.center, width: e.rx * 2.2, height: e.ry * 2.3);
    final lw = math.max(4.0, e.ry * 0.2);
    switch (pose.eye) {
      case EyeMode.happy:
        // 笑眼：盖住原来的眼睛，画一道向上弯的弧线（^）。
        _cover(canvas, rig, box);
        final path = Path()
          ..moveTo(e.cx - e.rx * 0.85, e.cy + e.ry * 0.25)
          ..quadraticBezierTo(e.cx, e.cy - e.ry * 0.75, e.cx + e.rx * 0.85, e.cy + e.ry * 0.25);
        canvas.drawPath(path, _stroke(rig.line, lw));
        return;
      case EyeMode.closed:
        // 闭眼：向下弯的弧线（︶）与两根睫毛。
        _cover(canvas, rig, box);
        final y = e.cy + e.ry * 0.15;
        final path = Path()
          ..moveTo(e.cx - e.rx * 0.85, y)
          ..quadraticBezierTo(e.cx, y + e.ry * 0.55, e.cx + e.rx * 0.85, y);
        canvas.drawPath(path, _stroke(rig.line, lw));
        return;
      case EyeMode.normal:
      case EyeMode.sparkle:
        break;
    }
    if (pose.eye == EyeMode.sparkle) {
      // 亮晶晶：在原图的眼睛上加两颗高光。
      final white = Paint()..color = const Color(0xF2FFFFFF);
      canvas.drawCircle(Offset(e.cx + e.rx * 0.32, e.cy + e.ry * 0.38), e.ry * 0.13, white);
      canvas.drawCircle(Offset(e.cx - e.rx * 0.3, e.cy - e.ry * 0.05), e.ry * 0.08, white);
    }
    final lid = pose.lid.clamp(0.0, 1.0);
    if (lid < 0.02) return;
    if (lid > 0.97) {
      _cover(canvas, rig, box);
      final y = e.cy + e.ry * 0.3;
      final path = Path()
        ..moveTo(e.cx - e.rx * 0.9, y - e.ry * 0.05)
        ..quadraticBezierTo(e.cx, y + e.ry * 0.3, e.cx + e.rx * 0.9, y - e.ry * 0.05);
      canvas.drawPath(path, _stroke(rig.line, lw));
      return;
    }
    // 眼皮：从上往下盖住眼睛，下沿是一条睫毛。
    final top = box.top;
    final edge = top + (box.height * 0.88) * lid + box.height * 0.06;
    final sag = e.ry * 0.28;
    canvas.save();
    canvas.clipPath(Path()..addOval(box));
    final lidPath = Path()
      ..moveTo(box.left - 4, top - 4)
      ..lineTo(box.right + 4, top - 4)
      ..lineTo(box.right + 4, edge - sag * 0.4)
      ..quadraticBezierTo(e.cx, edge + sag, box.left - 4, edge - sag * 0.4)
      ..close();
    canvas.drawPath(lidPath, Paint()..color = rig.skin);
    canvas.restore();
    final lash = Path()
      ..moveTo(e.cx - e.rx * 1.0, edge - sag * 0.35)
      ..quadraticBezierTo(e.cx, edge + sag * 1.05, e.cx + e.rx * 1.0, edge - sag * 0.35);
    canvas.drawPath(lash, _stroke(rig.line, lw));
  }

  void _mouth(Canvas canvas, PetRig rig, PetPose pose) {
    if (pose.mouth == MouthMode.original) return;
    final c = rig.mouth;
    final w = rig.mouthWidth;
    canvas.drawOval(Rect.fromCenter(center: c, width: rig.mouthPatch.width, height: rig.mouthPatch.height), Paint()..color = rig.skin);
    final lw = math.max(3.0, w * 0.09);
    final line = _stroke(rig.line, lw);
    const inside = Color(0xFFB4485E);
    const tongue = Color(0xFFFF9AAE);
    final cat = rig.mouthStyle == MouthStyle.cat;
    switch (pose.mouth) {
      case MouthMode.original:
        break;
      case MouthMode.smile:
        if (cat) {
          _catTop(canvas, c, w, line);
        } else {
          canvas.drawPath(
            Path()
              ..moveTo(c.dx - w * 0.45, c.dy - w * 0.08)
              ..quadraticBezierTo(c.dx, c.dy + w * 0.4, c.dx + w * 0.45, c.dy - w * 0.08),
            line,
          );
        }
      case MouthMode.open:
        final a = pose.open.clamp(0.0, 1.0);
        final h = w * (0.12 + 0.55 * a);
        final top = cat ? c.dy - w * 0.02 : c.dy - h * 0.35;
        final half = cat ? w * 0.32 : w * (0.36 + 0.06 * a);
        final shape = Path()
          ..moveTo(c.dx - half, top)
          ..quadraticBezierTo(c.dx, top + w * 0.06, c.dx + half, top)
          ..cubicTo(c.dx + half, top + h * 0.9, c.dx + half * 0.5, top + h * 1.25, c.dx, top + h * 1.25)
          ..cubicTo(c.dx - half * 0.5, top + h * 1.25, c.dx - half, top + h * 0.9, c.dx - half, top)
          ..close();
        canvas.drawPath(shape, Paint()..color = inside);
        canvas.save();
        canvas.clipPath(shape);
        canvas.drawOval(Rect.fromCenter(center: Offset(c.dx, top + h * 1.2), width: half * 1.5, height: h * 0.9), Paint()..color = tongue);
        canvas.restore();
        canvas.drawPath(shape, _stroke(rig.line, lw * 0.8));
        if (cat) _catTop(canvas, Offset(c.dx, top - w * 0.02), w, line);
      case MouthMode.o:
        final r = w * (0.14 + 0.12 * pose.open);
        final rect = Rect.fromCenter(center: c, width: r * 1.6, height: r * 2);
        canvas.drawOval(rect, Paint()..color = inside);
        canvas.drawOval(rect, _stroke(rig.line, lw * 0.75));
      case MouthMode.flat:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - w * 0.22, c.dy)
            ..quadraticBezierTo(c.dx, c.dy + w * 0.04, c.dx + w * 0.22, c.dy - w * 0.02),
          line,
        );
      case MouthMode.frown:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - w * 0.3, c.dy + w * 0.12)
            ..quadraticBezierTo(c.dx, c.dy - w * 0.16, c.dx + w * 0.3, c.dy + w * 0.12),
          line,
        );
    }
  }

  /// 小猫嘴的上半部分（ω）。
  void _catTop(Canvas canvas, Offset c, double w, Paint line) {
    final y = c.dy - w * 0.08;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - w * 0.42, y - w * 0.06)
        ..quadraticBezierTo(c.dx - w * 0.21, y + w * 0.3, c.dx, y)
        ..quadraticBezierTo(c.dx + w * 0.21, y + w * 0.3, c.dx + w * 0.42, y - w * 0.06),
      line,
    );
  }

  void _rings(Canvas canvas, PetRig rig, double t) {
    final center = Offset(rig.width / 2, rig.height * 0.5);
    for (var i = 0; i < 3; i++) {
      final f = ((t / 1.6) + i / 3) % 1;
      final r = rig.width * (0.32 + 0.38 * f);
      canvas.drawCircle(center, r, _stroke(accent.withValues(alpha: 0.45 * (1 - f)), 6 * (1 - f) + 2));
    }
  }

  void _sweat(Canvas canvas, PetRig rig, double t) {
    final s = rig.sweat + Offset(0, 6 * math.sin(2 * math.pi * t / 1.4));
    const h = 34.0;
    final drop = Path()
      ..moveTo(s.dx, s.dy - h * 0.6)
      ..quadraticBezierTo(s.dx + h * 0.45, s.dy + h * 0.05, s.dx, s.dy + h * 0.4)
      ..quadraticBezierTo(s.dx - h * 0.45, s.dy + h * 0.05, s.dx, s.dy - h * 0.6)
      ..close();
    canvas.drawPath(drop, Paint()..color = const Color(0xFF8CC8FF));
    canvas.drawPath(drop, _stroke(const Color(0xFF4A90D9), 3));
  }

  void _thinking(Canvas canvas, PetRig rig, double t) {
    // 头顶右侧的思考泡泡，里面三个点依次跳动。
    final c = rig.head + Offset(rig.width * 0.26, -10);
    final bubble = Paint()..color = const Color(0xF2FFFFFF);
    final border = _stroke(accent.withValues(alpha: 0.6), 3);
    final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 120, height: 58), const Radius.circular(29));
    canvas.drawCircle(c + const Offset(-52, 46), 9, bubble);
    canvas.drawCircle(c + const Offset(-52, 46), 9, border);
    canvas.drawRRect(rect, bubble);
    canvas.drawRRect(rect, border);
    for (var i = 0; i < 3; i++) {
      final ph = ((t * 1.6) - i * 0.18) % 1;
      final up = ph < 0.4 ? math.sin(math.pi * ph / 0.4) : 0.0;
      canvas.drawCircle(c + Offset((i - 1) * 30.0, -8 * up), 8, Paint()..color = accent.withValues(alpha: 0.55 + 0.45 * up));
    }
  }

  void _particle(Canvas canvas, _Particle q, double t) {
    final f = ((t - q.born) / q.life).clamp(0.0, 1.0);
    final pos = q.origin + q.drift * f + Offset(14 * math.sin(2 * math.pi * (f * 1.5 + q.seed)), 0);
    final alpha = f < 0.15 ? f / 0.15 : (1 - f) / 0.85;
    switch (q.kind) {
      case ParticleKind.note:
        _note(canvas, pos, q.size, accent.withValues(alpha: alpha), double: q.seed >= 0.5);
      case ParticleKind.z:
        final s = q.size * (0.6 + 0.6 * f);
        canvas.drawPath(
          Path()
            ..moveTo(pos.dx - s * 0.35, pos.dy - s * 0.35)
            ..lineTo(pos.dx + s * 0.35, pos.dy - s * 0.35)
            ..lineTo(pos.dx - s * 0.35, pos.dy + s * 0.35)
            ..lineTo(pos.dx + s * 0.35, pos.dy + s * 0.35),
          _stroke(const Color(0xFF7C8DB5).withValues(alpha: alpha), s * 0.17),
        );
      case ParticleKind.heart:
        final s = q.size * (0.8 + 0.3 * f);
        final path = Path()
          ..moveTo(pos.dx, pos.dy + s * 0.35)
          ..cubicTo(pos.dx - s * 0.6, pos.dy - s * 0.05, pos.dx - s * 0.35, pos.dy - s * 0.55, pos.dx, pos.dy - s * 0.25)
          ..cubicTo(pos.dx + s * 0.35, pos.dy - s * 0.55, pos.dx + s * 0.6, pos.dy - s * 0.05, pos.dx, pos.dy + s * 0.35)
          ..close();
        canvas.drawPath(path, Paint()..color = const Color(0xFFFF6F91).withValues(alpha: alpha));
      case ParticleKind.sparkle:
        final s = q.size * (0.6 + 0.4 * math.sin(math.pi * f));
        final path = Path()
          ..moveTo(pos.dx, pos.dy - s)
          ..quadraticBezierTo(pos.dx, pos.dy, pos.dx + s, pos.dy)
          ..quadraticBezierTo(pos.dx, pos.dy, pos.dx, pos.dy + s)
          ..quadraticBezierTo(pos.dx, pos.dy, pos.dx - s, pos.dy)
          ..quadraticBezierTo(pos.dx, pos.dy, pos.dx, pos.dy - s)
          ..close();
        canvas.drawPath(path, Paint()..color = const Color(0xFFFFC93C).withValues(alpha: alpha));
    }
  }

  /// 音符（♪ / ♫）：用图形画，不依赖字体。
  void _note(Canvas canvas, Offset at, double size, Color color, {bool double = false}) {
    final fill = Paint()..color = color;
    final stem = _stroke(color, size * 0.09);
    final headW = size * 0.34, headH = size * 0.25;
    void head(Offset c) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-0.4);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: headW, height: headH), fill);
      canvas.restore();
    }

    final h1 = at + Offset(-size * 0.22, size * 0.3);
    head(h1);
    final top1 = Offset(h1.dx + headW * 0.42, h1.dy - size * 0.68);
    canvas.drawLine(Offset(top1.dx, h1.dy - headH * 0.1), top1, stem);
    if (double) {
      final h2 = h1 + Offset(size * 0.46, -size * 0.1);
      head(h2);
      final top2 = Offset(h2.dx + headW * 0.42, h2.dy - size * 0.68);
      canvas.drawLine(Offset(top2.dx, h2.dy - headH * 0.1), top2, stem);
      canvas.drawLine(top1, top2, _stroke(color, size * 0.13));
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(top1.dx, top1.dy)
          ..quadraticBezierTo(top1.dx + size * 0.32, top1.dy + size * 0.12, top1.dx + size * 0.22, top1.dy + size * 0.42),
        stem,
      );
    }
  }

  @override
  bool shouldRepaint(PetPainter old) => old.image != image || old.animator != animator || old.accent != accent;
}
