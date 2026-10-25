import 'dart:async';

import 'package:flutter/material.dart';

import '../data_cache.dart';
import '../theme/palette.dart';
import 'box.dart';
import 'icons.dart';
import 'text.dart';
import 'widgets.dart';

/// 玻璃轻提示（“已加入下一首播放”）。
abstract final class Toast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(BuildContext context, String message, {YIconData icon = YIcons.check}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    showOn(overlay, message, icon: icon);
  }

  static void showOn(OverlayState overlay, String message, {YIconData icon = YIcons.check}) {
    _timer?.cancel();
    _entry?.remove();
    final entry = OverlayEntry(
      builder: (ctx) => _ToastView(message: message, icon: icon),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(const Duration(milliseconds: 2200), () {
      if (_entry == entry) {
        entry.remove();
        _entry = null;
      }
    });
  }
}

class _ToastView extends StatelessWidget {
  const _ToastView({required this.message, required this.icon});

  final String message;
  final YIconData icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final top = MediaQuery.paddingOf(context).top + 20;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            builder: (context, t, child) => Opacity(
              opacity: t.clamp(0, 1),
              child: Transform.translate(offset: Offset(0, -12 * (1 - t)), child: child),
            ),
            child: Glass(
              radius: 22,
              height: 44,
              padding: const EdgeInsets.fromLTRB(14, 0, 18, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  YIcon(icon, size: 18, color: p.text, strokeWidth: 2),
                  const SizedBox(width: 8),
                  Text(
                    message,
                    style: ts(14, weight: w600, color: p.text),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 确认弹窗（“清空播放队列？”）。返回 true 表示确认。
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  String cancel = '取消',
  bool destructive = true,
}) async {
  final r = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancel,
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.25),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) {
      final p = Palette.of(ctx);
      return Center(
        child: SizedBox(
          width: 270,
          child: YBox(
            radius: BorderRadius.circular(22),
            color: p.dialog,
            blur: true,
            shadows: const [Shadow2(0, 24, 50, Color.fromRGBO(28, 44, 92, 0.22))],
            insets: [Shadow2(0, 0, 0, p.isDark ? const Color.fromRGBO(255, 255, 255, 0.1) : const Color.fromRGBO(255, 255, 255, 0.9), spread: 1)],
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                    child: Column(
                      children: [
                        Text(
                          title,
                          style: ts(17, weight: w700, color: p.text),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          message,
                          style: ts(13, height: 1.45, color: p.text2),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: const Color.fromRGBO(60, 60, 67, 0.16)),
                  SizedBox(
                    height: 46,
                    child: Row(
                      children: [
                        Expanded(
                          child: Pressable(
                            onTap: () => Navigator.of(ctx).pop(false),
                            child: Center(
                              child: Text(cancel, style: ts(16, color: p.text)),
                            ),
                          ),
                        ),
                        Container(width: 1, color: const Color.fromRGBO(60, 60, 67, 0.16)),
                        Expanded(
                          child: Pressable(
                            onTap: () => Navigator.of(ctx).pop(true),
                            child: Center(
                              child: Text(
                                confirm,
                                style: ts(16, weight: w700, color: destructive ? p.danger : p.accentText),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(begin: 1.08, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
  return r ?? false;
}

/// 空状态 / 异常状态（图标块 + 标题 + 说明 + 按钮）。
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.icon,
    required this.tile,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
    this.primary = false,
    this.actionIcon,
  });

  factory StateView.network({VoidCallback? onRetry, String? message}) => StateView(
    icon: YIcons.wifiOff,
    tile: TileColor.orange,
    title: '网络开小差了',
    message: message ?? '请检查网络连接后重试，已下载的歌曲仍可播放。',
    action: '重新加载',
    actionIcon: YIcons.refresh,
    onAction: onRetry,
  );

  factory StateView.empty({
    required String title,
    required String message,
    String? action,
    VoidCallback? onAction,
    YIconData icon = YIcons.download,
    TileColor tile = TileColor.blue,
  }) => StateView(icon: icon, tile: tile, title: title, message: message, action: action, onAction: onAction, primary: true);

  final YIconData icon;
  final TileColor tile;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  final bool primary;
  final YIconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTile(icon, tile, size: 56, iconSize: 28, strokeWidth: 1.75),
          const SizedBox(height: 14),
          Text(
            title,
            style: ts(18, weight: w700, em: -0.01, color: p.text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              message,
              style: ts(13, height: 1.5, color: p.text2),
              textAlign: TextAlign.center,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            primary
                ? PrimaryButton(label: action!, onTap: onAction, height: 40, fontSize: 14)
                : SecondaryButton(label: action!, icon: actionIcon, iconSize: 18, onTap: onAction, height: 40, fontSize: 14, flat: true),
          ],
        ],
      ),
    );
  }
}

/// 骨架屏行。
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14)});

  final int count;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget bar(double f, double h) => FractionallySizedBox(
      widthFactor: f,
      alignment: Alignment.centerLeft,
      child: Container(
        height: h,
        decoration: BoxDecoration(color: p.skeleton, borderRadius: BorderRadius.circular(h / 2)),
      ),
    );
    return YCard(
      padding: padding,
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: p.skeleton, borderRadius: BorderRadius.circular(10)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [bar(0.58, 12), const SizedBox(height: 8), bar(0.32, 10)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 根据 Future 渲染加载 / 错误 / 内容。
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder, this.loading, this.keyValue, this.cacheKey, this.maxAge = const Duration(minutes: 10)});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;
  final Widget? loading;

  /// 变化时重新加载（例如切换播放源）。
  final Object? keyValue;

  /// 缓存键：有缓存时直接显示上次的数据，超过 [maxAge] 后在后台静默刷新。
  final String? cacheKey;
  final Duration maxAge;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  T? _data;
  bool _hasData = false;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final key = widget.cacheKey;
    final cached = key == null ? null : DataCache.lookup(key);
    if (cached != null && cached.$1 is T) {
      _data = cached.$1 as T;
      _hasData = true;
      _error = null;
      if (DateTime.now().difference(cached.$2) > widget.maxAge) _fetch(silent: true);
    } else {
      _hasData = false;
      _data = null;
      _fetch();
    }
  }

  /// 加载数据。静默刷新失败时保留现有内容。
  Future<void> _fetch({bool silent = false}) async {
    final request = ++_request;
    if (!silent && _error != null) setState(() => _error = null);
    try {
      final v = await widget.load();
      if (!mounted || request != _request) return;
      if (widget.cacheKey != null) DataCache.put(widget.cacheKey!, v);
      setState(() {
        _data = v;
        _hasData = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      if (silent && _hasData) return;
      setState(() => _error = e);
    }
  }

  void _reload() => _fetch(silent: _hasData);

  @override
  void didUpdateWidget(AsyncView<T> old) {
    super.didUpdateWidget(old);
    if (old.keyValue != widget.keyValue || old.cacheKey != widget.cacheKey) {
      setState(_start);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (_hasData) {
      child = KeyedSubtree(key: const ValueKey('data'), child: widget.builder(context, _data as T, _reload));
    } else if (_error != null) {
      child = Center(
        key: const ValueKey('error'),
        child: StateView.network(
          onRetry: () {
            setState(() => _error = null);
            _fetch();
          },
          message: errorText(_error),
        ),
      );
    } else {
      child = KeyedSubtree(key: const ValueKey('loading'), child: widget.loading ?? const SkeletonList());
    }
    // 骨架屏与内容之间短暂淡入淡出，避免内容突然“蹦”出来。
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      child: child,
    );
  }
}

String errorText(Object? e) {
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('connection') || s.contains('XMLHttpRequest')) {
    return '请检查网络连接后重试，已下载的歌曲仍可播放。';
  }
  return s.replaceFirst('Exception: ', '');
}
