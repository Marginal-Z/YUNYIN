@Tags(['live'])
// 联网测试会输出接口返回的摘要，便于人工核对。
// ignore_for_file: avoid_print
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';

void main() {
  test('QQ 音乐：未登录时安卓客户端方式取到官方试听片段（CDN 分发给出服务器地址），歌曲带付费类型与音质', () async {
    SharedPreferences.setMockInitialValues({});
    final qq = QQMusicSource();
    await qq.init();
    final r = await qq.search('晴 汪苏泷', type: SearchType.song, limit: 10);
    final song = r.songs.first;
    print('${song.name} - ${song.artistText} 付费类型 ${song.fee} 最高音质 ${song.maxQuality} 封面 ${song.coverUrl}');
    expect(song.maxQuality, isNotNull);
    final info = await qq.stream(song, AudioQuality.lossless);
    print('地址 ${info.url} 试听 ${info.trial}');
    expect(info.trial, isTrue);
    expect(info.url, startsWith('http'));
    final c1 = await qq.comments(song);
    final c2 = await qq.comments(song, offset: c1.next!);
    print('评论 ${c1.total}：第一页 ${c1.comments.length}，第二页 ${c2.comments.length}');
    expect(c2.comments.first.id, isNot(c1.comments.first.id));
  });
}
