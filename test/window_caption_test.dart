import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/features/desktop/window_controls.dart';

void main() {
  testWidgets('Windows 使用系统风格标题栏按钮，不显示红绿灯', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isMaximized' ? false : null,
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Row(children: [WindowControls(), WindowsCaptionButtons()]))));
    await tester.pump();
    expect(find.bySemanticsLabel('最小化'), findsOneWidget);
    expect(find.bySemanticsLabel('最大化'), findsOneWidget);
    expect(find.bySemanticsLabel('关闭'), findsOneWidget);
    // 红绿灯按钮不出现（否则会有两个“关闭”）。
    expect(find.bySemanticsLabel('关闭'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Linux 与 Windows 一样使用系统风格标题栏按钮，不显示红绿灯', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isMaximized' ? false : null,
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Row(children: [WindowControls(), WindowsCaptionButtons()]))));
    await tester.pump();
    expect(find.bySemanticsLabel('最小化'), findsOneWidget);
    expect(find.bySemanticsLabel('关闭'), findsOneWidget, reason: '只有一组按钮');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('macOS 使用红黄绿按钮；Android 平板的桌面布局不显示窗口按钮', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Row(children: [WindowControls(), WindowsCaptionButtons()]))));
    expect(find.bySemanticsLabel('最小化'), findsOneWidget);
    expect(find.bySemanticsLabel('向下还原'), findsNothing);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Row(children: [WindowControls(), WindowsCaptionButtons()]))));
    expect(find.bySemanticsLabel('关闭'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
