import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/core/ui/skeleton.dart';

void main() {
  for (final (name, widget, size) in [
    ('列表', const SkeletonList(), const Size(390, 844)),
    ('评论', const SkeletonComments(), const Size(390, 844)),
    ('移动端首页', const SkeletonHome(), const Size(390, 900)),
    ('桌面端首页', const SkeletonHome(desktop: true), const Size(1200, 900)),
  ]) {
    testWidgets('骨架屏：$name 正常布局并播放扫光', (tester) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        PaletteScope(
          palette: Palette.light(AccentColor.red),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: widget),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(Bone), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
