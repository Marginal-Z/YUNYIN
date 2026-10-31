import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/cloud/cloud_drives.dart';
import 'package:yunyin/features/cloud/cloud_pages.dart';
import 'package:yunyin/features/shell/nav.dart';

Future<void> _pump(
  WidgetTester tester,
  CloudDrives drives,
  AppNav nav,
  Widget page,
) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AppSettings()),
        ChangeNotifierProvider.value(value: drives),
        ChangeNotifierProvider.value(value: nav),
      ],
      child: PaletteScope(
        palette: Palette.light(AccentColor.red),
        child: MaterialApp(home: Material(child: page)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('网盘列表：空状态与已挂载的网盘', (tester) async {
    final drives = CloudDrives();
    final nav = AppNav();
    await _pump(tester, drives, nav, const CloudDrivesPage());
    expect(find.text('还没有挂载网盘'), findsOneWidget);
    expect(tester.takeException(), isNull);

    drives.upsert(
      const CloudDrive(
        id: 'a',
        kind: CloudKind.jianguoyun,
        name: '坚果云',
        url: 'https://dav.jianguoyun.com/dav/',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('坚果云'), findsOneWidget);
    await tester.tap(find.text('坚果云'));
    expect(nav.top, isA<CloudBrowseRoute>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('添加网盘：选择类型填入默认地址并保存', (tester) async {
    final drives = CloudDrives();
    final nav = AppNav()..push(CloudEditRoute());
    await _pump(tester, drives, nav, const CloudEditPage());
    expect(find.text('http://192.168.1.2:5244/dav'), findsOneWidget);
    await tester.ensureVisible(find.text('坚果云'));
    await tester.tap(find.text('坚果云'));
    await tester.pumpAndSettle();
    expect(find.text('https://dav.jianguoyun.com/dav/'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(2), 'me@example.com');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(drives.drives.single.kind, CloudKind.jianguoyun);
    expect(drives.drives.single.username, 'me@example.com');
    expect(drives.drives.single.name, '坚果云');
    expect(tester.takeException(), isNull);
  });
}
