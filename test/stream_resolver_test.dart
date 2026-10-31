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
  tearDown(() => SourcePolicy.custom = null);

  test('平台自己能播放时不使用洛雪音源', () async {
    var called = false;
    SourcePolicy.custom = (s, q) async {
      called = true;
      return const StreamInfo(url: 'https://lx/x');
    };
    final r = await resolveStream(_Fake(const StreamInfo(url: 'https://own/x')), song, AudioQuality.lossless);
    expect(r.url, 'https://own/x');
    expect(called, isFalse);
  });

  test('平台需要登录或只有试听时用洛雪音源获取同一首歌', () async {
    SourcePolicy.custom = (s, q) async => StreamInfo(url: 'https://lx/${s.id}');
    expect((await resolveStream(_Fake(Exception('需要登录')), song, AudioQuality.lossless)).url, 'https://lx/${song.id}');
    expect((await resolveStream(_Fake(const StreamInfo(url: 'https://own/trial', trial: true)), song, AudioQuality.lossless)).url, startsWith('https://lx/'));
  });

  test('洛雪音源也失败时：有试听片段播放试听，否则给出平台的原因', () async {
    SourcePolicy.custom = (s, q) async => throw Exception('音源超时');
    expect((await resolveStream(_Fake(const StreamInfo(url: 'https://own/trial', trial: true)), song, AudioQuality.lossless)).trial, isTrue);
    await expectLater(resolveStream(_Fake(Exception('需要登录')), song, AudioQuality.lossless), throwsA(predicate((e) => '$e'.contains('需要登录'))));
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
