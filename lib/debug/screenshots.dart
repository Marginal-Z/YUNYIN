// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import '../data/sources/source_manager.dart';
import '../features/common/actions.dart';
import '../features/shell/nav.dart';
import '../player/player_controller.dart';

/// 截图模式：设置环境变量 YUNYIN_SHOTS=<输出目录> 启动桌面版后，应用以固定的桌面 / 手机尺寸渲染，
/// 依次打开真实页面并把渲染结果保存为 PNG（官网截图用），完成后退出。正常使用时不会触发。
String? get screenshotDir {
  if (kIsWeb) return null;
  final d = Platform.environment['YUNYIN_SHOTS'];
  return d == null || d.isEmpty ? null : d;
}

bool get screenshotsRequested => screenshotDir != null;

/// 截图时的逻辑尺寸、安全区与像素倍率。
class ShotSpec {
  const ShotSpec(this.size, this.pixelRatio, {this.padding = EdgeInsets.zero, this.textScale = 1});

  final Size size;
  final double pixelRatio;
  final EdgeInsets padding;
  final double textScale;
}

const _desktop = ShotSpec(Size(1440, 900), 2);
// 手机：与常见 Android 机型相同的逻辑宽度，顶部状态栏与底部手势条的安全区。
const _mobile = ShotSpec(Size(392, 850), 3, padding: EdgeInsets.only(top: 40, bottom: 20));
// 适配检查：小屏手机 + 系统字体放大、横屏手机、最小桌面窗口。
const _small = ShotSpec(Size(320, 640), 2, padding: EdgeInsets.only(top: 24, bottom: 16), textScale: 1.3);
const _landscape = ShotSpec(Size(780, 360), 2, padding: EdgeInsets.only(left: 24, right: 24));
const _desktopMin = ShotSpec(Size(960, 640), 2);

final ValueNotifier<ShotSpec?> _spec = ValueNotifier(null);
final GlobalKey _boundary = GlobalKey();

/// 把整个应用放进固定尺寸的画布；尺寸可以大于窗口，截图时按画布完整渲染。
class ShotFrame extends StatelessWidget {
  const ShotFrame({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ShotSpec?>(
      valueListenable: _spec,
      builder: (context, spec, _) {
        if (spec == null) return builder(context);
        final mq = MediaQuery.of(context);
        return OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: spec.size.width,
          maxWidth: spec.size.width,
          minHeight: spec.size.height,
          maxHeight: spec.size.height,
          child: RepaintBoundary(
            key: _boundary,
            child: MediaQuery(
              data: mq.copyWith(
                size: spec.size,
                padding: spec.padding,
                viewPadding: spec.padding,
                devicePixelRatio: spec.pixelRatio,
                textScaler: TextScaler.linear(spec.textScale),
              ),
              child: Builder(builder: builder),
            ),
          ),
        );
      },
    );
  }
}

