import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/player/player_controller.dart';

void main() {
  test('均衡器滤镜：全部为 0 时不加滤镜，只使用 equalizer', () {
    expect(PlayerController.eqFilter(List.filled(10, 0)), '');
    final f = PlayerController.eqFilter([for (final g in EqPreset.bass.gains) g.toDouble()]);
    expect(f, startsWith('format=format=floatp,lavfi=[equalizer=f=31:width_type=o:width=1:g=6.0'));
    expect(f, isNot(contains('volume')), reason: '精简版 FFmpeg 没有 volume 滤镜');
    expect(f, isNot(contains('f=1000')), reason: '增益为 0 的频段不生成滤镜');
    expect(f, endsWith(']'));
    final cut = PlayerController.eqFilter([-3, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    expect(cut, 'format=format=floatp,lavfi=[equalizer=f=31:width_type=o:width=1:g=-3.0]');
  });

  test('峰值余量：没有响度信息的歌曲（QQ 音乐、酷狗、洛雪）也至少衰减 1.5 dB，防止削波破音', () {
    double db(double f) => 20 * math.log(f) / math.ln10;
    // 酷狗 / QQ 音乐：没有响度信息（增益系数 1），无论是否开启音量均衡都保留余量。
    expect(db(PlayerController.levelFactor(gain: 1, normalize: true, strength: 1)), closeTo(-1.5, 0.01));
    expect(db(PlayerController.levelFactor(gain: 1, normalize: false, strength: 1)), closeTo(-1.5, 0.01));
    // 网易云的响亮歌曲（响度增益 -9.3 dB → 衰减 1.3 dB）同样至少衰减 1.5 dB。
    final loud = PlayerController.gainFactor(-9.3);
    expect(db(PlayerController.levelFactor(gain: loud, normalize: true, strength: 1)), closeTo(-1.5, 0.01));
    // 衰减更多时按音量均衡。
    final louder = PlayerController.gainFactor(-14);
    expect(PlayerController.levelFactor(gain: louder, normalize: true, strength: 1), closeTo(louder, 1e-9));
  });
}
