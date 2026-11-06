@Tags(['live'])
// 联网测试会输出接口返回的摘要，便于人工核对。
// ignore_for_file: avoid_print
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';

void main() {
  test('酷狗：注册设备后客户端接口直接给出播放地址（不需要人机验证），会员歌曲给出试听', () async {
    SharedPreferences.setMockInitialValues({});
    final kg = KugouSource();
    await kg.init();

    final r = await kg.search('晴天', type: SearchType.song, limit: 30);
    final free = r.songs.firstWhere((s) => s.fee == SongFee.free && s.playable);
    final vip = r.songs.firstWhere((s) => s.fee == SongFee.vip);
    print('免费: ${free.name} - ${free.artistText} ${free.id}');
    print('会员: ${vip.name} - ${vip.artistText} ${vip.id}');

    final info = await kg.stream(free, AudioQuality.exhigh);
    print('免费歌曲地址: ${info.url} 音质 ${info.quality} 试听 ${info.trial}');
    expect(info.url, isNotNull);
    expect(info.trial, isFalse);
    final prefs = await SharedPreferences.getInstance();
    print('已注册设备 dfid: ${prefs.getString('kugou.dfid')}');
    expect(prefs.getString('kugou.dfid'), isNotNull, reason: '设备注册（AES + RSA）成功');

    final trial = await kg.stream(vip, AudioQuality.exhigh);
    print('会员歌曲: ${trial.url} 试听 ${trial.trial}');
    expect(trial.trial, isTrue);

    final c1 = await kg.comments(vip);
    final c2 = await kg.comments(vip, offset: c1.next!);
    print('评论 ${c1.total} 条，第一页 ${c1.comments.length}，第二页 ${c2.comments.length}：${c1.comments.first.content}');
    expect(c1.total, greaterThan(1000));
    expect(c2.comments, isNotEmpty);
    expect(c2.comments.first.id, isNot(c1.comments.first.id));

    final qr = await kg.createQrLogin();
    print('扫码登录二维码: ${qr.content}');
    expect(await kg.checkQrLogin(qr), QrState.waiting);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
