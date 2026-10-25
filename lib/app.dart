import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/settings.dart';
import 'core/theme/palette.dart';
import 'core/ui/box.dart';
import 'core/ui/feedback.dart';
import 'core/ui/icons.dart';
import 'core/ui/text.dart';
import 'core/ui/widgets.dart';
import 'data/downloads.dart';
import 'data/sources/source_manager.dart';
import 'features/common/layout.dart';
import 'features/shell/desktop_shell.dart';
import 'features/shell/mobile_shell.dart';
import 'features/shell/nav.dart';
import 'player/player_controller.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class YunyinApp extends StatelessWidget {
  const YunyinApp({
    super.key,
    required this.settings,
    required this.sources,
    required this.player,
    required this.downloads,
  });

  final AppSettings settings;
  final SourceManager sources;
  final PlayerController player;
  final DownloadManager downloads;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: sources),
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider.value(value: downloads),
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
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final p = isDark ? dark : light;
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
                    child: LayoutScope(
                      desktop: width >= kDesktopBreakpoint,
                      child: DefaultTextStyle(
                        style: ts(15, color: p.text),
                        child: IconTheme(
                          data: IconThemeData(color: p.text),
                          child: Material(
                            type: MaterialType.transparency,
                            child: PlaybackShortcuts(
                              enabled: width >= kDesktopBreakpoint,
                              child: _NoticeListener(child: child!),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            home: const _Root(),
          );
        },
      ),
    );
  }

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
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        }),
      );
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
