import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/player/lyrics_page.dart';
import 'package:yunyin/player/player_controller.dart';

void main() {
  testWidgets('歌词页可以上下拖动浏览', (tester) async {
    final settings = AppSettings();
    final player = PlayerController(SourceManager(const []), settings)
      ..lyrics = Lyrics([for (var i = 0; i < 40; i++) LyricLine(Duration(seconds: i * 3), '第 $i 行')])
      ..debugSetQueue([
        const Song(id: '1', sourceId: 'test', name: '测试歌曲', artists: [ArtistRef('a', '歌手')], duration: Duration(minutes: 3)),
      ], 0);
    player.position.value = const Duration(seconds: 60); // 第 20 行
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: player),
        ],
        child: PaletteScope(
          palette: Palette.light(AccentColor.red),
          child: const MaterialApp(home: LyricsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    final before = y('第 18 行');

    // 向下拖：看到前面的歌词。
    await tester.dragFrom(const Offset(195, 500), const Offset(0, 220));
    await tester.pump(const Duration(milliseconds: 100));
    expect(y('第 18 行'), greaterThan(before + 100), reason: '向下拖动后歌词应随手指下移');

    // 向上拖：看到后面的歌词。
    final mid = y('第 18 行');
    await tester.dragFrom(const Offset(195, 500), const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(y('第 18 行'), lessThan(mid - 200), reason: '向上拖动后歌词应随手指上移');
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
