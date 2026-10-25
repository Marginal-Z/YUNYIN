import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';

/// 移动端播放队列：背景是模糊的播放页，上方滑出白色面板。
class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pad = MediaQuery.paddingOf(context);
    final route = ModalRoute.of(context)!;
    final anim = CurvedAnimation(parent: route.animation!, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final song = context.select<PlayerController, Song?>((c) => c.current);
    final width = MediaQuery.sizeOf(context).width;
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: anim,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: GlowBackground.player(
                context,
                child: Stack(
                  children: [
                    Positioned(
                      left: (width - 220) / 2,
                      top: pad.top + 52,
                      child: Cover(song?.coverUrl, size: 220, radius: 30, shadows: [Shadow2(0, 28, 56, CoverArt.tint(song?.coverUrl).withValues(alpha: 0.35))]),
                    ),
                    Positioned.fill(child: ColoredBox(color: p.scrim)),
                    Positioned(
                      left: 16,
                      top: pad.top + 20,
                      child: GlassButton(YIcons.chevronDown, label: '关闭队列', onTap: () => Navigator.of(context).maybePop()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: pad.top + 112,
          bottom: 0,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(anim),
            child: GestureDetector(
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 500) Navigator.of(context).maybePop();
              },
              child: YBox(
                clip: true,
                radius: const BorderRadius.vertical(top: Radius.circular(34)),
                color: p.sheet,
                shadows: const [Shadow2(0, -12, 40, Color.fromRGBO(0, 0, 0, 0.2))],
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: const Material(type: MaterialType.transparency, child: QueueContent(handle: true)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 队列内容（标题、模式切换、可拖动排序的列表），移动端面板与桌面端侧栏共用。
class QueueContent extends StatelessWidget {
  const QueueContent({super.key, this.handle = false});

  final bool handle;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final cur = player.current;
    final next = player.upNext;
    final total = next.length + (cur == null ? 0 : 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (handle)
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(color: p.clearButton, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 18, 6, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '播放队列',
                      style: ts(24, weight: w700, em: -0.02, color: p.text),
                    ),
                    const SizedBox(height: 2),
                    Text('共 $total 首 · 接下来 ${next.length} 首', style: ts(13, color: p.text2)),
                  ],
                ),
              ),
              Pressable(
                onTap: next.isEmpty
                    ? null
                    : () async {
                        final ok = await showConfirm(context, title: '清空播放队列？', message: '将移除队列中的 ${next.length} 首歌曲，当前播放不受影响。', confirm: '清空');
                        if (ok) player.clearUpcoming();
                      },
                scale: 0.92,
                semanticLabel: '清空队列',
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: const Color.fromRGBO(220, 16, 49, 0.08), borderRadius: BorderRadius.circular(20)),
                  alignment: Alignment.center,
                  child: YIcon(YIcons.trash, size: 19, color: p.danger),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Segmented(height: 38, labels: const ['顺序播放', '随机播放', '单曲循环'], index: player.mode.index, onChanged: (i) => player.setMode(PlayMode.values[i])),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: cur == null
              ? Center(
                  child: Text('队列是空的', style: ts(14, color: p.text2)),
                )
              : ReorderableListView.builder(
                  padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16),
                  buildDefaultDragHandles: false,
                  header: _QueueRow(song: cur, current: true),
                  itemCount: next.length,
                  proxyDecorator: (child, _, _) => Material(type: MaterialType.transparency, child: child),
                  onReorderItem: (from, to) => player.moveUpNext(from, to),
                  itemBuilder: (context, i) => _QueueRow(key: ValueKey(next[i].key), song: next[i], index: i),
                ),
        ),
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({super.key, required this.song, this.current = false, this.index});

  final Song song;
  final bool current;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.read<PlayerController>();
    final row = Container(
      height: 58,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: current ? const Color.fromRGBO(220, 16, 49, 0.07) : Colors.transparent, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Cover(song.coverUrl, size: 42, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.name,
                  style: ts(15, weight: w600, color: current ? p.accentText : p.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  song.artistText,
                  style: ts(13, color: p.text2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (current) ...[
            const SizedBox(width: 12),
            NowPlayingBars(color: p.accentText, playing: context.select<PlayerController, bool>((c) => c.playing)),
            const SizedBox(width: 4),
          ],
          if (index != null)
            ReorderableDragStartListener(
              index: index!,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(child: YIcon(YIcons.drag, size: 20, color: p.muted)),
              ),
            )
          else
            SizedBox(
              width: 40,
              height: 40,
              child: Center(child: YIcon(YIcons.drag, size: 20, color: p.muted)),
            ),
        ],
      ),
    );
    final tappable = Pressable(onTap: current ? null : () => player.jumpTo(song), scale: 1, child: row);
    if (current) return tappable;
    return Dismissible(
      key: ValueKey('d-${song.key}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => player.removeSong(song),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: YIcon(YIcons.trash, size: 20, color: p.danger),
      ),
      child: tappable,
    );
  }
}

/// 桌面端：右侧浮出的玻璃队列面板。
void showDesktopQueue(BuildContext context) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭队列',
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.12),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, _, _) {
      final p = Palette.of(ctx);
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
          child: YBox(
            width: 380,
            radius: BorderRadius.circular(26),
            color: p.isDark ? const Color.fromRGBO(28, 29, 33, 0.92) : const Color.fromRGBO(255, 255, 255, 0.92),
            blur: true,
            border: p.glassBorder,
            shadows: p.sidebarShadow,
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: const Material(type: MaterialType.transparency, child: QueueContent()),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0.3, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: a, child: child),
    ),
  );
}
