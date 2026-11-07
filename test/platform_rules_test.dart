import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/listen_stats.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
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

  test('没有限幅器时按峰值智能增强：提升后不超过满刻度，不知道峰值时不提升', () {
    double out({required int db, required double? peak, double level = 1, double eq = 0}) =>
        PlayerController.softwareBoost(boostDb: db, peak: peak, level: level, eqPeakDb: eq);
    // 峰值 0.5（有 6 dB 余量）：+6 dB 几乎全部给出，结果不超过满刻度。
    expect(out(db: 6, peak: 0.5), closeTo(1.94, 0.01));
    expect(0.5 * out(db: 6, peak: 0.5), lessThanOrEqualTo(0.97));
    // 峰值 0.25：+6 dB 全部给出（不超过设定值）。
    expect(out(db: 6, peak: 0.25), closeTo(1.995, 0.01));
    // 已经接近满刻度的母带：不提升。
    expect(out(db: 10, peak: 0.99), 1);
    // 音量均衡已经压低了电平（0.5）：可以多提升一些，乘积仍不超过满刻度。
    expect(0.95 * 0.5 * out(db: 10, peak: 0.95, level: 0.5), lessThanOrEqualTo(0.97 + 1e-9));
    // 均衡器有 +6 dB 提升时按提升后的峰值计算。
    expect(out(db: 6, peak: 0.5, eq: 6), closeTo(1, 0.02));
    // 不知道峰值、或者没有开增强：不提升。
    expect(out(db: 6, peak: null), 1);
    expect(out(db: 0, peak: 0.3), 1);
  });

  test('QQ 音乐歌曲带上平台的响度增益与峰值，随队列保存', () {
    const song = Song(id: 'a', sourceId: 'qq', name: 'x', gainDb: -7.6, peak: 0.946);
    final back = Song.fromJson(song.toJson());
    expect(back.gainDb, -7.6);
    expect(back.peak, 0.946);
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

  test('酷狗会员：顶层 vip_type 6 为豪华 VIP，user_type 第 16 位为超级 VIP，busi_vip 中 tvip 为畅听、svip 为概念版', () {
    expect(KugouSource.kugouMembership({'vip_type': 6, 'vip_end_time': '2027-01-01 00:00:00', 'busi_vip': []}).title, '豪华 VIP');
    expect(KugouSource.kugouMembership({'vip_type': 6, 'vip_end_time': '2027-01-01 00:00:00'}).expires, DateTime(2027));
    expect(KugouSource.kugouMembership({'user_type': 16 | 1, 'vip_type': 6}).title, '超级 VIP');
    expect(
      KugouSource.kugouMembership({
        'busi_vip': [
          {'product_type': 'tvip', 'is_vip': 1, 'vip_end_time': '2026-12-31 23:59:59'},
        ],
      }).title,
      '畅听 VIP',
    );
    expect(
      KugouSource.kugouMembership({
        'busi_vip': [
          {'product_type': 'svip', 'is_vip': '1'},
        ],
      }).title,
      '概念版 VIP',
    );
    expect(KugouSource.kugouMembership({'is_vip': 1}).active, isTrue);
    final none = KugouSource.kugouMembership({
      'vip_type': 0,
      'busi_vip': [
        {'product_type': 'svip', 'is_vip': 0},
      ],
    });
    expect(none.active, isFalse);
  });

  test('QQ 音乐会员：8 元 / 12 元档、家庭与体验会员都算已开通', () {
    expect(QQMusicSource.qqMembership({'svip': 1, 'identity': {}})!.title, '超级会员');
    expect(QQMusicSource.qqMembership({'identity': {'eight': 1, 'eightEnd': '2027-02-01'}})!.title, '绿钻');
    expect(QQMusicSource.qqMembership({'identity': {'twelve': 1}})!.title, '豪华绿钻');
    expect(QQMusicSource.qqMembership({'identity': {'GroupVipFlag': 1}})!.active, isTrue);
    expect(QQMusicSource.qqMembership({'identity': {'vip': 0, 'level': 3}})!.active, isFalse);
    expect(QQMusicSource.qqMembership({}), isNull);
  });
}
