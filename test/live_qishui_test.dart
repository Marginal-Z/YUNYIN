@Tags(['live'])
// 联网测试会输出接口返回的摘要，便于人工核对。
// ignore_for_file: avoid_print
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/qishui/qishui_source.dart';

void main() {
  test(
    '汽水音乐：公开接口冒烟（搜索、歌单、专辑、播放地址、歌词）',
    () async {
      final qs = QishuiSource();

      final pl = await qs.search('卡农', type: SearchType.playlist, limit: 5);
      print('歌单搜索: ${pl.playlists.map((p) => '${p.name}(${p.trackCount})').join(' | ')}');
      expect(pl.playlists, isNotEmpty);
      final list = await qs.playlist(pl.playlists.first.id);
      print('歌单 ${list.name}: ${list.tracks!.length} 首，封面 ${list.cover}');
      expect(list.tracks, isNotEmpty);

      final al = await qs.search('卡农', type: SearchType.album, limit: 5);
      expect(al.albums, isNotEmpty);
      final album = await qs.album(al.albums.first.id);
      print('专辑 ${album.name} - ${album.artist?.name}: ${album.songs!.length} 首');
      expect(album.songs, isNotEmpty);

      // 歌曲搜索可能被网关降级（返回空内容），此时只记录，不判失败。
      try {
        final r = await qs.search('LOFI Shining', type: SearchType.song, limit: 10);
        print('歌曲搜索: ${r.songs.take(5).map((s) => '${s.name} - ${s.artistText}${s.vip ? '（VIP）' : ''}').join(' | ')}');
      } on QishuiThrottled catch (e) {
        print('歌曲搜索：$e');
      }

      // 免费歌曲：整曲、未加密。
      const free = Song(id: '7054591422900471838', sourceId: 'qishui', name: 'LOFI', duration: Duration(milliseconds: 220000));
      final info = await qs.stream(free, AudioQuality.lossless);
      print('免费歌曲: ${info.quality} trial=${info.trial} ${info.url}');
      expect(info.url, startsWith('https://'));
      expect(info.trial, isFalse);
      expect(info.quality, AudioQuality.exhigh);
      final head = await Dio().get<List<int>>(info.url!, options: Options(responseType: ResponseType.bytes, headers: {...info.headers, 'Range': 'bytes=0-63'}));
      expect(String.fromCharCodes(head.data!.sublist(4, 8)), 'ftyp');
      final low = await qs.stream(free, AudioQuality.standard);
      expect(low.quality, AudioQuality.standard);

      final ly = await qs.lyrics(free);
      print('歌词 ${ly.lines.length} 行，翻译 ${ly.hasTranslation}: ${ly.lines.take(2).map((l) => '${l.text} / ${l.translation}').join(' | ')}');
      expect(ly.lines, isNotEmpty);

      // 会员歌曲：只有官方试听片段。
      const vip = Song(id: '7146240707408168993', sourceId: 'qishui', name: '因为爱情', fee: SongFee.vip);
      final trial = await qs.stream(vip, AudioQuality.exhigh);
      print('会员歌曲: ${trial.quality} trial=${trial.trial} ${trial.note}');
      expect(trial.trial, isTrue);
      final krc = await qs.lyrics(vip);
      print('逐字歌词 ${krc.lines.length} 行: ${krc.lines.first.text} ${krc.lines.first.words?.length} 字');
      expect(krc.wordSynced, isTrue);

      final feed = await qs.homeFeed();
      print('首页: 每日 ${feed.daily.length} 首，歌单 ${feed.playlists.map((p) => p.name).take(3).join(' | ')}');
      expect(feed.daily, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
