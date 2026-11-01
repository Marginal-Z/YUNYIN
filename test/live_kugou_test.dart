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
      final kg = KugouSource();

      final r = await kg.search('起风了 买辣椒也用券', type: SearchType.song, limit: 10);
      expect(r.songs, isNotEmpty);
      final song = r.songs.firstWhere((s) => s.artistText.contains('买辣椒'));
      print('搜索: ${song.name} - ${song.artistText} ${song.duration} ${song.coverUrl}');
      expect(song.coverUrl, startsWith('https://'));

      final hot = await kg.hotSearches();
      print('热搜: ${hot.take(5).map((h) => h.keyword).join(' | ')}');
      expect(hot, isNotEmpty);

      final charts = await kg.charts();
      print('榜单: ${charts.map((c) => '${c.name}(${c.preview.length})').join(' | ')}');
      expect(charts.where((c) => c.preview.isNotEmpty).length, greaterThanOrEqualTo(5));
      final soaring = await kg.soaringChart();
      expect(soaring.tracks!.length, greaterThan(20));
      final feed = await kg.homeFeed();
      expect(feed.daily, isNotEmpty);

      final ly = await kg.lyrics(song);
      print('歌词 ${ly.lines.length} 行，同步 ${ly.synced}: ${ly.lines.take(3).map((l) => l.text).join(' / ')}');
      expect(ly.lines.length, greaterThan(10));

      // 完整的平台功能：歌手、专辑、歌单、评论与各类搜索。
      final artist = await kg.artist('kugou:周杰伦');
      print('歌手: ${artist.name} ${artist.hotSongs.length} 首 ${artist.avatar}');
      expect(artist.hotSongs, isNotEmpty);
      final albums = await kg.artistAlbums(artist.id, limit: 5);
      expect(albums, isNotEmpty);
      final album = await kg.album(albums.first.id);
      print('专辑: ${album.name} ${album.songs?.length} 首 ${album.cover}');
      final pls = await kg.recommendPlaylists(limit: 6);
      expect(pls, isNotEmpty);
      final pl = await kg.playlist(pls.first.id);
      print('歌单: ${pl.name} ${pl.tracks?.length} 首 ${pl.creator}');
      expect(pl.tracks, isNotEmpty);
      final cm = await kg.comments(pl.tracks!.first);
      final cmLatest = await kg.comments(pl.tracks!.first, sort: CommentSort.latest);
      print('评论: 共 ${cm.total} 条 ${cm.comments.firstOrNull?.userName}：${cm.comments.firstOrNull?.content}');
      expect(cmLatest.comments, isNotEmpty);
      final all = await kg.search('周杰伦');
      print('综合搜索: 歌曲 ${all.songs.length} 歌手 ${all.artists.length} 专辑 ${all.albums.length} 歌单 ${all.playlists.length}');
      expect(all.artists, isNotEmpty);
      expect(all.albums, isNotEmpty);
      expect(all.playlists, isNotEmpty);

      // 平台彼此独立：游客取不到完整地址时给出指向洛雪音源的说明，而不是换用其他平台的歌曲。
      try {
        final st = await kg.stream(r.songs.first, AudioQuality.standard);
        print('直接播放: ${st.url}');
      } catch (e) {
        print('游客播放: $e');
        expect('$e', contains('洛雪'));
      }
    },
    skip: '联网测试：flutter test --run-skipped --tags live',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
