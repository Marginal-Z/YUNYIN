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
}
