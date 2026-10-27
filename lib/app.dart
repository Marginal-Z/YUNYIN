import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/settings.dart';
import 'core/ui/adaptive_scale.dart';
import 'core/theme/palette.dart';
import 'core/ui/box.dart';
import 'core/ui/feedback.dart';
import 'core/ui/icons.dart';
import 'core/ui/text.dart';
import 'core/ui/widgets.dart';
import 'data/downloads.dart';
import 'data/local_library.dart';
import 'data/sources/source_manager.dart';
import 'features/common/layout.dart';
import 'features/shell/desktop_shell.dart';
import 'features/shell/mobile_shell.dart';
import 'debug/benchmark.dart';
import 'debug/screenshots.dart';
import 'features/settings/update_dialog.dart';
import 'features/splash/splash.dart';
import 'features/shell/nav.dart';
import 'player/player_controller.dart';
import 'core/update/updater.dart';
import 'data/listen_stats.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class YunyinApp extends StatelessWidget {
  const YunyinApp({
    super.key,
    required this.settings,
    required this.sources,
    required this.player,
    required this.downloads,
    required this.local,
    required this.updater,
    required this.stats,
  });

  final AppSettings settings;
  final SourceManager sources;
  final PlayerController player;
  final DownloadManager downloads;
  final LocalLibrary local;
  final UpdateManager updater;
  final ListenStats stats;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: sources),
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider.value(value: downloads),
        ChangeNotifierProvider.value(value: local),
        ChangeNotifierProvider.value(value: updater),
        ChangeNotifierProvider.value(value: stats),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: Consumer<AppSettings>(
        builder: (context, s, _) {
          final light = s.palette(false);
          final dark = s.palette(true);
          return MaterialApp(
            title: '云音',
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavigatorKey,
            themeMode: s.themeMode,
            theme: _theme(light),
            darkTheme: _theme(dark),
            builder: (context, child) {
              // 界面整体按设备尺寸等比缩放后再搭建外壳。
              Widget scaled(BuildContext context) => AdaptiveScale(
                desktopBreakpoint: kDesktopBreakpoint,
                child: Builder(builder: (context) => _shell(context, child!, s, light, dark)),
              );
              return screenshotsRequested ? ShotFrame(builder: scaled) : _SplashGate(child: scaled(context));
            },
            home: const _Root(),
          );
        },
      ),
    );
  }

  /// 应用外壳：主题色板、毛玻璃开关、桌面 / 移动布局与全局快捷键。
  Widget _shell(BuildContext context, Widget child, AppSettings s, Palette light, Palette dark) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 默认纯白背景下卡片改为浅灰底（见 Palette.onWhite）；封面取色与自定义图片背景保持原样。
    final p = isDark ? dark : (s.background == BackgroundMode.glow ? _onWhite(light) : light);
    final width = MediaQuery.sizeOf(context).width;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: PaletteScope(
        palette: p,
        child: GlassScope(
          enabled: s.glass,
          material: s.glassMaterial,
          child: LayoutScope(
            desktop: AdaptiveScale.desktopOf(context) ?? width >= kDesktopBreakpoint,
            child: DefaultTextStyle(
              style: ts(15, color: p.text),
              child: IconTheme(
                data: IconThemeData(color: p.text),
                child: Material(
                  type: MaterialType.transparency,
                  child: PlaybackShortcuts(
                    enabled: AdaptiveScale.desktopOf(context) ?? width >= kDesktopBreakpoint,
                    child: BackdropGroup(child: _NoticeListener(child: child)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static final _white = Expando<Palette>();

  /// 缓存纯白背景用的色板：色板对象不变时 PaletteScope 不会通知整棵树重建。
  static Palette _onWhite(Palette light) => _white[light] ??= light.onWhite();

  ThemeData _theme(Palette p) => ThemeData(
    useMaterial3: true,
    brightness: p.isDark ? Brightness.dark : Brightness.light,
    fontFamily: kFontFamily,
    fontFamilyFallback: kFontFallback,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent.base,
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      primary: p.accentText,
      surface: p.bg,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accentText,
      selectionColor: p.accentText.withValues(alpha: 0.25),
      selectionHandleColor: p.accentText,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// 启动动画盖在应用上方：首页在下面照常加载，动画结束后淡出并移除。
/// 首次启动播完整版，之后只播缩短版；截图与性能测试模式不播放。
class _SplashGate extends StatefulWidget {
  const _SplashGate({required this.child});

  final Widget child;

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _done = benchmarkRequested;
  late final bool _full = !context.read<AppSettings>().splashSeen;

  void _finish() {
    final s = context.read<AppSettings>();
    if (!s.splashSeen) s.setFlag('splashSeen', true);
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        widget.child,
        Directionality(
          textDirection: TextDirection.ltr,
          child: Splash(
            full: _full,
            desktop: MediaQuery.sizeOf(context).width >= kDesktopBreakpoint,
            version: context.read<UpdateManager>().current,
            onDone: _finish,
          ),
        ),
      ],
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final desktop = LayoutScope.isDesktop(context);
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: desktop),
      child: desktop ? const DesktopShell() : const MobileShell(),
    );
  }
}

/// 把播放器的提示显示为轻提示或“暂无播放版权”卡片。
class _NoticeListener extends StatefulWidget {
  const _NoticeListener({required this.child});

  final Widget child;

  @override
  State<_NoticeListener> createState() => _NoticeListenerState();
}

class _NoticeListenerState extends State<_NoticeListener> {
  StreamSubscription<PlayerNotice>? _sub;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _sub = context.read<PlayerController>().notices.listen(_show);
    _autoUpdate();
  }

  /// 启动几秒后静默检查更新，有新版本（且未被跳过）时弹出更新说明。
  Future<void> _autoUpdate() async {
    final settings = context.read<AppSettings>();
    final updater = context.read<UpdateManager>();
    if (!settings.autoUpdate || updater.kind == InstallKind.unsupported || screenshotsRequested) return;
    await Future<void>.delayed(const Duration(seconds: 5));
    if (!await updater.check() || settings.skippedUpdate == updater.latest!.version) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) await showUpdateDialog(ctx);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _show(PlayerNotice n) {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    if (!n.blocking) {
      final overlay = nav.overlay;
      if (overlay != null) Toast.showOn(overlay, n.title, icon: n.title.contains('喜欢') ? YIcons.heart : YIcons.info);
      return;
    }
    if (_dialogOpen) return;
    _dialogOpen = true;
    showGeneralDialog<void>(
      context: nav.context,
      barrierDismissible: true,
      barrierLabel: '知道了',
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.25),
      pageBuilder: (ctx, _, _) {
        return Center(
          child: SizedBox(
            width: 320,
            child: YCard(
              child: StateView(
                icon: YIcons.lock,
                tile: TileColor.graphite,
                title: n.title,
                message: n.message ?? '',
                action: '知道了',
                onAction: () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() => _dialogOpen = false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 桌面端播放快捷键：空格 播放/暂停，Ctrl+←/→ 切歌，Ctrl+↑/↓ 音量。
class PlaybackShortcuts extends StatelessWidget {
  const PlaybackShortcuts({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  static bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
        final player = context.read<PlayerController>();
        final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.space && !ctrl) {
          if (_typing) return KeyEventResult.ignored;
          if (e is KeyDownEvent) player.toggle();
          return KeyEventResult.handled;
        }
        if (!ctrl) return KeyEventResult.ignored;
        if (k == LogicalKeyboardKey.arrowLeft && !_typing) {
          player.previous();
        } else if (k == LogicalKeyboardKey.arrowRight && !_typing) {
          player.next();
        } else if (k == LogicalKeyboardKey.arrowUp) {
          player.setVolume(player.volume + 0.05);
        } else if (k == LogicalKeyboardKey.arrowDown) {
          player.setVolume(player.volume - 0.05);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
