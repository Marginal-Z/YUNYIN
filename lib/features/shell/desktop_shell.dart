import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/app_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../data/sources/music_source.dart';
import '../../data/sources/source_manager.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../desktop/player_bar.dart';
import '../desktop/window_controls.dart';
import '../player/player_page.dart';
import '../search/search_page.dart';
import 'nav.dart';
import 'routes.dart';

/// 桌面端外壳：玻璃侧边栏 + 顶栏 + 内容区 + 底部播放条。
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _navKey = GlobalKey<NavigatorState>();
  bool _mini = false;
  Size? _restoreSize;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleMini() async {
    if (!isDesktopPlatform) {
      setState(() => _mini = !_mini);
      return;
    }
    if (!_mini) {
      _restoreSize = await windowManager.getSize();
      setState(() => _mini = true);
      await windowManager.setMinimumSize(const Size(360, 96));
      await windowManager.setSize(const Size(420, 96));
      await windowManager.setAlwaysOnTop(true);
    } else {
      setState(() => _mini = false);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(960, 640));
      await windowManager.setSize(_restoreSize ?? const Size(1280, 820));
    }
  }

  /// 播放相关快捷键在应用层处理（见 PlaybackShortcuts），这里只处理搜索与迷你模式。
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (!ctrl) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.keyF) {
      if (_mini) _toggleMini();
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.keyM) {
      _toggleMini();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: _mini ? _MiniWindow(onRestore: _toggleMini) : _full(context, nav),
    );
  }

  Widget _full(BuildContext context, AppNav nav) {
    final p = Palette.of(context);
    return AppBackground(
      scale: 2.4,
      child: Stack(
        children: [
          Positioned.fill(
            child: Navigator(
              key: _navKey,
              pages: [for (final r in nav.stacks[0]) _FadePage(key: ValueKey(r.uid), child: buildDesktopRoute(r))],
              onDidRemovePage: (page) {
                final key = page.key;
                if (key is ValueKey<int>) {
                  final r = nav.stacks[0].where((x) => x.uid == key.value).firstOrNull;
                  if (r != null) nav.removed(0, r);
                }
              },
            ),
          ),
          // 顶栏背后的拖动区域。
          const Positioned(left: 252, right: 0, top: 0, height: 72, child: WindowDragArea(child: SizedBox.expand())),
          Positioned(
            left: 262,
            right: 28,
            top: 16,
            height: 44,
            child: Row(
              children: [
                GlassButton(
                  YIcons.back,
                  size: 40,
                  iconSize: 20,
                  strokeWidth: 1.9,
                  label: '后退',
                  color: nav.canBack ? p.text : p.text2,
                  onTap: nav.canBack ? nav.pop : null,
                ),
                const SizedBox(width: 10),
                GlassButton(
                  YIcons.forward,
                  size: 40,
                  iconSize: 20,
                  strokeWidth: 1.9,
                  label: '前进',
                  color: nav.canForward ? p.text : p.text2,
                  onTap: nav.canForward ? nav.forward : null,
                ),
                const SizedBox(width: 18),
                Glass(
                  width: 340,
                  height: 40,
                  radius: 20,
                  shadows: p.glassButtonShadow,
                  insets: p.glassButtonInset,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      YIcon(YIcons.search, size: 18, strokeWidth: 1.9, color: p.text3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          style: ts(14, color: p.text),
                          cursorColor: p.accentText,
                          textInputAction: TextInputAction.search,
                          onTap: () {
                            if (nav.top is! SearchRoute && nav.top is! SearchResultRoute && _search.text.isEmpty) nav.push(SearchRoute());
                          },
                          onSubmitted: (q) => submitSearch(context, q),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: '搜索歌曲、歌手、歌单',
                            hintStyle: ts(14, color: p.text2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          const Positioned(left: 10, top: 10, bottom: 10, width: 232, child: _Sidebar()),
          const Positioned(left: 262, right: 28, bottom: 14, child: DesktopPlayerBar()),
        ],
      ),
    );
  }
}

class _FadePage extends Page<void> {
  const _FadePage({required super.key, required this.child});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => PageRouteBuilder<void>(
    settings: this,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (_, _, _) => child,
    transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final nav = context.watch<AppNav>();
    final sm = context.watch<SourceManager>();
    final source = sm.current;
    final active = nav.top.sideKey;
    void open(AppRoute r) {
      if (nav.top.sideKey == r.sideKey) return;
      nav.push(r);
    }

    Widget label(String t, double top) => Padding(
      padding: EdgeInsets.fromLTRB(10, top, 0, 6),
      child: Text(
        t,
        style: ts(12, weight: w600, color: p.text2),
      ),
    );

    return YBox(
      radius: BorderRadius.circular(26),
      color: p.sidebar,
      // 侧边栏只覆盖静态的光晕背景，模糊没有可见效果，省去每帧的背景截取。
      border: p.glassBorder,
      shadows: p.sidebarShadow,
      insets: p.glassButtonInset,
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WindowDragArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: const [WindowControls(), Spacer()]),
            ),
          ),
          const SizedBox(height: 20),
          WindowDragArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const AppLogo(size: 28),
                  const SizedBox(width: 9),
                  Text(
                    '云音',
                    style: ts(18, weight: w700, em: -0.01, color: p.text),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  label('发现', 20),
                  _SideItem(icon: YIcons.home, label: '首页', active: active == 'home', onTap: () => open(HomeRoute())),
                  _SideItem(icon: YIcons.discover, label: '发现', active: active == 'discover', onTap: () => open(DiscoverRoute())),
                  _SideItem(icon: YIcons.radio, label: '电台', active: active == 'radio', onTap: () => open(DiscoverRoute(tab: 2))),
                  label('乐库', 18),
                  _SideItem(icon: YIcons.clock, label: '最近播放', active: active == 'collection:recent', onTap: () => open(CollectionRoute(PlaylistKind.recent))),
                  _SideItem(
                    icon: YIcons.heartOutline,
                    label: '我喜欢的音乐',
                    active: active == 'collection:liked',
                    onTap: () => open(CollectionRoute(PlaylistKind.liked)),
                  ),
                  _SideItem(
                    icon: YIcons.download,
                    label: '已下载',
                    active: active == 'collection:downloaded',
                    onTap: () => open(CollectionRoute(PlaylistKind.downloaded)),
                  ),
                  _SideItem(icon: YIcons.folder, label: '本地音乐', active: active == 'collection:local', onTap: () => open(CollectionRoute(PlaylistKind.local))),
                  _SideItem(icon: YIcons.library, label: '专辑与歌手', active: active == 'collections', onTap: () => open(MyCollectionsRoute())),
                  _SideItem(icon: YIcons.equalizer, label: '听歌统计', active: active == 'stats', onTap: () => open(StatsRoute())),
                  label('我的歌单', 18),
                  _SidePlaylists(key: ValueKey(sm.generation), source: source, active: active),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 4, 0),
            child: Row(
              children: [
                Pressable(
                  onTap: () => open(source.user == null && source.supports(SourceFeature.login) ? LoginRoute() : SettingsMoreRoute()),
                  child: Avatar(source.user?.avatar, size: 34),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Pressable(
                    onTap: () => open(source.user == null && source.supports(SourceFeature.login) ? LoginRoute() : SettingsMoreRoute()),
                    scale: 1,
                    child: Text(
                      source.user?.nickname ?? '点击登录',
                      style: ts(14, weight: w600, color: p.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                YIconButton(YIcons.sliders, size: 36, iconSize: 20, color: p.text3, label: '设置', onTap: () => open(SettingsRoute())),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({this.icon, this.cover, required this.label, required this.active, required this.onTap});

  final YIconData? icon;
  final String? cover;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = active ? p.accentText : p.text3;
    return Pressable(
      onTap: onTap,
      scale: 1,
      hoverColor: active ? null : p.sidebarActive.withValues(alpha: 0.08),
      radius: BorderRadius.circular(12),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: active ? p.sidebarActive : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            if (icon != null) YIcon(icon!, size: 18, color: color) else Cover(cover, size: 22, radius: 6),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: ts(14, weight: active ? w600 : w500, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidePlaylists extends StatefulWidget {
  const _SidePlaylists({super.key, required this.source, required this.active});

  final MusicSource source;
  final String active;

  @override
  State<_SidePlaylists> createState() => _SidePlaylistsState();
}

class _SidePlaylistsState extends State<_SidePlaylists> {
  List<PlaylistInfo>? _lists;

  @override
  void initState() {
    super.initState();
    if (!widget.source.loggedIn && widget.source.supports(SourceFeature.login)) return;
    widget.source
        .userPlaylists()
        .then((l) {
          if (mounted) setState(() => _lists = l.where((x) => !x.isLikedList).toList());
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lists = _lists;
    if (lists == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: Text(widget.source.loggedIn ? '加载中…' : '登录后显示你的歌单', style: ts(13, color: p.text2)),
      );
    }
    return Column(
      children: [
        for (final pl in lists)
          _SideItem(
            cover: pl.cover,
            label: pl.name,
            active: widget.active == 'playlist:${pl.id}',
            onTap: () {
              final nav = context.read<AppNav>();
              if (nav.top.sideKey == 'playlist:${pl.id}') return;
              openPlaylist(context, pl);
            },
          ),
      ],
    );
  }
}

/// 迷你模式：小窗口只保留播放控制。
class _MiniWindow extends StatelessWidget {
  const _MiniWindow({required this.onRestore});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final song = player.current;
    return GlowBackground.player(
      context,
      child: WindowDragArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Glass(
            radius: 38,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
            child: Row(
              children: [
                Cover(song?.coverUrl, size: 52, circle: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song?.name ?? '云音',
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
                YIconButton(YIcons.prev, size: 32, iconSize: 20, label: '上一首', onTap: player.previous),
                const PlayButton(size: 36, iconSize: 18),
                YIconButton(YIcons.next, size: 32, iconSize: 20, label: '下一首', onTap: player.next),
                YIconButton(YIcons.miniMode, size: 32, iconSize: 20, color: p.text3, label: '退出迷你模式', onTap: onRestore),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
