@Tags(['live'])
// ignore_for_file: avoid_print
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/song_matcher.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';

void main() {
  test(
    '本地歌曲在网易云、QQ 音乐、酷狗中依次匹配歌词与封面',
    () async {
      SharedPreferences.setMockInitialValues({});
      final netease = NeteaseSource();
      await netease.init();
      final sources = [netease, QQMusicSource(netease), KugouSource(netease)];
      // 周杰伦的歌不在网易云上架：应在 QQ 音乐或酷狗中匹配到。
      const local = Song(id: 'x', sourceId: 'local', name: '晴天', artists: [ArtistRef('a', '周杰伦')], duration: Duration(seconds: 269));
      Lyrics? found;
      for (final src in sources) {
        final m = await SongMatcher.match(src, local);
        print('${src.name}: ${m == null ? '未匹配' : '${m.name} - ${m.artistText} ${m.duration} ${m.coverUrl}'}');
        if (m == null) continue;
        final ly = await src.lyrics(m);
        print('  歌词 ${ly.lines.length} 行');
        if (ly.lines.isNotEmpty) {
          found = ly;
          break;
        }
      }
      expect(found, isNotNull);
      expect(found!.lines.length, greaterThan(10));
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: '联网测试：flutter test --run-skipped --tags live',
  );
}
