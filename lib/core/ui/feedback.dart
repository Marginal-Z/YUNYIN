import 'dart:async';

import 'package:flutter/material.dart';

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
    final entry = OverlayEntry(builder: (ctx) => _ToastView(message: message, icon: icon));
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
                  Text(message, style: ts(14, weight: w600, color: p.text)),
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
                    child: Column(children: [
                      Text(title, style: ts(17, weight: w700, color: p.text), textAlign: TextAlign.center),
                      const SizedBox(height: 6),
                      Text(message, style: ts(13, height: 1.45, color: p.text2), textAlign: TextAlign.center),
                    ]),
                  ),
                  Container(height: 1, color: const Color.fromRGBO(60, 60, 67, 0.16)),
                  SizedBox(
                    height: 46,
                    child: Row(children: [
                      Expanded(
                        child: Pressable(
                          onTap: () => Navigator.of(ctx).pop(false),
                          child: Center(child: Text(cancel, style: ts(16, color: p.text))),
                        ),
                      ),
                      Container(width: 1, color: const Color.fromRGBO(60, 60, 67, 0.16)),
                      Expanded(
                        child: Pressable(
                          onTap: () => Navigator.of(ctx).pop(true),
                          child: Center(
                            child: Text(confirm, style: ts(16, weight: w700, color: destructive ? p.danger : p.accentText)),
                          ),
                        ),
                      ),
                    ]),
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
      child: ScaleTransition(scale: Tween(begin: 1.08, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)), child: child),
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

  factory StateView.empty({required String title, required String message, String? action, VoidCallback? onAction, YIconData icon = YIcons.download, TileColor tile = TileColor.blue}) =>
      StateView(icon: icon, tile: tile, title: title, message: message, action: action, onAction: onAction, primary: true);

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
          Text(title, style: ts(18, weight: w700, em: -0.01, color: p.text), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(message, style: ts(13, height: 1.5, color: p.text2), textAlign: TextAlign.center),
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
          child: Container(height: h, decoration: BoxDecoration(color: p.skeleton, borderRadius: BorderRadius.circular(h / 2))),
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
                child: Row(children: [
                  Container(width: 42, height: 42, decoration: BoxDecoration(color: p.skeleton, borderRadius: BorderRadius.circular(10))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [bar(0.58, 12), const SizedBox(height: 8), bar(0.32, 10)],
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// 根据 Future 渲染加载 / 错误 / 内容。
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder, this.loading, this.keyValue});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;
  final Widget? loading;

  /// 变化时重新加载（例如切换播放源）。
  final Object? keyValue;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future = widget.load();

  void _reload() => setState(() => _future = widget.load());

  @override
  void didUpdateWidget(AsyncView<T> old) {
    super.didUpdateWidget(old);
    if (old.keyValue != widget.keyValue) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return widget.loading ?? const SkeletonList();
        }
        if (snap.hasError) {
          return Center(child: StateView.network(onRetry: _reload, message: errorText(snap.error)));
        }
        return widget.builder(context, snap.data as T, _reload);
      },
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
