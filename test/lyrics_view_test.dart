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

    // 进入第 10 行中段：当前行逐字填色，视图滚动到它。
    player.position.value = const Duration(milliseconds: 31500);
    await tester.pump();
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(scroll.pixels, greaterThan(0));

    // 拖动后暂停跟随。
    final before = scroll.pixels;
    await tester.drag(find.byType(Scrollable), const Offset(0, 300));
    await tester.pumpAndSettle();
    player.position.value = const Duration(seconds: 40);
    await tester.pumpAndSettle();
    expect(scroll.pixels, lessThan(before));

    // 2.5 秒后恢复跟随。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(scroll.pixels, greaterThan(before));
    expect(tester.takeException(), isNull);
  });
}
