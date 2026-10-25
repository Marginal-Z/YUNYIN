import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';

/// 滚动歌词。当前行放大高亮并自动滚动到 [anchor] 位置，点击某行跳转。
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.desktop, this.anchor = 0.3, this.padding = EdgeInsets.zero});

  final bool desktop;

  /// 当前行在可视区域中的位置（0 顶部，1 底部）。
  final double anchor;
  final EdgeInsets padding;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _scroll = ScrollController();
  List<GlobalKey> _keys = [];
  Lyrics? _lyrics;
  int _active = -2;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int i) {
    if (i == _active) return;
    _active = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || i < 0 || i >= _keys.length) return;
      final ctx = _keys[i].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx, alignment: widget.anchor, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    });
  }

  TextStyle _style(Palette p, int d) {
    if (widget.desktop) {
      return d == 0
          ? ts(44, weight: w700, em: -0.02, height: 1.3, color: p.lyricActive)
          : ts(32, weight: w700, em: -0.01, height: 1.35, color: p.lyricDim);
    }
    return switch (d) {
      0 => ts(34, weight: w700, em: -0.01, height: 1.3, color: p.lyricActive),
      1 => ts(26, weight: w600, em: -0.01, height: 1.3, color: p.playerText2),
      -1 || 2 => ts(24, weight: d == -1 ? w600 : w500, em: -0.01, height: 1.3, color: p.lyricDim),
      _ => ts(22, weight: w500, em: -0.01, height: 1.3, color: p.lyricDim),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.read<PlayerController>();
    final lyrics = context.select<PlayerController, Lyrics>((c) => c.lyrics);
    final showTr = context.select<AppSettings, bool>((s) => s.showTranslation);
    if (!identical(lyrics, _lyrics)) {
      _lyrics = lyrics;
      _keys = List.generate(lyrics.lines.length, (_) => GlobalKey());
      _active = -2;
    }
    if (lyrics.lines.isEmpty) {
      return Align(
        alignment: widget.desktop ? Alignment.centerLeft : Alignment.topLeft,
        child: Padding(
          padding: widget.padding,
          child: Text('暂无歌词，请欣赏', style: _style(p, 1)),
        ),
      );
    }
    return ValueListenableBuilder<Duration>(
      valueListenable: player.position,
      builder: (context, pos, _) {
        final active = lyrics.indexAt(pos);
        if (lyrics.synced) _follow(active);
        return ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
            stops: [0, 0.08, 0.86, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: widget.padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lyrics.lines.length; i++)
                  Padding(
                    key: _keys[i],
                    padding: EdgeInsets.only(bottom: widget.desktop ? 22 : 22),
                    child: Pressable(
                      onTap: lyrics.synced ? () => player.seek(lyrics.lines[i].time) : null,
                      scale: 1,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                        style: _style(p, lyrics.synced ? i - active : 3),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(lyrics.lines[i].text),
                          if (showTr && (lyrics.lines[i].translation ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(lyrics.lines[i].translation!,
                                  style: ts(widget.desktop ? 20 : 16, weight: w500, color: i == active ? p.playerText2 : p.lyricDim)),
                            ),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
