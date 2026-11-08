import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/core/ui/transition_snapshot.dart';

void main() {
  testWidgets('推入时延后起步：首帧停在起点，之后从 0 平滑到 1，时长不变', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final c = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 300));
    final a = TransitionStart.of(c);
    TransitionStart.hold();
    c.forward();
    expect(a.value, 0);
    // 首帧很慢（60 毫秒）：原动画已经走了一截，包装后的动画仍从 0 开始。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(c.value, greaterThan(0.1));
    expect(a.value, 0);
    await tester.pump(const Duration(milliseconds: 100));
    final mid = a.value;
    expect(mid, inExclusiveRange(0, 1));
    expect(mid, lessThan(c.value));
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.isCompleted, isTrue);
    expect(a.value, 1);
    c.dispose();
  });

  testWidgets('不是推入（手势拖动后继续前进）时照常跟随原动画', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final c = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 300), value: 0.6);
    final a = TransitionStart.of(c);
    c.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(a.value, c.value);
    c.dispose();
  });
}
