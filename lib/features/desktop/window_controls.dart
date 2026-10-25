import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 是否运行在桌面系统上（Windows / Linux / macOS）。
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.macOS);

/// 设计稿中的红黄绿三色窗口按钮：关闭 / 最小化 / 最大化。
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  bool _hover = false;

  Future<void> _toggleMax() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = isDesktopPlatform;
    Widget dot(Color c, IconData icon, String label, VoidCallback onTap) => Semantics(
      button: true,
      label: label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: _hover && enabled ? Icon(icon, size: 9, color: const Color.fromRGBO(0, 0, 0, 0.55)) : null,
          ),
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot(const Color(0xFFFF5F57), Icons.close_rounded, '关闭', () => windowManager.close()),
          const SizedBox(width: 8),
          dot(const Color(0xFFFEBC2E), Icons.remove_rounded, '最小化', () => windowManager.minimize()),
          const SizedBox(width: 8),
          dot(const Color(0xFF28C840), Icons.open_in_full_rounded, '最大化', _toggleMax),
        ],
      ),
    );
  }
}

/// 可拖动窗口的区域（双击最大化）。
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: child,
    );
  }
}
