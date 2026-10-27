@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/local_library.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/local/local_source.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';

Song local(String name, String artist, Duration d) =>
    Song(id: 'x', sourceId: LocalSource.sourceId, name: name, artists: [ArtistRef('local:$artist', artist)], duration: d);

void main() {
  test('本地歌曲匹配网易云并取得歌词', () async {
    SharedPreferences.setMockInitialValues({});
    final source = NeteaseSource();
    await source.init();
    final lib = LocalLibrary()..online = source;
    final m = await lib.matchOnline(local('起风了', '买辣椒也用券', Duration.zero));
    expect(m, isNotNull);
    expect(m!.name, contains('起风了'));
    expect(m.artistText, contains('买辣椒也用券'));
    expect(m.coverUrl, startsWith('http'));
    final ly = await lib.online!.lyrics(m);
    expect(ly.lines.length, greaterThan(10));
    // 歌手与时长都对不上时不匹配；翻唱（歌名部分吻合、歌手不同）也不匹配。
    expect(await lib.matchOnline(local('晴天', '不存在的歌手甲乙丙', const Duration(minutes: 1))), isNull);
    expect(await lib.matchOnline(local('晴天', '周杰伦', const Duration(minutes: 4, seconds: 29))), isNull);

    // 没有标签、歌名来自文件名的常见形式。
    Future<String?> name(Song s) async => (await lib.matchOnline(s))?.artistText;
    // 带音轨编号、不知道歌手，但时长吻合。
    final d = m.duration;
    expect(await name(local('01. 起风了', '未知歌手', d)), contains('买辣椒也用券'));
    // “歌名 - 歌手”顺序被当成“歌手 - 歌名”解析。
    expect(await name(local('买辣椒也用券', '起风了', Duration.zero)), contains('买辣椒也用券'));
    // 歌名带版本后缀、多位歌手写在一起。
    expect(await name(local('起风了 (Live)', '买辣椒也用券/某人', d)), contains('买辣椒也用券'));
  }, skip: '联网测试：flutter test --run-skipped --tags live');
}
