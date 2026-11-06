import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/listen_stats.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';
import 'package:yunyin/player/player_controller.dart';

void main() {
  test('QQ 音乐：绿钻歌曲为 VIP，数字专辑与付费单曲为付费，兼容旧版字段', () {
    expect(
      QQMusicSource.qqFee({
        'pay': {'pay_month': 1, 'pay_play': 1, 'price_track': 200},
      }),
      SongFee.vip,
    );
    expect(
      QQMusicSource.qqFee({
        'pay': {'pay_month': 0, 'pay_play': 1, 'price_album': 2000},
      }),
      SongFee.paid,
    );
    expect(
      QQMusicSource.qqFee({
        'pay': {'pay_month': 0, 'pay_play': 0, 'price_track': 0},
      }),
      SongFee.free,
    );
    expect(
      QQMusicSource.qqFee({
        'pay': {'paytrackmouth': 1, 'payplay': 1},
      }),
      SongFee.vip,
    );
    expect(
      QQMusicSource.qqFee({
        'pay': {'payplay': 1, 'payalbumprice': 1500},
      }),
      SongFee.paid,
    );
  });

  test('网易云：fee 1 为黑胶 VIP，4 为付费专辑，8 为免费', () {
    expect(NeteaseSource.neteaseFee(1), SongFee.vip);
    expect(NeteaseSource.neteaseFee(4), SongFee.paid);
    expect(NeteaseSource.neteaseFee(8), SongFee.free);
    expect(NeteaseSource.neteaseFee(0), SongFee.free);
    expect(NeteaseSource.neteaseFee(null), SongFee.free);
  });

  test('旧版本保存的 vip 标记迁移为会员歌曲；付费类型与音质随队列保存', () {
    expect(Song.fromJson({'id': '1', 'sourceId': 'qq', 'name': 'a', 'vip': true}).fee, SongFee.vip);
    const song = Song(id: '1', sourceId: 'kugou', name: 'a', fee: SongFee.paid, maxQuality: AudioQuality.lossless);
    final back = Song.fromJson(song.toJson());
    expect(back.fee, SongFee.paid);
    expect(back.maxQuality, AudioQuality.lossless);
    expect(back.vip, isTrue);
    expect(Song.fromJson(const Song(id: '2', sourceId: 'qq', name: 'b').toJson()).fee, SongFee.free);
  });

  test('音频滤镜：均衡器在前，音量增强与限幅器在后；没有增强时不加限幅器', () {
    expect(PlayerController.audioFilter(), '');
    final eq = PlayerController.audioFilter(gains: [3, 0, 0, 0, 0, 0, 0, 0, 0, -2]);
    expect(eq, contains('equalizer=f=31'));
    expect(eq, isNot(contains('alimiter')));
    final boosted = PlayerController.audioFilter(gains: [3, 0, 0, 0, 0, 0, 0, 0, 0, 0], boostDb: 6);
    expect(boosted, startsWith('format=format=floatp,lavfi=['));
    expect(boosted.indexOf('equalizer'), lessThan(boosted.indexOf('volume=6dB')));
    expect(boosted.indexOf('volume=6dB'), lessThan(boosted.indexOf('alimiter')));
    expect(boosted, contains('level=0'), reason: '限幅器不做自动电平，不改变整体响度');
    expect(PlayerController.audioFilter(boostDb: 4), 'format=format=floatp,lavfi=[volume=4dB,alimiter=limit=0.944:attack=1:release=80:level=0]');
  });

  test('听歌统计：一天中的分布、平台分布、连续天数与听过的歌曲数', () {
    final stats = ListenStats();
    const a = Song(id: '1', sourceId: 'qq', name: 'a');
    const b = Song(id: '2', sourceId: 'kugou', name: 'b');
    stats.record(a, const Duration(minutes: 3));
    stats.record(b, const Duration(minutes: 1));
    final hour = DateTime.now().hour;
    expect(stats.hourly[hour], const Duration(minutes: 4));
    expect(stats.favoriteHour, hour);
    expect(stats.bySource.first, ('qq', const Duration(minutes: 3)));
    expect(stats.songCount, 2);
    expect(stats.playCount, 2, reason: '每首超过 30 秒计一次');
    expect(stats.streak, 1);
    expect(stats.longestStreak, 1);
    expect(stats.since(7), const Duration(minutes: 4));
    expect(stats.activeIn(30), 1);
  });
}
