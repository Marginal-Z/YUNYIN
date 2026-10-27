import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/core/ui/adaptive_scale.dart';
import 'package:yunyin/core/ui/feedback.dart';
import 'package:yunyin/features/shell/transitions.dart';

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;

  @override
  Widget build(BuildContext context) => Text('$n', textDirection: TextDirection.ltr);
}

/// 带一个持续运行的动画，用来检查 TickerMode 是否关闭。
class _TickerProbe extends StatefulWidget {
  const _TickerProbe({required this.label});

  final String label;

  @override
  State<_TickerProbe> createState() => _TickerProbeState();
}

class _TickerProbeState extends State<_TickerProbe> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  bool get ticking => _c.isAnimating && TickerMode.valuesOf(context).enabled;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label, textDirection: TextDirection.ltr);
}

void main() {
  testWidgets('界面缩放：窗口跨过设计尺寸时不重新挂载应用', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    const app = AdaptiveScale(desktopBreakpoint: 860, child: _Counter());
    await tester.pumpWidget(const MediaQuery(data: MediaQueryData(size: Size(1280, 820)), child: app));
    final state = tester.state<_CounterState>(find.byType(_Counter));
    state.n = 7;

    // 缩小到设计尺寸以下：界面整体缩放，但状态保持。
    await tester.pumpWidget(const MediaQuery(data: MediaQueryData(size: Size(1000, 680)), child: app));
    expect(tester.state<_CounterState>(find.byType(_Counter)), same(state));

    // 再放大回来。
    await tester.pumpWidget(const MediaQuery(data: MediaQueryData(size: Size(1280, 820)), child: app));
    expect(tester.state<_CounterState>(find.byType(_Counter)), same(state));
  });

  testWidgets('桌面端页面切换：旧页面先淡出，返回后状态保留', (tester) async {
    Widget app(List<String> pages) => Directionality(
      textDirection: TextDirection.ltr,
      child: Navigator(
        pages: [
          for (final p in pages) FadePage(key: ValueKey(p), child: p == 'A' ? const _Counter() : const Text('B', textDirection: TextDirection.ltr)),
        ],
        onDidRemovePage: (_) {},
      ),
    );
    // 页面在 Opacity 之下：取最近的 Opacity 祖先。
    double opacityOf(Finder f) => tester.widget<Opacity>(find.ancestor(of: f, matching: find.byType(Opacity)).first).opacity;

    await tester.pumpWidget(app(['A']));
    await tester.pumpAndSettle();
    final state = tester.state<_CounterState>(find.byType(_Counter));
    state.n = 3;

    await tester.pumpWidget(app(['A', 'B']));
    await tester.pump(const Duration(milliseconds: 120));
    final oldOpacity = opacityOf(find.byType(_Counter));
    final newOpacity = opacityOf(find.text('B'));
    // 进行到 40% 时旧页面已基本淡出，新页面正在淡入，两份文字不会以接近的透明度叠在一起。
    expect(oldOpacity, lessThan(0.25));
    expect(newOpacity, inExclusiveRange(0.3, 1.0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(opacityOf(find.text('B')), 1);
    // 完成后旧页面不在画面中（不透明路由遮住了它）。
    expect(find.byType(_Counter), findsNothing);

    await tester.pumpWidget(app(['A']));
    await tester.pump(const Duration(milliseconds: 120));
    expect(opacityOf(find.byType(_Counter)), greaterThan(0));
    await tester.pumpAndSettle();
    expect(opacityOf(find.byType(_Counter)), 1);
    expect(tester.state<_CounterState>(find.byType(_Counter)), same(state));
    expect(state.n, 3);
  });

  testWidgets('移动端标签：交叉淡化，隐藏的标签暂停动画并保留状态', (tester) async {
    Widget app(int index) => Directionality(
      textDirection: TextDirection.ltr,
      child: TabStack(
        index: index,
        children: [for (final t in ['首页', '发现', '乐库']) _TickerProbe(label: t)],
      ),
    );
    bool ticking(String t) => tester.state<_TickerProbeState>(find.byWidgetPredicate((w) => w is _TickerProbe && w.label == t, skipOffstage: false)).ticking;
    double opacity(String t) =>
        tester.widget<FadeTransition>(find.ancestor(of: find.text(t, skipOffstage: false), matching: find.byType(FadeTransition)).first).opacity.value;

    await tester.pumpWidget(app(0));
    final home = tester.state<_TickerProbeState>(find.byWidgetPredicate((w) => w is _TickerProbe && w.label == '首页'));
    expect(ticking('首页'), isTrue);
    expect(ticking('发现'), isFalse);
    expect(find.text('发现'), findsNothing);

    // 0 → 2：新标签在上层，淡入。
    await tester.pumpWidget(app(2));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('乐库'), findsOneWidget);
    expect(opacity('乐库'), inExclusiveRange(0.0, 1.0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('首页'), findsNothing);
    expect(ticking('首页'), isFalse);
    expect(ticking('乐库'), isTrue);

    // 2 → 0：旧标签在上层，改为淡出旧标签。
    await tester.pumpWidget(app(0));
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity('乐库'), inExclusiveRange(0.0, 1.0));
    expect(opacity('首页'), 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('乐库'), findsNothing);
    expect(tester.state<_TickerProbeState>(find.byWidgetPredicate((w) => w is _TickerProbe && w.label == '首页')), same(home));
  });

  testWidgets('入场动画：淡入后完全不透明，换 key 重新播放', (tester) async {
    Widget build(int k) => Directionality(
      textDirection: TextDirection.ltr,
      child: EntranceFade(key: ValueKey(k), child: const Text('内容')),
    );
    double opacity() => tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;

    await tester.pumpWidget(build(0));
    expect(opacity(), lessThan(0.1));
    await tester.pumpAndSettle();
    expect(opacity(), 1);

    await tester.pumpWidget(build(1));
    expect(opacity(), lessThan(0.1));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
  });
}
