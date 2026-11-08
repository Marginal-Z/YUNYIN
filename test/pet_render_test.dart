import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/pet/pet_painter.dart';
import 'package:yunyin/pet/pet_rig.dart';

Future<ui.Image> _load(PetKind k) async {
  final codec = await ui.instantiateImageCodec(File(k.rig.asset).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

/// 按状态与时间画一帧，返回 RGBA 像素。
Future<(ui.Image, ByteData)> _frame(PetKind kind, ui.Image img, PetMood mood, double at, {double petH = 300, void Function(PetAnimator)? setup}) async {
  final a = PetAnimator(kind, seed: 7);
  final time = ValueNotifier<double>(0);
  a.pose(0);
  a.setMood(mood);
  setup?.call(a);
  // 逐步推进，让平滑过渡与粒子有时间生效。
  for (var t = 0.0; t < at; t += 1 / 30) {
    a.pose(t);
  }
  time.value = at;
  final size = PetPainter.canvasSize(kind, petH);
  final rec = ui.PictureRecorder();
  PetPainter(image: img, animator: a, time: time, accent: kind.color).paint(Canvas(rec), size);
  final out = await rec.endRecording().toImage(size.width.ceil(), size.height.ceil());
  return (out, (await out.toByteData())!);
}

void main() {
  test('三只桌宠的各种表情都能画出来，眨眼与说话会改变五官', () async {
    final sheet = Platform.environment['YUNYIN_PET_SHEET'];
    // 各状态取一个有代表性的时刻（说话取张嘴的瞬间）。
    final shots = <(PetMood, double)>[
      (PetMood.idle, 0.5),
      (PetMood.listening, 1.0),
      (PetMood.thinking, 1.0),
      (PetMood.speaking, 1.06),
      (PetMood.happy, 0.6),
      (PetMood.dancing, 1.2),
      (PetMood.sleepy, 2.0),
      (PetMood.sad, 1.0),
      (PetMood.dragged, 0.5),
    ];
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    var y = 0.0, width = 0.0;
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      for (final kind in PetKind.values) {
        final img = await _load(kind);
        var x = 0.0, rowH = 0.0;
        final pixels = <PetMood, ByteData>{};
        for (final (mood, at) in shots) {
          final (frame, bytes) = await _frame(kind, img, mood, at);
          pixels[mood] = bytes;
          canvas.drawRect(Rect.fromLTWH(x, y, frame.width.toDouble(), frame.height.toDouble()), Paint()..color = const Color(0xFFEFF3FA));
          canvas.drawImage(frame, Offset(x, y), Paint());
          x += frame.width + 8;
          rowH = frame.height.toDouble();
        }
        width = x;
        y += rowH + 8;
        expect(listEquals(pixels[PetMood.idle]!.buffer.asUint8List(), pixels[PetMood.happy]!.buffer.asUint8List()), isFalse);

        // 眨眼：闭眼的瞬间眼睛中心是皮肤色。
        final a = PetAnimator(kind, seed: 1);
        a.pose(0);
        final blinkAt = [for (var t = 0.0; t < 8; t += 1 / 60) t].firstWhere((t) => a.pose(t).lid > 0.99);
        final (open, ob) = await _frame(kind, img, PetMood.idle, 0.3);
        final eye = kind.rig.eyes.first;
        final scale = 300 / kind.rig.height;
        int px(ByteData b, ui.Image im) {
          final sx = (im.width / 2 - kind.rig.width * scale / 2 + eye.cx * scale).round();
          final sy = (im.height - 2 - 300 + eye.cy * scale).round();
          return b.getUint32((sy * im.width + sx) * 4);
        }

        final (closed, cb) = await _frame(kind, img, PetMood.idle, blinkAt);
        expect(px(ob, open), isNot(px(cb, closed)), reason: '${kind.label}眨眼时眼睛被眼皮盖住');
      }
    });
    if (sheet != null) {
      final out = await rec.endRecording().toImage(width.ceil(), y.ceil());
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      File(sheet).writeAsBytesSync(png!.buffer.asUint8List());
    }
  });

  test('说话的口型有开有合，不会一直张着嘴', () {
    final v = [for (var t = 0.0; t < 6; t += 0.02) PetAnimator.syllable(t)];
    expect(v.where((a) => a > 0.5).length, greaterThan(20));
    expect(v.where((a) => a < 0.05).length, greaterThan(20));
  });
}
