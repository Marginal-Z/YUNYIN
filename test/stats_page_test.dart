import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/listen_stats.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/shell/nav.dart';
import 'package:yunyin/features/stats/stats_page.dart';

void main() {
  ListenStats sample() {
    final stats = ListenStats();
    for (var i = 0; i < 12; i++) {
      stats.record(
        Song(
          id: '$i',
          sourceId: i.isEven ? 'qq' : 'kugou',
          name: '一首名字很长很长很长很长的歌曲 $i',
          artists: [ArtistRef('$i', '歌手 ${i % 3}')],
        ),
        Duration(minutes: 3 + i),
      );
    }
    return stats;
  }

  Widget app(ListenStats stats, Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: AppSettings()),
      ChangeNotifierProvider.value(value: SourceManager([NeteaseSource(), QQMusicSource(), KugouSource()])),
      ChangeNotifierProvider.value(value: stats),
      ChangeNotifierProvider.value(value: AppNav()),
    ],
    child: PaletteScope(
      palette: Palette.light(AccentColor.red),
      child: MaterialApp(home: Material(child: child)),
    ),
  );

  for (final (name, size) in [('手机', Size(390, 844)), ('窄屏手机', Size(320, 640))]) {
    testWidgets('听歌统计在$name上正常显示，切换时间范围', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final stats = sample();
      await tester.pumpWidget(app(stats, const StatsPage()));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(find.text('近 7 天收听'), findsOneWidget);
      // 滚到底部：各部分（分布图、平台分布、排行）依次构建，没有溢出。
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('平台分布', skipOffstage: false), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('近 30 天'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('近 30 天收听'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      stats.dispose();
    });
  }

  testWidgets('听歌海报按固定尺寸排版，没有溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final stats = sample();
    await tester.pumpWidget(app(stats, Center(child: ListenPoster(stats: _Stats.instance, period: StatsPeriod.week))));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('最常听的歌手'), findsOneWidget);
    expect(tester.getSize(find.byType(ListenPoster)), const Size(360, 640));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    stats.dispose();
    _Stats.instance.dispose();
  });
}

/// 海报测试用的统计数据。
abstract final class _Stats {
  static final instance = () {
    final stats = ListenStats();
    for (var i = 0; i < 6; i++) {
      stats.record(Song(id: '$i', sourceId: 'netease', name: '很长很长很长很长很长很长的歌名 $i', artists: const [ArtistRef('1', '歌手')]), Duration(minutes: 10 - i));
    }
    return stats;
  }();
}
