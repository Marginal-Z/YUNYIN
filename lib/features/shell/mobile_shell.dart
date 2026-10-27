import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import 'nav.dart';
import 'routes.dart';
import 'tab_bar.dart';

/// 移动端外壳：三个标签各自的导航栈 + 悬浮玻璃导航栏与迷你播放条。
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  final _keys = List.generate(3, (_) => GlobalKey<NavigatorState>());

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    final chrome = nav.top.chrome;
    final bottom = chromeBottom(context);
    final hasSong = context.select<PlayerController, bool>((p) => p.current != null);
    final showNav = chrome == Chrome.full || chrome == Chrome.navOnly;
    final showMini = hasSong && (chrome == Chrome.full || chrome == Chrome.miniOnly);

    // 横屏或平板上导航栏与迷你播放条不必铺满整行，限制在 560 宽并居中。
    final barInset = math.max(0.0, (MediaQuery.sizeOf(context).width - 560) / 2);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) nav.handleBack();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: nav.tab,
              children: [
                for (var i = 0; i < 3; i++)
                  Navigator(
                    key: _keys[i],
                    pages: [for (final r in nav.stacks[i]) CupertinoPage<void>(key: ValueKey(r.uid), child: buildMobileRoute(r))],
                    onDidRemovePage: (page) {
                      final key = page.key;
                      if (key is ValueKey<int>) {
                        final r = nav.stacks[i].where((x) => x.uid == key.value).firstOrNull;
                        if (r != null) nav.removed(i, r);
                      }
                    },
                  ),
              ],
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: 12 + barInset,
            right: 12 + barInset,
            bottom: chrome == Chrome.miniOnly ? bottom + 2 : bottom + 74,
            child: IgnorePointer(
              ignoring: !showMini,
              child: AnimatedOpacity(opacity: showMini ? 1 : 0, duration: const Duration(milliseconds: 200), child: const MiniPlayer()),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: 16 + barInset,
            right: 16 + barInset,
            bottom: showNav ? bottom : -100,
            child: const _BottomBar(),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final nav = context.watch<AppNav>();
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: '主导航',
            container: true,
            child: SlidingTabBar(
              items: const [TabBarItem(YIcons.home, '首页'), TabBarItem(YIcons.discover, '发现'), TabBarItem(YIcons.library, '乐库')],
              index: nav.tab,
              onSelect: nav.switchTab,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Pressable(
          onTap: () => nav.push(SearchRoute()),
          scale: 0.94,
          semanticLabel: '搜索',
          child: Glass(
            radius: 32,
            width: 64,
            height: 64,
            alignment: Alignment.center,
            child: YIcon(YIcons.search, size: 24, color: p.text),
          ),
        ),
      ],
    );
  }
}

/// 迷你播放条（高 58，玻璃）。
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final song = player.current;
    return Glass(
      radius: 29,
      height: 58,
      padding: const EdgeInsets.fromLTRB(7, 7, 8, 7),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              onTap: () => openPlayer(context),
              scale: 1,
              child: Row(
                children: [
                  Cover(song?.coverUrl, size: 42, circle: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song?.name ?? '',
                          style: ts(14, weight: w600, color: p.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song?.artistText ?? '',
                          style: ts(12, color: p.text4),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          YIconButton(player.playing ? YIcons.pause : YIcons.play, label: player.playing ? '暂停' : '播放', onTap: player.toggle),
          YIconButton(YIcons.next, label: '下一首', onTap: player.next),
        ],
      ),
    );
  }
}
