@Tags(['live'])
// 联网测试会输出接口返回的摘要，便于人工核对。
// ignore_for_file: avoid_print
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';

void main() {
  test(
    'QQ 音乐：搜索、热搜、排行榜、歌词、扫码二维码，未登录时换源播放',
    () async {
      SharedPreferences.setMockInitialValues({});
      final netease = NeteaseSource();
      await netease.init();
      final qq = QQMusicSource(netease);
      await qq.init();

      final r = await qq.search('晴天 周杰伦', type: SearchType.song, limit: 10);
      expect(r.songs, isNotEmpty);
      final song = r.songs.first;
      print('搜索: ${song.name} - ${song.artistText} ${song.duration} ${song.coverUrl} ${song.id}');
      expect(song.coverUrl, startsWith('https://'));

      final hot = await qq.hotSearches();
      print('热搜: ${hot.take(5).map((h) => h.keyword).join(' | ')}');
      expect(hot, isNotEmpty);

      final charts = await qq.charts();
      print('榜单: ${charts.take(5).map((c) => '${c.name}(${c.preview.length})').join(' | ')}');
      expect(charts.length, greaterThan(5));
      final top = await qq.playlist(charts.first.id);
      print('榜单详情: ${top.name} ${top.tracks!.length} 首，第一首 ${top.tracks!.first.name}');
      expect(top.tracks, isNotEmpty);

      final feed = await qq.homeFeed();
      expect(feed.daily, isNotEmpty);

      final ly = await qq.lyrics(song);
      print('歌词: ${ly.lines.length} 行，${ly.lines.skip(6).first.text}');
      expect(ly.lines.length, greaterThan(10));

      // 周杰伦的歌只在 QQ 音乐上架；换一批两边都有的歌测试换源播放（游客能播放其中免费的歌）。
      var playable = 0;
      for (final s in [
        for (final k in ['晚风 说唱版', '童话 光良', '小幸运 田馥甄']) ...(await qq.search(k, type: SearchType.song, limit: 4)).songs,
      ]) {
        try {
          final st = await qq.stream(s, AudioQuality.standard);
          print('换源播放 ${s.name}: ${st.url == null ? '无地址' : st.url!.substring(0, 40)}');
          if (st.url != null) playable++;
        } catch (e) {
          print('换源播放 ${s.name}: $e');
        }
      }
      expect(playable, greaterThan(0));

      final ticket = await qq.createQrLogin();
      expect(ticket.image, isNotNull);
      expect(ticket.image!.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
      expect(await qq.checkQrLogin(ticket), QrState.waiting);
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: '联网测试：flutter test --run-skipped --tags live',
  );
}
