import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 是否运行在桌面系统上（Windows / Linux / macOS）。
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.macOS);

/// Windows 使用系统风格的标题栏按钮（右上角），其他桌面系统使用红黄绿三色按钮。
bool get useWindowsCaption => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// 设计稿中的红黄绿三色窗口按钮：关闭 / 最小化 / 最大化（Linux、macOS）。Windows 上不显示，改用 [WindowsCaptionButtons]。
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
    if (useWindowsCaption) return const SizedBox.shrink();
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


/// Windows 风格的标题栏按钮：最小化、最大化 / 还原、关闭，宽 46、高 32，图标为 1 像素细线；
/// 悬停时浅色底，关闭按钮悬停为红底白色图标。放在窗口右上角。
class WindowsCaptionButtons extends StatefulWidget {
  const WindowsCaptionButtons({super.key});

  @override
  State<WindowsCaptionButtons> createState() => _WindowsCaptionButtonsState();
}

class _WindowsCaptionButtonsState extends State<WindowsCaptionButtons> with WindowListener {
  bool _max = false;

  @override
  void initState() {
    super.initState();
    if (!useWindowsCaption) return;
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _max = v);
    });
  }

  @override
  void dispose() {
    if (useWindowsCaption) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _max = true);

  @override
  void onWindowUnmaximize() => setState(() => _max = false);

  @override
  Widget build(BuildContext context) {
    if (!useWindowsCaption) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(kind: _Caption.minimize, dark: dark, label: '最小化', onTap: () => windowManager.minimize()),
        _CaptionButton(
          kind: _max ? _Caption.restore : _Caption.maximize,
          dark: dark,
          label: _max ? '向下还原' : '最大化',
          onTap: () => _max ? windowManager.unmaximize() : windowManager.maximize(),
        ),
        _CaptionButton(kind: _Caption.close, dark: dark, label: '关闭', onTap: () => windowManager.close()),
      ],
    );
  }
}

enum _Caption { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({required this.kind, required this.dark, required this.label, required this.onTap});

  final _Caption kind;
  final bool dark;
  final String label;
  final VoidCallback onTap;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final close = widget.kind == _Caption.close;
    final fg = widget.dark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);
    final Color bg;
    if (close && (_hover || _down)) {
      bg = _down ? const Color(0xFFC94F4F) : const Color(0xFFC42B1C);
    } else if (_hover || _down) {
      bg = (widget.dark ? Colors.white : Colors.black).withValues(alpha: _down ? 0.1 : 0.06);
    } else {
      bg = Colors.transparent;
    }
    final iconColor = close && (_hover || _down) ? Colors.white : fg;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = _down = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 46,
            height: 32,
            color: bg,
            child: CustomPaint(painter: _CaptionIcon(widget.kind, iconColor)),
          ),
        ),
      ),
    );
  }
}

class _CaptionIcon extends CustomPainter {
  _CaptionIcon(this.kind, this.color);

  final _Caption kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const s = 10.0;
    switch (kind) {
      case _Caption.minimize:
        canvas.drawLine(Offset(c.dx - s / 2, c.dy + 0.5), Offset(c.dx + s / 2, c.dy + 0.5), p);
      case _Caption.maximize:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s, height: s), const Radius.circular(1.5)), p);
      case _Caption.restore:
        final back = Rect.fromLTWH(c.dx - s / 2 + 2, c.dy - s / 2, s - 2, s - 2);
        final front = Rect.fromLTWH(c.dx - s / 2, c.dy - s / 2 + 2, s - 2, s - 2);
        canvas.drawPath(
          Path()
            ..moveTo(back.left, front.top)
            ..lineTo(back.left, back.top + 1.5)
            ..arcToPoint(Offset(back.left + 1.5, back.top), radius: const Radius.circular(1.5))
            ..lineTo(back.right - 1.5, back.top)
            ..arcToPoint(Offset(back.right, back.top + 1.5), radius: const Radius.circular(1.5))
            ..lineTo(back.right, back.bottom - 1.5)
            ..arcToPoint(Offset(back.right - 1.5, back.bottom), radius: const Radius.circular(1.5))
            ..lineTo(front.right, back.bottom),
          p,
        );
        canvas.drawRRect(RRect.fromRectAndRadius(front, const Radius.circular(1.5)), p);
      case _Caption.close:
        canvas.drawLine(Offset(c.dx - s / 2, c.dy - s / 2), Offset(c.dx + s / 2, c.dy + s / 2), p);
        canvas.drawLine(Offset(c.dx + s / 2, c.dy - s / 2), Offset(c.dx - s / 2, c.dy + s / 2), p);
    }
  }

  @override
  bool shouldRepaint(_CaptionIcon old) => old.kind != kind || old.color != color;
}
