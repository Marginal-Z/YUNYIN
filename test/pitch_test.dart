import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/voice/pitch.dart';
import 'package:yunyin/voice/wav.dart';

/// 带谐波、音高缓慢起伏的合成“人声”（中间有停顿）。
Uint8List _voice(double f0, {int rate = 22050}) {
  final n = rate * 2;
  final s = Float32List(n);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    final f = f0 * (1 + 0.05 * math.sin(2 * math.pi * 1.5 * t));
    phase += 2 * math.pi * f / rate;
    final env = (t % 0.5) < 0.4 ? 1.0 : 0.0;
    var v = 0.0;
    for (var h = 1; h <= 8; h++) {
      v += math.sin(phase * h) / h;
    }
    s[i] = (0.3 * env * v).toDouble();
  }
  return encodeWav(s, rate);
}

void main() {
  test('估计基频：区分男声与女声的音高，不出现八度错误', () {
    expect(medianPitch(_voice(120))!, closeTo(120, 8));
    expect(medianPitch(_voice(230))!, closeTo(230, 12));
    expect(medianPitch(_voice(180, rate: 16000))!, closeTo(180, 10));
    expect(medianPitch(encodeWav(Float32List(22050), 22050)), isNull, reason: '静音没有音高');
  });
}
