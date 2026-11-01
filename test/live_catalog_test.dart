@Tags(['live'])
// 联网测试：三个平台的榜单分组、榜单详情、歌单广场分类与分页、新碟。会输出接口返回的摘要，便于人工核对。
// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/music_source.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';

Future<void> checkCatalog(MusicSource source) async {
  final charts = await source.charts();
  final groups = <String?, int>{};
  for (final c in charts) {
    groups[c.group] = (groups[c.group] ?? 0) + 1;
  }
  print('${source.name} 榜单 ${charts.length} 个：$groups');
  expect(charts.length, greaterThan(10));
  expect(groups.keys.whereType<String>().length, greaterThan(2), reason: '榜单应按平台分组');

  // 每个分组打开第一个榜单。
  for (final g in groups.keys) {
    final c = charts.firstWhere((c) => c.group == g);
    final detail = await source.playlist(c.id);
    print('  [$g] ${detail.name}：${detail.tracks!.length} 首，第一名 ${detail.tracks!.first.name} - ${detail.tracks!.first.artistText}');
    expect(detail.tracks, isNotEmpty);
    expect(detail.name, isNot('酷狗榜单'));
  }

  final cats = await source.playlistCategories();
  final catGroups = {for (final c in cats) c.group};
  print('${source.name} 歌单分类 ${cats.length} 个，分组 $catGroups；前几个：${cats.take(8).map((c) => c.name).join(' ')}');
  expect(cats.length, greaterThan(10));

  final first = cats.first;
  final page1 = await source.categoryPlaylists(first.id, limit: 20);
  final page2 = await source.categoryPlaylists(first.id, offset: 20, limit: 20);
  print('  ${first.name}：第 1 页 ${page1.take(3).map((p) => p.name).join(' | ')}；第 2 页 ${page2.take(3).map((p) => p.name).join(' | ')}');
  expect(page1, isNotEmpty);
  expect(page2, isNotEmpty);
  expect(page2.first.id, isNot(page1.first.id), reason: '第二页应是不同的歌单');

  final other = cats[cats.length ~/ 2];
  final list = await source.categoryPlaylists(other.id, limit: 10);
  print('  ${other.name}：${list.take(3).map((p) => p.name).join(' | ')}');
  expect(list, isNotEmpty);
  expect(list.first.id, isNot(page1.first.id), reason: '不同分类应返回不同歌单');

  final pl = await source.playlist(list.first.id);
  print('  歌单详情：${pl.name} ${pl.tracks?.length} 首');
  expect(pl.tracks, isNotEmpty);

  if (source.supports(SourceFeature.newAlbums)) {
    final albums = await source.newAlbums(limit: 6);
    print('  新碟：${albums.map((a) => '${a.name}/${a.artist?.name}').join(' | ')}');
    expect(albums, isNotEmpty);
    final album = await source.album(albums.first.id);
    expect(album.songs, isNotEmpty);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    '网易云：榜单分组与歌单广场',
    () async {
      // 新的游客身份可能被网易云风控（-462）；可用 YUNYIN_PREFS 指向应用的 shared_preferences.json 复用已有身份。
      final prefs = Platform.environment['YUNYIN_PREFS'];
      if (prefs != null) {
        final j = jsonDecode(File(prefs).readAsStringSync()) as Map<String, dynamic>;
        SharedPreferences.setMockInitialValues({
          for (final e in j.entries)
            if (e.key.startsWith('flutter.') && e.value is String) e.key.substring(8): e.value as Object,
        });
      }
      final s = NeteaseSource();
      await s.init();
      await checkCatalog(s);
    },
    skip: '联网测试：flutter test --run-skipped --tags live',
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'QQ 音乐：榜单分组与歌单广场',
    () async {
      final s = QQMusicSource();
      await s.init();
      await checkCatalog(s);
    },
    skip: '联网测试：flutter test --run-skipped --tags live',
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    '酷狗：全部榜单、长榜单分页与歌单广场',
    () async {
      final s = KugouSource();
      await s.init();
      await checkCatalog(s);
      final top500 = await s.playlist('rank:8888');
      print('TOP500：${top500.name} ${top500.tracks!.length} 首');
      expect(top500.name, 'TOP500');
      expect(top500.tracks!.length, greaterThan(100));
    },
    skip: '联网测试：flutter test --run-skipped --tags live',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
