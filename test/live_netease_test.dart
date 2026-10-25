@Tags(['live'])
// 联网测试会输出接口返回的摘要，便于人工核对。
// ignore_for_file: avoid_print
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';

void main() {
  test('网易云接口联网冒烟测试', () async {
    SharedPreferences.setMockInitialValues({});
    final s = NeteaseSource();
    await s.init();
    final pls = await s.recommendPlaylists(limit: 3);
    print('推荐歌单: ${pls.map((p) => p.name).join(' | ')}');
    final r = await s.search('晚风', type: SearchType.song, limit: 3);
    print('搜索: ${r.songs.map((x) => '${x.name}-${x.artistText}').join(' | ')}');
    final song = r.songs.first;
    final st = await s.stream(song, AudioQuality.exhigh);
    print('播放地址: ${st.url?.substring(0, 40)} trial=${st.trial}');
    final ly = await s.lyrics(song);
    print('歌词行数: ${ly.lines.length}');
    final c = await s.comments(song);
    print('评论总数: ${c.total}, 第一条: ${c.comments.firstOrNull?.content}');
    final hot = await s.hotSearches();
    print('热搜: ${hot.take(3).map((h) => h.keyword).join(' | ')}');
    final chart = await s.soaringChart();
    print('飙升榜: ${chart.tracks?.length} 首');
    final qr = await s.createQrLogin();
    print('二维码: ${qr.content}');
    final artist = await s.artist(song.artists.first.id);
    print('歌手: ${artist.name} 粉丝=${artist.fans} 热门=${artist.hotSongs.length}');
    final albums = await s.artistAlbums(artist.id);
    print('专辑数: ${albums.length}');
    if (song.album != null) {
      final al = await s.album(song.album!.id);
      print('专辑: ${al.name} ${al.songs?.length} 首');
    }
    final na = await s.newAlbums(limit: 3);
    print('新碟: ${na.map((a) => a.name).join(' | ')}');
    final radios = await s.hotRadios(limit: 2);
    print('电台: ${radios.map((r) => r.name).join(' | ')}');
    final prog = await s.radioPrograms(radios.first);
    print('节目: ${prog.tracks?.length}');
    final charts = await s.charts();
    print('榜单: ${charts.length}');
    final pl = await s.playlist(pls.first.id);
    print('歌单曲目: ${pl.tracks?.length} / ${pl.trackCount}');
    expect(pls, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
