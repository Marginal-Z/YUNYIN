import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/features/splash/splash.dart';

Future<bool> _run(WidgetTester tester, {required bool full, required bool desktop, bool reduce = false, bool skip = false}) async {
  final size = desktop ? const Size(1280, 820) : const Size(390, 844);
  await tester.binding.setSurfaceSize(size);
  var done = false;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: reduce),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Splash(key: UniqueKey(), full: full, desktop: desktop, version: '1.0.0', onDone: () => done = true),
      ),
    ),
  );
  if (skip) {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('跳过'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return done;
  }
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull);
  return done;
}

void main() {
  testWidgets('启动动画：完整版约 2.4 秒后淡出结束', (tester) async {
    expect(await _run(tester, full: true, desktop: false), isTrue);
  });
  testWidgets('启动动画：缩短版与桌面端', (tester) async {
    expect(await _run(tester, full: false, desktop: false), isTrue);
    expect(await _run(tester, full: true, desktop: true), isTrue);
  });
  testWidgets('启动动画：减少动态效果时直接结束', (tester) async {
    expect(await _run(tester, full: true, desktop: false, reduce: true), isTrue);
  });
  testWidgets('启动动画：点击跳过立即结束', (tester) async {
    expect(await _run(tester, full: true, desktop: false, skip: true), isTrue);
  });
}
