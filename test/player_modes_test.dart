import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/local_library.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/local/local_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/player/player_page.dart';
import 'package:yunyin/player/player_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PlayerController> pump(WidgetTester tester, PlayerStyle style, Size size) async {
    final settings = AppSettings();
    await settings.init();
    settings.setPlayerStyle(style);
    final songs = [
      for (var i = 0; i < 8; i++) Song(id: '$i', sourceId: 'local', name: '歌曲 $i', artists: [ArtistRef('a', '歌手 $i')]),
    ];
    final player = PlayerController(SourceManager([LocalSource(LocalLibrary())]), settings)..debugSetQueue(songs, 2);
    tester.view.physicalSize = size * 3;
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
          child: const MaterialApp(home: Material(child: PlayerPage())),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return player;
  }

  for (final style in [PlayerStyle.cardFlow, PlayerStyle.coverFlow, PlayerStyle.wall, PlayerStyle.minimal]) {
    for (final size in const [Size(390, 844), Size(844, 390)]) {
      testWidgets('播放样式 ${style.label}（${size.width > size.height ? '横屏' : '竖屏'}）正常显示', (tester) async {
        await pump(tester, style, size);
        expect(tester.takeException(), isNull);
        expect(find.text(style == PlayerStyle.wall ? '歌曲 2' : '歌曲 2'), findsWidgets);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('卡片流：向左滑动切到下一首', (tester) async {
    final player = await pump(tester, PlayerStyle.cardFlow, const Size(390, 844));
    expect(player.index, 2);
    await tester.drag(find.byType(PageView), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(player.index, 3);
    await tester.pumpWidget(const SizedBox());
  });
}
