import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/core/ui/icons.dart';
import 'package:yunyin/features/shell/tab_bar.dart';

void main() {
  testWidgets('标签栏：点击切换，按住拖动到另一个标签后松手切换', (tester) async {
    final selected = <int>[];
    var index = 0;
    await tester.binding.setSurfaceSize(const Size(400, 200));
    await tester.pumpWidget(
      PaletteScope(
        palette: Palette.light(AccentColor.red),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 310,
              child: StatefulBuilder(
                builder: (context, setState) => SlidingTabBar(
                  items: const [TabBarItem(YIcons.home, '首页'), TabBarItem(YIcons.discover, '发现'), TabBarItem(YIcons.library, '乐库')],
                  index: index,
                  onSelect: (i) => setState(() {
                    selected.add(i);
                    index = i;
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    expect(selected, [1]);

    // 从“发现”按住拖到“首页”，途中不切换，松手后切换。
    final from = tester.getCenter(find.text('发现'));
    final to = tester.getCenter(find.text('首页'));
    final g = await tester.startGesture(from);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(selected, [1]);
    await g.up();
    await tester.pumpAndSettle();
    expect(selected, [1, 0]);

    // 向右快速一甩：越过半格也会切到下一个标签。
    await tester.fling(find.text('首页'), const Offset(50, 0), 1500);
    await tester.pumpAndSettle();
    expect(selected.last, 1);
    expect(tester.takeException(), isNull);
  });
}
