import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/downloads.dart';
import 'package:yunyin/data/local_library.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/local/local_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/playlist/playlist_page.dart';
import 'package:yunyin/features/shell/nav.dart';
import 'package:yunyin/player/player_controller.dart';

void main() {
  testWidgets('歌单详情：封面渐隐、标题、操作按钮与按需构建的歌曲列表', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    await settings.init();
    final sm = SourceManager([LocalSource(LocalLibrary())]);
    final player = PlayerController(sm, settings);
    final songs = [
      for (var i = 0; i < 2000; i++) Song(id: '$i', sourceId: 'local', name: 'Song $i', artists: const [ArtistRef('a', 'G-DRAGON')]),
    ];
    final pl = PlaylistInfo(
      id: 'p',
      sourceId: 'local',
      name: 'Solstice 至日歌单',
      creator: '韩流之站',
      description: '充满活力与深情的韩流精选歌单，集结经典之作',
      playCount: 3880000,
      tracks: songs,
    );
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: sm),
          ChangeNotifierProvider.value(value: player),
          ChangeNotifierProvider.value(value: AppNav()),
          ChangeNotifierProvider.value(value: LocalLibrary()),
          ChangeNotifierProvider.value(value: DownloadManager(sm, settings)),
        ],
        child: PaletteScope(
          palette: Palette.light(AccentColor.red),
          child: MaterialApp(
            home: Material(
              child: PlaylistPage(route: PlaylistRoute('p', preview: pl)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Solstice 至日歌单'), findsWidgets);
    expect(find.text('2000 首歌曲'), findsWidgets);
    // 2000 首歌只构建屏幕上可见的几行。
    expect(find.text('Song 1999'), findsNothing);
    expect(find.text('Song 0'), findsOneWidget);
  });
}
