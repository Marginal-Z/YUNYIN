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
      final qq = QQMusicSource();
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

      try {
        final st = await qq.stream(r.songs.first, AudioQuality.standard);
        print('直接播放: ${st.url}');
      } catch (e) {
        print('游客播放: $e');
        expect('$e', contains('QQ 音乐'));
      }

      // 完整的平台功能：歌手、专辑、歌单、评论、新碟与各类搜索。
      final artistId = song.artists.first.id;
      final artist = await qq.artist(artistId);
      print('歌手: ${artist.name} ${artist.hotSongs.length} 首');
      expect(artist.hotSongs, isNotEmpty);
      final albums = await qq.artistAlbums(artistId, limit: 5);
      expect(albums, isNotEmpty);
      final album = await qq.album(song.album!.id);
      print('专辑: ${album.name} ${album.songs?.length} 首 ${album.publishTime}');
      expect(album.songs, isNotEmpty);
      final pls = await qq.recommendPlaylists(limit: 6);
      expect(pls, isNotEmpty);
      final pl = await qq.playlist(pls.first.id);
      print('歌单: ${pl.name} ${pl.tracks?.length} 首');
      expect(pl.tracks, isNotEmpty);
      expect(await qq.newAlbums(limit: 5), isNotEmpty);
      final hotCm = await qq.comments(song);
      final latest = await qq.comments(song, sort: CommentSort.latest);
      print('评论: 共 ${hotCm.total} 条，热门 ${hotCm.comments.first.userName}：${hotCm.comments.first.content}');
      expect(hotCm.comments, isNotEmpty);
      expect(latest.comments, isNotEmpty);
      final all = await qq.search('周杰伦');
      print('综合搜索: 歌曲 ${all.songs.length} 歌手 ${all.artists.length} 专辑 ${all.albums.length} 歌单 ${all.playlists.length}');
      expect(all.artists, isNotEmpty);
      expect(all.playlists, isNotEmpty);

      final ticket = await qq.createQrLogin();
      expect(ticket.image, isNotNull);
      expect(ticket.image!.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
      expect(await qq.checkQrLogin(ticket), QrState.waiting);
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: '联网测试：flutter test --run-skipped --tags live',
  );
}
