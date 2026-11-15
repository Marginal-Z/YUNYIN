import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/login/login_page.dart';
import 'package:yunyin/features/shell/nav.dart';

Future<void> _pump(WidgetTester tester, SourceManager sources) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  final settings = AppSettings();
  await settings.init();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sources),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: PaletteScope(
        palette: Palette.light(AccentColor.red),
        child: const MaterialApp(home: Scaffold(body: LoginPage())),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('网易云登录页只显示网易云的扫码，不出现酷狗的登录卡片，也没有验证码与密码登录', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sources = SourceManager([NeteaseSource(), KugouSource()]);
    await _pump(tester, sources);
    expect(find.textContaining('网易云音乐 App 扫码'), findsOneWidget);
    expect(find.text('扫码登录'), findsOneWidget);
    expect(find.textContaining('酷狗'), findsNothing);
    expect(find.text('获取验证码'), findsNothing);
    expect(find.text('其他登录方式'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
