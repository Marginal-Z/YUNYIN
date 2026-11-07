import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/cover_colors.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';
import '../comments/comments_page.dart';
import '../common/layout.dart';
import '../player/lyrics_view.dart';
import '../shell/nav.dart';
import '../shell/routes.dart';
import 'window_controls.dart';

/// 桌面端的弹出面板：窗口中央的圆角面板，内容按手机布局排版（宽度与手机相近），点按面板外或 Esc 关闭。
Future<T?> showDesktopPanel<T>(BuildContext context, {required WidgetBuilder builder, double width = 560}) {
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.32),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) {
      final p = Palette.of(ctx);
      final size = MediaQuery.sizeOf(ctx);
      return Center(
        child: SizedBox(
          width: width.clamp(360.0, size.width - 48),
          height: (size.height - 64).clamp(420.0, 900.0),
          child: YBox(
            clip: true,
            radius: BorderRadius.circular(28),
            color: p.bg,
            shadows: const [Shadow2(0, 30, 70, Color.fromRGBO(0, 0, 0, 0.32))],
            child: MediaQuery.removePadding(
              context: ctx,
              removeTop: true,
              removeBottom: true,
              child: LayoutScope(
                desktop: false,
                child: Material(
                  type: MaterialType.transparency,
                  child: Builder(builder: builder),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, a, _, child) {
      final curve = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curve), child: child),
      );
    },
  );
}

/// 桌面端评论：弹出面板。
Future<void> showDesktopComments(BuildContext context, Song song) => showDesktopPanel<void>(context, width: 620, builder: (_) => CommentsPage(song: song));

/// 设置面板里自己的导航栈：设置的子页面（外观、播放、音效……）在面板内打开，返回到设置首页后再返回即关闭面板。
class _SettingsNav extends AppNav {
  _SettingsNav(this._close) {
    stacks[0]
      ..clear()
      ..add(SettingsRoute());
  }

  final VoidCallback _close;

  @override
  bool pop() {
    if (super.pop()) return true;
    _close();
    return true;
  }
}

/// 桌面端设置：弹出面板，不再占用主窗口的页面。
Future<void> showDesktopSettings(BuildContext context) => showDesktopPanel<void>(context, builder: (_) => const _SettingsPanel());

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel();

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  // 导航栈只创建一次：面板重建（例如调整窗口大小）时不回到设置首页。
  late final _SettingsNav _nav = _SettingsNav(() => Navigator.of(context).maybePop());

  @override
  void dispose() {
    _nav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppNav>.value(
      value: _nav,
      child: Stack(
        children: [
          Positioned.fill(
            child: Consumer<AppNav>(
              builder: (context, nav, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(key: ValueKey(nav.top.uid), child: buildMobileRoute(nav.top)),
              ),
            ),
          ),
          Positioned(
            top: 20,
            right: 16,
            child: GlassButton(YIcons.close, label: '关闭设置', onTap: () => Navigator.of(context).maybePop()),
          ),
        ],
      ),
    );
  }
}

/// 桌面端全屏歌词：窗口进入全屏，只显示居中的大号歌词与歌曲信息；Esc 或右上角按钮退出。
class DesktopLyricsPage extends StatefulWidget {
  const DesktopLyricsPage({super.key});

  @override
  State<DesktopLyricsPage> createState() => _DesktopLyricsPageState();
}

class _DesktopLyricsPageState extends State<DesktopLyricsPage> {
  bool _wasFullScreen = false;

  @override
  void initState() {
    super.initState();
    if (isDesktopPlatform) {
      windowManager.isFullScreen().then((v) {
        _wasFullScreen = v;
        if (!v) windowManager.setFullScreen(true);
      });
    }
  }

  @override
  void dispose() {
    if (isDesktopPlatform && !_wasFullScreen) windowManager.setFullScreen(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final song = player.current;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: GlowBackground.player(
            context,
            scale: 2.4,
            flow: player.playing,
            child: Stack(
              children: [
                const Positioned.fill(child: LyricsView(desktop: true, anchor: 0.42, padding: EdgeInsets.symmetric(horizontal: 160))),
                Positioned(
                  left: 40,
                  top: 28,
                  right: 120,
                  child: Text(
                    song == null ? '' : '${song.name} · ${song.artistText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(15, weight: w600, color: p.playerText2),
                  ),
                ),
                Positioned(
                  top: 20,
                  right: 28,
                  child: YIconButton(
                    YIcons.exitFullscreen,
                    size: 44,
                    iconSize: 22,
                    color: p.text,
                    label: '退出全屏歌词',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 打开桌面端全屏歌词。
void openDesktopLyrics(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => const PlayerThemed(child: DesktopLyricsPage()),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}
