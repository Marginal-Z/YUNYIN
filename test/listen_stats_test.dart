import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/listen_stats.dart';
import 'package:yunyin/data/models.dart';

Song song(String id, List<String> artists) =>
    Song(id: id, sourceId: 'test', name: '歌曲$id', artists: [for (final a in artists) ArtistRef(a, a)], duration: const Duration(minutes: 3));

void main() {
  test('按歌曲与歌手累计时长，30 秒计为一次播放', () {
    final s = ListenStats();
    s.record(song('1', ['甲']), const Duration(seconds: 20));
    s.record(song('1', ['甲']), const Duration(seconds: 20));
    s.record(song('2', ['甲', '乙']), const Duration(minutes: 2));
    expect(s.today, const Duration(minutes: 2, seconds: 40));
    expect(s.total, s.today);
    expect(s.thisWeek, s.today);
    final top = s.topSongs(5);
    expect(top.first.song.id, '2');
    expect(top.last.plays, 1);
    final artists = s.topArtists(5);
    expect(artists.first.$1, '甲');
    expect(artists.first.$2, const Duration(minutes: 1, seconds: 40));
    expect(s.lastDays(7).last.$2, s.today);
  });

  test('时长文字', () {
    expect(formatListen(Duration.zero), '0 分钟');
    expect(formatListen(const Duration(seconds: 20)), '不到 1 分钟');
    expect(formatListen(const Duration(minutes: 45)), '45 分钟');
    expect(formatListen(const Duration(hours: 2, minutes: 13)), '2 小时 13 分');
  });
}
