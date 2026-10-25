import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/app_background.dart';
import '../shell/nav.dart';

/// 当前是桌面布局还是移动布局。
class LayoutScope extends InheritedWidget {
  const LayoutScope({super.key, required this.desktop, required super.child});

  final bool desktop;

  static bool isDesktop(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LayoutScope>()?.desktop ?? false;

  @override
  bool updateShouldNotify(LayoutScope old) => old.desktop != desktop;
}

/// 桌面布局断点。
const double kDesktopBreakpoint = 860;

/// 悬浮控件距离底部的距离（设计稿 22，叠加系统手势区）。
double chromeBottom(BuildContext context) {
  final inset = MediaQuery.viewPaddingOf(context).bottom;
  return 22 + math.max(0, inset - 10);
}

/// 内容需要为悬浮控件留出的底部空间。
double chromeClearance(BuildContext context, Chrome chrome) {
  final b = chromeBottom(context);
  return switch (chrome) {
    Chrome.full => b + 64 + 10 + 58 + 24,
    Chrome.navOnly => b + 64 + 24,
    Chrome.miniOnly => b + 58 + 24,
    Chrome.none => b + 12,
  };
}

/// 移动端页面骨架：光晕背景 + 滚动内容 + 固定在顶部的悬浮按钮。
class MobilePage extends StatelessWidget {
  const MobilePage({
    super.key,
    this.children = const [],
    this.slivers,
    this.chrome = Chrome.full,
    this.top = 26,
    this.horizontal = 20,
    this.overlay = const [],
    this.player = false,
    this.controller,
  });

  final List<Widget> children;

  /// 长列表页面使用 sliver（放在 [children] 之后）。
  final List<Widget>? slivers;
  final Chrome chrome;

  /// 内容距安全区顶部的距离（设计稿中的 main padding-top）。
  final double top;
  final double horizontal;

  /// 固定在页面上的悬浮元素（返回按钮等），坐标相对安全区顶部。
  final List<Widget> overlay;
  final bool player;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final bg = player ? GlowBackground.player(context) : const AppBackground();
    return Stack(
      children: [
        Positioned.fill(child: bg),
        Positioned.fill(
          child: slivers == null
              ? ListView(
                  controller: controller,
                  padding: EdgeInsets.fromLTRB(horizontal, safeTop + top, horizontal, chromeClearance(context, chrome)),
                  children: children,
                )
              : CustomScrollView(
                  controller: controller,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(horizontal, safeTop + top, horizontal, 0),
                      sliver: SliverList.list(children: children),
                    ),
                    for (final s in slivers!)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        sliver: s,
                      ),
                    SliverToBoxAdapter(child: SizedBox(height: chromeClearance(context, chrome))),
                  ],
                ),
        ),
        if (overlay.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: safeTop,
            child: SizedBox(
              height: 80,
              child: Stack(clipBehavior: Clip.none, children: overlay),
            ),
          ),
      ],
    );
  }
}

/// 桌面端内容区页面：左侧为侧边栏留出 262，右侧 28，顶部 78（设计稿）。
class DesktopPage extends StatelessWidget {
  const DesktopPage({super.key, this.children = const [], this.slivers, this.top = 78, this.controller});

  final List<Widget> children;
  final List<Widget>? slivers;
  final double top;
  final ScrollController? controller;

  static const double left = 262;
  static const double right = 28;
  static const double bottom = 14 + 76 + 28;

  @override
  Widget build(BuildContext context) {
    if (slivers == null) {
      return ListView(controller: controller, padding: EdgeInsets.fromLTRB(left, top, right, bottom), children: children);
    }
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(left, top, right, 0),
          sliver: SliverList.list(children: children),
        ),
        for (final s in slivers!) SliverPadding(padding: const EdgeInsets.fromLTRB(left, 0, right, 0), sliver: s),
        const SliverToBoxAdapter(child: SizedBox(height: bottom)),
      ],
    );
  }
}

/// 根据布局选择页面骨架，供两端共用的页面使用。
class AdaptivePage extends StatelessWidget {
  const AdaptivePage({
    super.key,
    this.children = const [],
    this.slivers,
    this.chrome = Chrome.full,
    this.mobileTop = 30,
    this.desktopTop = 78,
    this.overlay = const [],
  });

  final List<Widget> children;
  final List<Widget>? slivers;
  final Chrome chrome;
  final double mobileTop;
  final double desktopTop;
  final List<Widget> overlay;

  @override
  Widget build(BuildContext context) {
    if (LayoutScope.isDesktop(context)) return DesktopPage(top: desktopTop, slivers: slivers, children: children);
    return MobilePage(chrome: chrome, top: mobileTop, overlay: overlay, slivers: slivers, children: children);
  }
}

/// 卡片样式的长列表（整段共享一个圆角卡片背景与阴影）。
class SliverCard extends StatelessWidget {
  const SliverCard({super.key, required this.itemCount, required this.itemBuilder, required this.indent, this.header, this.radius = 26});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double indent;
  final Widget? header;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final hasHeader = header != null;
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(radius),
        border: p.isDark ? Border.all(color: const Color.fromRGBO(255, 255, 255, 0.07)) : null,
        boxShadow: [for (final s in p.cardShadow) BoxShadow(color: s.color, offset: s.offset, blurRadius: cssBlurRadius(s.blur))],
      ),
      sliver: SliverList.builder(
        itemCount: itemCount + (hasHeader ? 1 : 0),
        itemBuilder: (context, i) {
          if (hasHeader && i == 0) return header!;
          final idx = hasHeader ? i - 1 : i;
          final row = itemBuilder(context, idx);
          if (idx == 0 && !hasHeader) return row;
          return Stack(
            children: [
              row,
              Positioned(
                left: indent,
                right: 0,
                top: 0,
                child: Container(height: 1, color: p.separator),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// CSS blur 对应 Flutter [BoxShadow.blurRadius]（sigma = blur/2）。
double cssBlurRadius(double blur) => blur <= 1 ? 0 : (blur / 2 - 0.5) / 0.57735;
