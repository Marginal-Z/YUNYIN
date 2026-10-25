import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import 'lyrics_view.dart';
import 'player_page.dart';

/// 移动端全屏歌词。Android 上隐藏系统栏沉浸显示；歌词铺满屏幕，控件闲置几秒后自动隐藏，轻点空白处重新显示。
class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  static final _immersive = Platform.isAndroid;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    if (_immersive) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _poke();
  }

  @override
  void dispose() {
    _hide?.cancel();
    if (_immersive) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// 有操作时保持控件显示，并重新计时。
  void _poke() {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && context.read<PlayerController>().playing) setState(() => _controls = false);
    });
  }

  void _toggle() {
    if (_controls) {
      _hide?.cancel();
      setState(() => _controls = false);
    } else {
      _poke();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.watch<PlayerController>();
    final settings = context.watch<AppSettings>();
    final song = player.current;
    final pad = MediaQuery.paddingOf(context);
    if (song == null) return GlowBackground.player(context);
    final liked = player.isLiked(song);
    // 横屏：歌词在左，歌曲卡片与控制卡片在右侧一栏。
    final size = MediaQuery.sizeOf(context);
    final land = size.width > size.height * 1.3;
    final side = land ? (size.width * 0.42).clamp(300.0, 380.0) : 0.0;
    Widget fade(Widget child, {required bool top}) => IgnorePointer(
      ignoring: !_controls,
      child: AnimatedOpacity(
        opacity: _controls ? 1 : 0,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: _controls ? Offset.zero : Offset(0, top ? -0.15 : 0.15),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          child: child,
        ),
      ),
    );
    return GlowBackground.player(
      context,
      child: Listener(
        onPointerDown: (_) {
          if (_controls) _poke();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _toggle),
            ),
            // 控件显示时歌词从顶部卡片下方开始，避免与卡片重叠；控件隐藏后歌词铺满全屏。
            AnimatedPositioned(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              left: 28,
              right: land && _controls ? side + 40 : 28,
              top: pad.top + (land ? 76 : (_controls ? 168 : 12)),
              bottom: pad.bottom,
              child: const LyricsView(desktop: false, anchor: 0.3),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: fade(
                top: true,
                SizedBox(
                  height: pad.top + 160,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 16,
                        top: pad.top + 20,
                        child: GlassButton(YIcons.chevronDown, label: '收起歌词', onTap: () => Navigator.of(context).maybePop()),
                      ),
                      Positioned(
                        left: 76,
                        right: 76,
                        top: pad.top + 20,
                        height: 44,
                        child: Center(
                          child: Text(
                            '歌词',
                            style: ts(11, weight: w700, em: 0.14, color: p.playerText2),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        top: pad.top + 20,
                        child: GlassButton(
                          YIcons.more,
                          label: '歌词选项',
                          onTap: () async {
                            final v = await showOptions<int>(
                              context,
                              title: '歌词选项',
                              options: [(0, settings.showTranslation ? '隐藏翻译' : '显示翻译'), (1, '查看评论'), (2, '歌曲操作')],
                            );
                            if (!context.mounted) return;
                            if (v == 0) settings.setFlag('showTranslation', !settings.showTranslation);
                            if (v == 1) openComments(context, song);
                            if (v == 2) showSongMenu(context, song);
                          },
                        ),
                      ),
                      Positioned(
                        left: land ? size.width - side - 20 : 20,
                        right: 20,
                        top: pad.top + 84,
                        child: YBox(
                          height: 72,
                          radius: BorderRadius.circular(24),
                          color: p.lyricsCard,
                          shadows: p.cardShadow,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Cover(song.coverUrl, size: 48, radius: 12),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.name,
                                      style: ts(16, weight: w700, color: p.text),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      song.subtitle,
                                      style: ts(13, color: p.playerText2),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Pressable(
                                onTap: () => player.toggleLike(song),
                                scale: 0.9,
                                semanticLabel: liked ? '取消喜欢' : '喜欢',
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(color: p.isDark ? p.translucentButton : Colors.white, shape: BoxShape.circle),
                                  alignment: Alignment.center,
                                  child: YIcon(liked ? YIcons.heart : YIcons.heartOutline, size: 20, color: p.accentText),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: land ? size.width - side - 20 : 20,
              right: 20,
              bottom: 22 + pad.bottom,
              child: fade(
                top: false,
                LiquidGlass(
                  radius: 34,
                  height: 150,
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                  child: Column(
                    children: [
                      ValueListenableBuilder<Duration>(
                        valueListenable: player.position,
                        builder: (context, pos, _) {
                          final total = player.duration;
                          final f = total.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / total.inMilliseconds;
                          final remain = total - pos;
                          return Column(
                            children: [
                              SeekBar(value: f, onSeek: player.seekFraction),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    formatDuration(pos),
                                    style: ts(12, weight: w500, color: p.playerText2, tabular: true),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '-${formatDuration(remain.isNegative ? Duration.zero : remain)}',
                                    style: ts(12, weight: w500, color: p.playerText2, tabular: true),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Pressable(
                            onTap: () => settings.setFlag('showTranslation', !settings.showTranslation),
                            scale: 0.9,
                            semanticLabel: '歌词翻译',
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: Text(
                                  '译',
                                  style: ts(15, weight: w700, color: settings.showTranslation ? p.accentText : p.playerText2),
                                ),
                              ),
                            ),
                          ),
                          YIconButton(YIcons.prev, size: 52, iconSize: 30, label: '上一首', onTap: player.previous),
                          const PlayButton(size: 64, iconSize: 28, shadow: true, largePause: false),
                          YIconButton(YIcons.next, size: 52, iconSize: 30, label: '下一首', onTap: player.next),
                          YIconButton(YIcons.queue, size: 44, iconSize: 24, color: p.playerText2, label: '播放队列', onTap: () => openQueue(context)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
