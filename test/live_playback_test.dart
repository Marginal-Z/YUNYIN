@Tags(['live'])
// ignore_for_file: avoid_print
library;


import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';

void main() {
  test('网易云歌曲可以真正播放出声', () async {
    SharedPreferences.setMockInitialValues({});
    MediaKit.ensureInitialized();
    final s = NeteaseSource();
    await s.init();
    final chart = await s.soaringChart();
    var played = 0;
    for (final song in chart.tracks!.take(5)) {
      final info = await s.stream(song, AudioQuality.lossless);
      print('${song.name}: url=${info.url != null} trial=${info.trial}');
      if (info.url == null) continue;
      final p = Player();
      final errors = <String>[];
      p.stream.error.listen(errors.add);
      await p.setVolume(0);
      await p.open(Media(info.url!, httpHeaders: info.headers));
      final pos = await p.stream.position.firstWhere((d) => d > const Duration(seconds: 1)).timeout(const Duration(seconds: 20), onTimeout: () => Duration.zero);
      print('  position=$pos duration=${p.state.duration} errors=$errors');
      if (pos > Duration.zero) played++;
      await p.dispose();
    }
    final qr = await s.createQrLogin();
    print('扫码状态: ${await s.checkQrLogin(qr)}');
    expect(played, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
