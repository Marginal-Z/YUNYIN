@Tags(['live'])
// 联网测试会输出接口返回的摘要，便于人工核对。
// ignore_for_file: avoid_print
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';

void main() {
  test(
    '酷狗：搜索、排行榜、歌词，换源播放',
    () async {
      SharedPreferences.setMockInitialValues({});
      final netease = NeteaseSource();
      await netease.init();
      final kg = KugouSource(netease);

      final r = await kg.search('起风了 买辣椒也用券', type: SearchType.song, limit: 10);
      expect(r.songs, isNotEmpty);
      final song = r.songs.firstWhere((s) => s.artistText.contains('买辣椒'));
      print(
        '搜索: ${song.name} - ${song.artistText} ${song.duration} ${song.coverUrl}',
      );
      expect(song.coverUrl, startsWith('https://'));

      final hot = await kg.hotSearches();
      print('热搜: ${hot.take(5).map((h) => h.keyword).join(' | ')}');
      expect(hot, isNotEmpty);

      final charts = await kg.charts();
      print(
        '榜单: ${charts.map((c) => '${c.name}(${c.preview.length})').join(' | ')}',
      );
      expect(
        charts.where((c) => c.preview.isNotEmpty).length,
        greaterThanOrEqualTo(5),
      );
      final soaring = await kg.soaringChart();
      expect(soaring.tracks!.length, greaterThan(20));
      final feed = await kg.homeFeed();
      expect(feed.daily, isNotEmpty);

      final ly = await kg.lyrics(song);
      print(
        '歌词 ${ly.lines.length} 行，同步 ${ly.synced}: ${ly.lines.take(3).map((l) => l.text).join(' / ')}',
      );
      expect(ly.lines.length, greaterThan(10));

      // 换源播放：酷狗搜索结果在网易云中匹配到同一首歌后取得播放地址（新歌多为会员专享，游客没有地址，属正常）。
      var playable = 0;
      final candidates = (await kg.search(
        '晚风',
        type: SearchType.song,
        limit: 8,
      )).songs;
      for (final s in candidates) {
        try {
          final st = await kg.stream(s, AudioQuality.standard);
          print(
            '播放 ${s.name}: ${st.url == null ? '无地址' : st.url!.substring(0, 40)} 试听 ${st.trial}',
          );
          if (st.url != null) playable++;
        } catch (e) {
          print('播放 ${s.name}: $e');
        }
      }
      expect(playable, greaterThan(0));
    },
    skip: '联网测试：flutter test --run-skipped --tags live',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
