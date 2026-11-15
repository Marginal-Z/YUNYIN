import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/motion.dart';
import 'assistant_page.dart';

/// 云音助手悬浮球：浮在页面上，按住可以拖到任意位置，松手后吸附到最近的左右边缘并记住位置。
/// 点按打开助手，长按打开并立即开始听。听、思考时外圈亮起。
class AssistantBall extends StatefulWidget {
  const AssistantBall({super.key, required this.top, required this.bottom});

  /// 可停靠范围的上下边界（离屏幕顶部、底部的距离，避开状态栏、底部导航栏与迷你播放条）。
  final double top;
  final double bottom;

  static const size = 52.0;

  @override
  State<AssistantBall> createState() => _AssistantBallState();
}

class _AssistantBallState extends State<AssistantBall> {
  /// 拖动中的位置（左上角）；为 null 时按保存的停靠位置显示。
  Offset? _drag;

  static const _margin = 10.0;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AssistantSettings>();
    final status = context.select<AssistantController, AssistantStatus>((a) => a.status);
    final p = Palette.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        const d = AssistantBall.size;
        final minY = widget.top;
        final maxY = (c.maxHeight - widget.bottom - d).clamp(minY, double.infinity);
        final docked = Offset(s.ballLeft ? _margin : c.maxWidth - d - _margin, minY + (maxY - minY) * s.ballY);
        final pos = _drag ?? docked;
        final active = status != AssistantStatus.idle;
        return Stack(
          children: [
            AnimatedPositioned(
              // 拖动时跟手，松手后弹到边缘。
              duration: _drag == null ? const Duration(milliseconds: 320) : Duration.zero,
              curve: Motion.spring,
              left: pos.dx,
              top: pos.dy,
              child: GestureDetector(
                onTap: () => openAssistant(context),
                onLongPress: () => openAssistant(context, listen: true),
                onPanStart: (_) => setState(() => _drag = pos),
                onPanUpdate: (e) => setState(() {
                  final o = (_drag ?? pos) + e.delta;
                  _drag = Offset(o.dx.clamp(0.0, c.maxWidth - d), o.dy.clamp(minY, maxY));
                }),
                onPanEnd: (_) {
                  final o = _drag ?? pos;
                  setState(() => _drag = null);
                  s.setBall(left: o.dx + d / 2 < c.maxWidth / 2, y: maxY > minY ? (o.dy - minY) / (maxY - minY) : 0);
                },
                child: Semantics(
                  button: true,
                  label: '云音助手',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [p.accent.buttonTop, p.accent.base], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      border: Border.all(color: Colors.white.withValues(alpha: active ? 0.95 : 0.55), width: active ? 2.4 : 1.2),
                      boxShadow: [
                        BoxShadow(color: p.accent.base.withValues(alpha: active ? 0.55 : 0.32), blurRadius: active ? 22 : 14, offset: const Offset(0, 6)),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: YIcon(status == AssistantStatus.listening ? YIcons.mic : YIcons.sparkle, size: 24, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
