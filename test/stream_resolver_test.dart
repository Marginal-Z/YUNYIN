import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/lx/lx_sources.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/music_source.dart';
import 'package:yunyin/data/sources/source_policy.dart';

class _Fake extends MusicSource {
  _Fake(this.result);
  final Object result;
  @override
  String get id => 'qq';
  @override
  String get name => 'fake';
  @override
  String get description => '';
  @override
  Set<SourceFeature> get features => const {};
  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async => result is StreamInfo ? result as StreamInfo : throw result;
}

void main() {
  const song = Song(id: '0039MnYb0qxYhV:003Qui1q2u1Zho', sourceId: 'qq', name: '晴天', artists: [ArtistRef('a', '周杰伦')], duration: Duration(seconds: 269));
  test('平台只用自己的接口：完整地址、官方试听片段都照常返回', () async {
    expect((await resolveStream(_Fake(const StreamInfo(url: 'https://own/x')), song, AudioQuality.lossless)).url, 'https://own/x');
    final trial = await resolveStream(_Fake(const StreamInfo(url: 'https://own/trial', trial: true)), song, AudioQuality.lossless);
    expect(trial.trial, isTrue);
  });

  test('取不到地址时给出平台的原因；会员歌曲提示需要会员', () async {
    await expectLater(resolveStream(_Fake(Exception('需要登录')), song, AudioQuality.lossless), throwsA(predicate((e) => '$e'.contains('需要登录'))));
    await expectLater(resolveStream(_Fake(const StreamInfo()), song, AudioQuality.lossless), throwsA(predicate((e) => '$e'.contains('没有这首歌'))));
    const vip = Song(id: 'x', sourceId: 'qq', name: 'v', vip: true);
    await expectLater(resolveStream(_Fake(const StreamInfo()), vip, AudioQuality.lossless), throwsA(predicate((e) => '$e'.contains('会员'))));
  });

  test('洛雪 musicInfo：QQ 音乐与酷狗的歌曲 id 拆成各自的字段', () {
    final tx = LxSources.musicInfo(song, 'tx');
    expect(tx['songmid'], '0039MnYb0qxYhV');
    expect(tx['strMediaMid'], '003Qui1q2u1Zho');
    expect(tx['interval'], '04:29');
    expect((tx['meta'] as Map)['songId'], '0039MnYb0qxYhV');
    const kgSong = Song(id: 'abc123:556677:998', sourceId: 'kugou', name: 'x');
    final kg = LxSources.musicInfo(kgSong, 'kg');
    expect(kg['hash'], 'abc123');
    expect(kg['albumId'], '998');
    expect((kg['meta'] as Map)['hash'], 'abc123');
  });
}
