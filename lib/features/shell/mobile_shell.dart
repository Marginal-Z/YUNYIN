import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator, Theme;
import 'package:provider/provider.dart';

import '../../core/perf_overlay.dart';
import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/app_background.dart';
import '../../core/ui/box.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import 'nav.dart';
import 'routes.dart';
import 'landscape_chrome.dart';
import 'tab_bar.dart';
import 'transitions.dart';
import '../common/song_cover.dart';
import '../../core/ui/motion.dart';
import '../desktop/player_bar.dart';

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
    final land = isPhoneLandscape(context);
    // 横屏极简布局：左侧竖向导航（全屏页面除外），内容区让出导航栏的宽度。
    final rail = land && (chrome != Chrome.none || nav.top is SearchRoute);
    final mq = MediaQuery.of(context);
    final railSpace = mq.padding.left + 12 + kLandscapeRailWidth + 8;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) nav.handleBack();
      },
      child: Stack(
        children: [
          if (land) const Positioned.fill(child: AppBackground()),
          Positioned.fill(
            left: rail ? railSpace : 0,
            child: MediaQuery(
              // 页面按让出导航栏后的实际宽度排版。
              data: rail ? mq.copyWith(size: Size(mq.size.width - railSpace, mq.size.height), padding: mq.padding.copyWith(left: 0)) : mq,
              child: TabStack(
                index: nav.tab,
                children: [
                  for (var i = 0; i < 3; i++)
                    Navigator(
                      key: _keys[i],
                      // 每个页面单独一组背景截取：转场时上下两个页面都在绘制，各自的玻璃读取各自的背景。
                      pages: [
                        for (final r in nav.stacks[i])
                          SpringPage<void>(
                            key: ValueKey(r.uid),
                            child: BackdropGroup(child: buildMobileRoute(r)),
                          ),
                      ],
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
          ),
          if (land) ...[
            // 横屏：左侧竖向导航，底部整行播放控制条。
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Motion.spring,
              left: rail ? mq.padding.left + 12 : -kLandscapeRailWidth - 20,
              top: mq.padding.top + 12,
              bottom: bottom,
              width: kLandscapeRailWidth,
              child: const Align(alignment: Alignment.topCenter, child: LandscapeNavRail()),
            ),
            // 横屏播放条没有底板：后面的页面在底部渐隐。
            Positioned(
              left: rail ? railSpace - 8 : 0,
              right: 0,
              bottom: 0,
              height: (kLandscapeBarHeight + bottom) / 0.6,
              child: AnimatedOpacity(opacity: showMini ? 1 : 0, duration: const Duration(milliseconds: 200), child: const PlayerBarFade()),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Motion.spring,
              left: rail ? railSpace : 16,
              right: 16 + mq.padding.right,
              bottom: showMini ? bottom : -kLandscapeBarHeight - 40,
              child: IgnorePointer(
                ignoring: !showMini,
                child: AnimatedOpacity(
                  opacity: showMini ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const _OverPage(child: LandscapePlayerBar()),
                ),
              ),
            ),
          ] else if (!PerfLab.noChrome) ...[
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Motion.spring,
              left: 12 + barInset,
              right: 12 + barInset,
              bottom: chrome == Chrome.miniOnly ? bottom + 2 : bottom + 74,
              child: IgnorePointer(
                ignoring: !showMini,
                child: AnimatedOpacity(
                  opacity: showMini ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const _OverPage(child: MiniPlayer()),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Motion.spring,
              left: 16 + barInset,
              right: 16 + barInset,
              bottom: showNav ? bottom : -100,
              child: const _OverPage(child: _BottomBar()),
            ),
          ],
        ],
      ),
    );
  }
}

/// 歌单、专辑、电台与收藏页的背景由封面取色、始终是深色（浅色主题下也是）：浮在其上的导航栏与迷你播放条
/// 改用深色外观（浅色文字、深色玻璃色调），否则浅色主题的深色文字落在深色页面上看不清。
class _OverPage extends StatelessWidget {
  const _OverPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = context.select<AppNav, AppRoute>((n) => n.top);
    final darkPage = top is PlaylistRoute || top is AlbumRoute || top is RadioRoute || top is CollectionRoute;
    if (!darkPage || Palette.of(context).isDark) return child;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(colorScheme: theme.colorScheme.copyWith(brightness: Brightness.dark)),
      child: PaletteScope(palette: context.read<AppSettings>().palette(true), child: child),
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
            legible: true,
            child: YIcon(YIcons.search, size: 24, strokeWidth: 2.3, color: p.text),
          ),
        ),
      ],
    );
  }
}

/// 玻璃上的文字描边：与背景相反的柔和光晕，保证在任何内容上都清晰。

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
      legible: true,
      padding: const EdgeInsets.fromLTRB(7, 7, 8, 7),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              onTap: () => openPlayer(context),
              scale: 1,
              child: Row(
                children: [
                  SongCover(song, size: 42, circle: true),
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
                          style: ts(12, weight: w500, color: p.text2),
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
          if (player.loading)
            SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: p.text)),
              ),
            )
          else
            YIconButton(player.playing ? YIcons.pause : YIcons.play, label: player.playing ? '暂停' : '播放', onTap: player.toggle),
          YIconButton(YIcons.next, label: '下一首', onTap: player.next),
        ],
      ),
    );
  }
}
