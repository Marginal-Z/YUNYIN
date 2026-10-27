// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../data/models.dart';
import '../data/sources/source_manager.dart';
import '../features/common/actions.dart';
import '../features/shell/nav.dart';
import '../player/player_controller.dart';

/// 性能测试模式：设置环境变量 YUNYIN_BENCH=1 启动后，自动滚动各页面并打印帧耗时统计，然后退出。
/// 只用于在真实硬件上测量流畅度，正常使用时不会触发。
bool get benchmarkRequested => !kIsWeb && Platform.environment['YUNYIN_BENCH'] == '1';

class _Phase {
  _Phase(this.name);

  final String name;
  final List<FrameTiming> frames = [];
  final Stopwatch watch = Stopwatch();
}

Future<void> runBenchmark(GlobalKey<NavigatorState> navKey) async {
  final phases = <_Phase>[];
  _Phase? current;
  SchedulerBinding.instance.addTimingsCallback((list) => current?.frames.addAll(list));

  void report() {
    final rate = PlatformDispatcher.instance.displays.map((d) => d.refreshRate).fold<double>(0, math.max);
    final out = StringBuffer('\n===== 云音性能测试 =====\n显示器刷新率: ${rate.toStringAsFixed(0)} Hz\n');
    out.writeln('阶段 | 帧数 | 帧率 | 构建 平均/P90/最大 ms | 光栅 平均/P90/最大 ms | 等待垂直同步 平均 ms | 帧间隔 中位 ms');
    for (final p in phases) {
      final secs = math.max(p.watch.elapsedMilliseconds, 1) / 1000;
      String stats(Iterable<Duration> ds) {
        final v = ds.map((d) => d.inMicroseconds / 1000).toList()..sort();
        if (v.isEmpty) return '-';
        final avg = v.reduce((a, b) => a + b) / v.length;
        return '${avg.toStringAsFixed(1)}/${v[(v.length * 0.9).floor().clamp(0, v.length - 1)].toStringAsFixed(1)}/${v.last.toStringAsFixed(1)}';
      }

      final vsync = p.frames.isEmpty ? 0 : p.frames.map((f) => f.vsyncOverhead.inMicroseconds).reduce((a, b) => a + b) / p.frames.length / 1000;
      final starts = [for (final f in p.frames) f.timestampInMicroseconds(FramePhase.vsyncStart)];
      final gaps = [for (var i = 1; i < starts.length; i++) (starts[i] - starts[i - 1]) / 1000]..sort();
      final gap = gaps.isEmpty ? 0 : gaps[gaps.length ~/ 2];
      out.writeln(
        '${p.name} | ${p.frames.length} | ${(p.frames.length / secs).toStringAsFixed(0)} | '
        '${stats(p.frames.map((f) => f.buildDuration))} | ${stats(p.frames.map((f) => f.rasterDuration))} | '
        '${vsync.toStringAsFixed(1)} | ${gap.toStringAsFixed(1)}',
      );
    }
    stderr.writeln(out);
  }

  // 看门狗：任何一步卡住都输出已收集的数据并退出。
  Timer(const Duration(seconds: 100), () {
    stderr.writeln('bench: 超时，输出已收集的数据');
    report();
    exit(1);
  });

  Future<void> phase(String name, Future<void> Function() body) async {
    var state = '';
    try {
      state = '焦点=${await windowManager.isFocused()} 可见=${await windowManager.isVisible()} 最小化=${await windowManager.isMinimized()}';
    } catch (_) {}
    stderr.writeln('bench: $name $state');
    final p = _Phase(name);
    phases.add(p);
    current = p;
    p.watch.start();
    await body();
    // 等待最后几帧的统计回传。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    p.watch.stop();
    current = null;
  }

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  /// 以 4ms 间隔持续发送滚轮事件，帧率只受渲染能力和屏幕刷新率限制。
  Future<void> scroll(Offset at, double perEvent, int ms) {
    final done = Completer<void>();
    final sw = Stopwatch()..start();
    Timer.periodic(const Duration(milliseconds: 4), (t) {
      GestureBinding.instance.handlePointerEvent(PointerScrollEvent(position: at, scrollDelta: Offset(0, perEvent)));
      if (sw.elapsedMilliseconds >= ms) {
        t.cancel();
        done.complete();
      }
    });
    return done.future;
  }

  stderr.writeln('bench: 等待首页数据');
  await wait(4000);
  // 把窗口置于前台，避免合成器对被遮挡的窗口降低刷新频率。
  try {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAlwaysOnTop(true);
  } catch (_) {}
  await wait(5000);
  final ctx = navKey.currentContext!;
  final nav = ctx.read<AppNav>();
  final player = ctx.read<PlayerController>();
  final source = ctx.read<SourceManager>().current;
  final view = PlatformDispatcher.instance.views.first;
  Size logical() => view.physicalSize / view.devicePixelRatio;

  await phase('桌面·空闲', () => wait(2000));
  await phase('桌面·页面切换', () async {
    for (var i = 0; i < 3; i++) {
      nav.push(DiscoverRoute());
      await wait(600);
      nav.pop();
      await wait(600);
    }
  });
  await phase('桌面·首页滚动', () async {
    final s = logical();
    await scroll(Offset(s.width * 0.6, s.height * 0.5), 6, 2500);
    await scroll(Offset(s.width * 0.6, s.height * 0.5), -6, 2500);
  });

  List<Song> songs = const [];
  try {
    final lists = await source.recommendPlaylists(limit: 1);
    final pl = await source.playlist(lists.first.id);
    songs = pl.tracks ?? const [];
    nav.push(PlaylistRoute(pl.id, preview: pl, sourceId: pl.sourceId));
  } catch (e) {
    stderr.writeln('bench: 加载歌单失败 $e');
  }
  await wait(1500);
  await phase('桌面·歌单滚动', () async {
    final s = logical();
    await scroll(Offset(s.width * 0.6, s.height * 0.5), 8, 3000);
  });
  if (songs.isNotEmpty) unawaited(player.playSongs(songs.take(5).toList()));
  await wait(2500);
  await phase('桌面·播放中空闲', () => wait(3000));
  openPlayer(navKey.currentContext!);
  await phase('桌面·正在播放页', () => wait(4000));
  navKey.currentState?.maybePop();
  await wait(800);

  await windowManager.setSize(const Size(430, 900));
  await wait(1500);
  nav.switchTab(0);
  await wait(800);
  await phase('移动·首页滚动', () async {
    final s = logical();
    await scroll(Offset(s.width * 0.5, s.height * 0.45), 6, 2500);
    await scroll(Offset(s.width * 0.5, s.height * 0.45), -6, 2500);
  });
  await phase('移动·标签切换', () async {
    for (final t in [1, 2, 0, 2, 1, 0]) {
      nav.switchTab(t);
      await wait(500);
    }
  });

  report();
  exit(0);
}
