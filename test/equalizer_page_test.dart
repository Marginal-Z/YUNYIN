import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/settings/equalizer_page.dart';
import 'package:yunyin/features/shell/nav.dart';
import 'package:yunyin/player/player_controller.dart';

void main() {
  testWidgets('均衡器页：关闭时拖动频段会设置增益并自动打开；选预设同样打开', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    await settings.init();
    final sources = SourceManager([KugouSource()]);
    final player = PlayerController(sources, settings);
    expect(settings.eqEnabled, isFalse);
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: sources),
          ChangeNotifierProvider.value(value: player),
          ChangeNotifierProvider(create: (_) => AppNav()),
        ],
        child: PaletteScope(
          palette: Palette.light(AccentColor.red),
          child: const MaterialApp(home: Scaffold(body: EqualizerPage())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 第一个频段（31 Hz）：从中线往上拖。
    final band = find.text('31');
    expect(band, findsOneWidget);
    final column = tester.getRect(find.ancestor(of: band, matching: find.byType(Column)).first);
    await tester.dragFrom(Offset(column.center.dx, column.center.dy), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(settings.eqEnabled, isTrue, reason: '拖动频段自动打开均衡器');
    expect(settings.eqGains[0], greaterThan(0));
    settings.setFlag('eqEnabled', false);
    await tester.pumpAndSettle();
    await tester.tap(find.text(EqPreset.ordered.last.label));
    await tester.pumpAndSettle();
    expect(settings.eqEnabled, isTrue, reason: '选预设自动打开均衡器');
    expect(settings.eqPreset, EqPreset.ordered.last);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
