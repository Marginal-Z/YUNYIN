import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/system_bars.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import 'lyrics_view.dart';
import 'player_page.dart';
import '../common/song_cover.dart';

/// 移动端全屏歌词。Android 上隐藏系统栏沉浸显示；歌词铺满屏幕，控件闲置几秒后自动隐藏，轻点空白处重新显示。
class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  static final _android = Platform.isAndroid;

  /// 上下的歌曲信息与播放控件是否显示：只有点按“全屏歌词”按钮才隐藏，不会自动隐藏。
  bool _controls = true;

  /// 沉浸状态栏：竖屏时保留透明的状态栏（时间、电量照常显示，页面画到状态栏后面），顶部按钮紧贴状态栏；
  /// 此前一直隐藏状态栏，但页面仍按状态栏（或挖孔）高度留白，按钮下面空出一截，看起来往下沉。
  /// 只有横屏与“全屏歌词”时才完全隐藏系统栏。
  void _syncBars() {
    if (!_android || !mounted) return;
    final size = MediaQuery.sizeOf(context);
    SystemBars.immersive(this, size.width > size.height * 1.3 || !_controls);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBars();
  }

  @override
  void dispose() {
    if (_android) SystemBars.immersive(this, false);
    super.dispose();
  }

  void _setFullscreen(bool on) {
    setState(() => _controls = !on);
    _syncBars();
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
    // 控件隐藏时滑出屏幕。不用透明度渐隐：液态玻璃是背景滤镜，叠加透明度时 Impeller 无法正确合成，会闪烁。
    Widget fade(Widget child, {required bool top}) => IgnorePointer(
      ignoring: !_controls,
      child: AnimatedSlide(
        offset: _controls ? Offset.zero : Offset(0, top ? -1.05 : 1.6),
        duration: Duration(milliseconds: _controls ? 520 : 420),
        curve: _controls ? Curves.easeOutCubic : Curves.easeInCubic,
        child: child,
      ),
    );
    return GlowBackground.player(
      context,
      flow: player.playing,
      child: Stack(
        children: [
          // 控件显示时歌词从顶部卡片下方开始，避免与卡片重叠；控件隐藏后歌词铺满全屏。
          AnimatedPositioned(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            left: 28,
            right: land && _controls ? side + 40 : 28,
            top: pad.top + (land ? 64 : (_controls ? 148 : 12)),
            bottom: pad.bottom + (!land && _controls ? 172 : 0),
            child: const LyricsView(desktop: false, anchor: 0.3),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: fade(
              top: true,
              SizedBox(
                height: pad.top + 140,
                child: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      top: pad.top + 8,
                      child: YIconButton(
                        YIcons.chevronDown,
                        size: 44,
                        iconSize: 26,
                        color: p.text,
                        label: '收起歌词',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    Positioned(
                      left: 76,
                      right: 76,
                      top: pad.top + 8,
                      height: 44,
                      child: Center(
                        child: Text(
                          '歌词',
                          style: ts(11, weight: w700, em: 0.14, color: p.playerText2),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 64,
                      top: pad.top + 8,
                      child: YIconButton(YIcons.fullscreen, size: 44, iconSize: 22, color: p.text, label: '全屏歌词', onTap: () => _setFullscreen(true)),
                    ),
                    Positioned(
                      right: 16,
                      top: pad.top + 8,
                      child: YIconButton(
                        YIcons.more,
                        size: 44,
                        iconSize: 24,
                        color: p.text,
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
                      top: pad.top + 64,
                      // 歌曲信息不加卡片背景。
                      child: Container(
                        height: 72,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            SongCover(song, size: 48, radius: 12),
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
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: Center(child: YIcon(liked ? YIcons.heart : YIcons.heartOutline, size: 24, color: p.playerAccent ?? p.accentText)),
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
              // 控制区透明、无背景框；歌词区域在控件显示时止于其上方，两者不重叠。
              Container(
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
                            SeekBar(
                              value: f,
                              onSeek: player.seekFraction,
                              style: settings.progressStyle,
                              playing: player.playing,
                              seed: player.current?.key.hashCode ?? 0,
                            ),
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
          // 全屏歌词时右下角的退出按钮（只在全屏时显示）。
          Positioned(
            right: 20,
            bottom: pad.bottom + 20,
            child: IgnorePointer(
              ignoring: _controls,
              child: AnimatedOpacity(
                opacity: _controls ? 0 : 1,
                duration: const Duration(milliseconds: 300),
                child: YIconButton(YIcons.exitFullscreen, size: 44, iconSize: 22, color: p.playerText2, label: '退出全屏歌词', onTap: () => _setFullscreen(false)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
