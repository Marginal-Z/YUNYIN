import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/listen_stats.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/profile/profile_page.dart';
import 'package:yunyin/features/shell/nav.dart';

void main() {
  testWidgets('个人中心：会员卡片随平台切换，可切换平台模式', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final netease = NeteaseSource();
    final sm = SourceManager([netease, QQMusicSource(netease), KugouSource(netease)]);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: AppSettings()),
          ChangeNotifierProvider.value(value: sm),
          ChangeNotifierProvider.value(value: ListenStats()),
          ChangeNotifierProvider.value(value: AppNav()),
        ],
        child: PaletteScope(
          palette: Palette.light(AccentColor.red),
          child: const MaterialApp(home: Material(child: ProfilePage())),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('网易云音乐会员'), findsOneWidget);
    expect(find.text('登录后查看会员信息'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('酷狗音乐'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(sm.current.id, 'kugou');
    expect(find.text('酷狗音乐会员'), findsOneWidget);
    expect(find.text('游客模式'), findsWidgets);

    await tester.tap(find.text('QQ 音乐'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(sm.current.id, 'qq');
    expect(find.text('QQ 音乐会员'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
