import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/login/kugou_login.dart';

void main() {
  testWidgets('酷狗粘贴完整 Cookie 后保存账号并正常关闭输入框', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final source = KugouSource();
    final sources = SourceManager([source]);
    var completed = false;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: sources,
        child: PaletteScope(
          palette: Palette.light(AccentColor.red),
          child: MaterialApp(
            home: Scaffold(body: KugouLoginCard(onDone: () => completed = true)),
          ),
        ),
      ),
    );
    await tester.tap(find.text('粘贴 Cookie 登录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'kg_mid=test-mid; kg_dfid=test-dfid; KuGoo=KugooID=123&t=test-token');
    await tester.tap(find.widgetWithText(TextButton, '登录'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(completed, isTrue);
    expect(source.user?.id, '123');
    await tester.pumpWidget(const SizedBox.shrink());
    sources.dispose();
  });
}