Future<void> runScreenshots(GlobalKey<NavigatorState> navKey) async {
  final out = Directory(screenshotDir!)..createSync(recursive: true);
  Timer(const Duration(minutes: 8), () {
    stderr.writeln('shots: 超时退出');
    exit(1);
  });
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
  BuildContext ctx() => navKey.currentContext!;

  while (navKey.currentContext == null) {
    await wait(100);
  }
  final settings = ctx().read<AppSettings>();
  final player = ctx().read<PlayerController>();
  final nav = ctx().read<AppNav>();
  final source = ctx().read<SourceManager>().current;
  await player.setVolume(0);
  settings.setThemeMode(ThemeMode.light);

  Future<void> shot(String name, {int settle = 2500}) async {
    await wait(settle);
    await WidgetsBinding.instance.endOfFrame;
    final spec = _spec.value!;
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: spec.pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${out.path}/$name.png').writeAsBytes(png!.buffer.asUint8List());
    stderr.writeln('shots: $name ${image.width}x${image.height}');
  }

  void home() {
    while (navKey.currentState!.canPop()) {
      navKey.currentState!.pop();
    }
    nav.switchTab(0);
    nav.switchTab(0);
  }

  // 选一首有逐行歌词的推荐歌曲，并跳到歌曲中段，让播放页与歌词页呈现真实的播放状态。
  final feed = await source.homeFeed();
  await playAll(ctx(), feed.daily, title: '每日推荐');
  for (var i = 0; i < 8; i++) {
    for (var t = 0; t < 40 && (player.duration == Duration.zero || player.lyrics.lines.isEmpty); t++) {
      await wait(200);
    }
    if (player.lyrics.synced && player.lyrics.lines.length > 12) break;
    await player.next();
    await wait(800);
  }
  final lines = player.lyrics.lines;
  if (lines.length > 12) await player.seek(lines[lines.length ~/ 3].time + const Duration(milliseconds: 1200));

  Future<void> tour(String prefix, ShotSpec spec, {required bool dark}) async {
    settings.setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
    _spec.value = spec;
    home();
    await shot('$prefix-home${dark ? '-dark' : ''}', settle: 5000);
    openPlayer(ctx());
    await shot('$prefix-player${dark ? '-dark' : ''}', settle: 3500);
    if (spec == _mobile) {
      navKey.currentState!.pop();
      await wait(600);
      openLyrics(ctx());
      await shot('$prefix-lyrics${dark ? '-dark' : ''}', settle: 1800);
    }
    if (dark) return;
    home();
    await wait(600);
    if (spec == _mobile) {
      nav.switchTab(1);
    } else {
      nav.push(DiscoverRoute());
    }
    await shot('$prefix-discover', settle: 4500);
    if (feed.playlists.isNotEmpty) {
      openPlaylist(ctx(), feed.playlists.first);
      await shot('$prefix-playlist', settle: 4500);
    }
  }

  await tour('desktop', _desktop, dark: false);
  await tour('desktop', _desktop, dark: true);
  await tour('mobile', _mobile, dark: false);
  await tour('mobile', _mobile, dark: true);

  // 「柔和」玻璃材质与封面取色背景。
  settings.setThemeMode(ThemeMode.light);
  settings.setGlassMaterial(GlassMaterial.regular);
  _spec.value = _mobile;
  home();
  await shot('mobile-home-regular', settle: 3000);
  openPlayer(ctx());
  await shot('mobile-player-regular', settle: 3000);
  navKey.currentState!.pop();
  settings.setGlassMaterial(GlassMaterial.clear);
  settings.setBackground(BackgroundMode.cover);
  home();
  await shot('mobile-home-cover', settle: 3500);
  _spec.value = _desktop;
  home();
  await shot('desktop-home-cover', settle: 3500);
  settings.setBackground(BackgroundMode.glow);

  // 适配检查。
  Future<void> fit(String prefix, ShotSpec spec, {bool lyrics = true}) async {
    _spec.value = spec;
    home();
    await shot('$prefix-home', settle: 3000);
    openPlayer(ctx());
    await shot('$prefix-player', settle: 2500);
    navKey.currentState!.pop();
    if (lyrics) {
      await wait(500);
      openLyrics(ctx());
      await shot('$prefix-lyrics', settle: 1800);
      navKey.currentState!.pop();
    }
    home();
    await wait(500);
    if (spec.size.width < 860) {
      nav.switchTab(1);
      nav.switchTab(1);
    } else {
      nav.push(DiscoverRoute());
    }
    await shot('$prefix-discover', settle: 2500);
    if (feed.playlists.isNotEmpty) {
      openPlaylist(ctx(), feed.playlists.first);
      await shot('$prefix-playlist', settle: 2500);
    }
  }

  // 听歌统计（巡览期间播放的时长）。
  _spec.value = _mobile;
  home();
  nav.push(StatsRoute());
  await shot('mobile-stats', settle: 2000);
  _spec.value = _desktop;
  home();
  nav.push(StatsRoute());
  await shot('desktop-stats', settle: 2000);

  await fit('small', _small);
  await fit('landscape', _landscape);
  await fit('desktopmin', _desktopMin, lyrics: false);
  stderr.writeln('shots: 完成 → ${out.path}');
  exit(0);
}
