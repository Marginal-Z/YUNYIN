import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/player/lyrics_view.dart';
import 'package:yunyin/player/player_controller.dart';

void main() {
  testWidgets('歌词随进度切换当前行并滚动', (tester) async {
    final settings = AppSettings();
    final player = PlayerController(SourceManager(const []), settings)
      ..lyrics = Lyrics([for (var i = 0; i < 30; i++) LyricLine(Duration(seconds: i * 3), '第 $i 行歌词，长度足够让它在窄屏上换成两行显示', translation: 'line $i')]);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: player),
        ],
        child: PaletteScope(
          palette: Palette.light(AccentColor.red),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(size: Size(390, 844)),
              child: LyricsView(desktop: false, anchor: 0.34),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 行'), findsOneWidget);
    double y() => tester.getTopLeft(find.textContaining('第 5 行')).dy;
    final start = y();

    // 进入第 10 行中段：各行以弹簧曲线上移，当前行到达锚点。
    player.position.value = const Duration(milliseconds: 31500);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(y(), lessThan(start));

    // 拖动后暂停跟随：换行时画面不动。
    await tester.drag(find.byType(LyricsView), const Offset(0, 300));
    await tester.pumpAndSettle();
    final browsing = y();
    player.position.value = const Duration(seconds: 40);
    await tester.pumpAndSettle();
    expect(y(), moreOrLessEquals(browsing, epsilon: 1));

    // 2.5 秒后恢复跟随。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(y(), lessThan(browsing));
    expect(tester.takeException(), isNull);
  });

  testWidgets('逐字歌词与长间奏圆点', (tester) async {
    final settings = AppSettings();
    final player = PlayerController(SourceManager(const []), settings)
      ..lyrics = Lyrics([
        for (var i = 0; i < 6; i++)
          LyricLine(
            Duration(seconds: 8 + i * 3),
            '第 $i 行',
            duration: const Duration(seconds: 2),
            words: [
              LyricWord(Duration(seconds: 8 + i * 3), const Duration(milliseconds: 800), '第 '),
              LyricWord(Duration(milliseconds: 8800 + i * 3000), const Duration(milliseconds: 1200), '$i 行'),
            ],
          ),
      ]);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: player),
        ],
        child: PaletteScope(
          palette: Palette.light(AccentColor.red),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(size: Size(390, 844)),
              child: LyricsView(desktop: false, anchor: 0.34),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 前奏 8 秒：显示圆点，第 0 行尚未成为当前行。
    expect(find.text('第 0 行'), findsOneWidget);
    player.position.value = const Duration(milliseconds: 9200);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('第 0 行'), findsNothing);
    expect(find.text('第 1 行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
