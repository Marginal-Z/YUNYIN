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

  Future<void> phase(String name, Future<void> Function() body) async {
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

  /// 每帧发送一次滚轮事件，模拟持续滚动。
  Future<void> scroll(Offset at, double perFrame, int ms) async {
    final done = Completer<void>();
    final end = DateTime.now().add(Duration(milliseconds: ms));
    void tick(Duration _) {
      GestureBinding.instance.handlePointerEvent(PointerScrollEvent(position: at, scrollDelta: Offset(0, perFrame)));
      if (DateTime.now().isBefore(end)) {
        SchedulerBinding.instance.scheduleFrameCallback(tick);
        SchedulerBinding.instance.scheduleFrame();
      } else {
        done.complete();
      }
    }

    SchedulerBinding.instance.scheduleFrameCallback(tick);
    SchedulerBinding.instance.scheduleFrame();
    return done.future;
  }

  await wait(9000);
  final ctx = navKey.currentContext!;
  final nav = ctx.read<AppNav>();
  final player = ctx.read<PlayerController>();
  final source = ctx.read<SourceManager>().current;
  final view = PlatformDispatcher.instance.views.first;
  Size logical() => view.physicalSize / view.devicePixelRatio;

  await phase('桌面·空闲', () => wait(2000));
  await phase('桌面·首页滚动', () async {
    final s = logical();
    await scroll(Offset(s.width * 0.6, s.height * 0.5), 18, 2500);
    await scroll(Offset(s.width * 0.6, s.height * 0.5), -18, 2500);
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
    await scroll(Offset(s.width * 0.6, s.height * 0.5), 24, 3000);
  });
  if (songs.isNotEmpty) await player.playSongs(songs.take(5).toList());
  await wait(1500);
  await phase('桌面·播放中空闲', () => wait(3000));
  final pctx = navKey.currentContext!;
  if (pctx.mounted) openPlayer(pctx);
  await phase('桌面·正在播放页', () => wait(4000));
  navKey.currentState?.maybePop();
  await wait(800);

  await windowManager.setSize(const Size(430, 900));
  await wait(1500);
  nav.switchTab(0);
  await wait(800);
  await phase('移动·首页滚动', () async {
    final s = logical();
    await scroll(Offset(s.width * 0.5, s.height * 0.45), 18, 2500);
    await scroll(Offset(s.width * 0.5, s.height * 0.45), -18, 2500);
  });

  final rate = PlatformDispatcher.instance.displays.map((d) => d.refreshRate).fold<double>(0, math.max);
  final out = StringBuffer('\n===== 云音性能测试 =====\n显示器刷新率: ${rate.toStringAsFixed(0)} Hz\n');
  out.writeln('阶段 | 帧数 | 帧率 | 构建 平均/P90/最大 ms | 光栅 平均/P90/最大 ms');
  for (final p in phases) {
    final secs = p.watch.elapsedMilliseconds / 1000;
    String stats(Iterable<Duration> ds) {
      final v = ds.map((d) => d.inMicroseconds / 1000).toList()..sort();
      if (v.isEmpty) return '-';
      final avg = v.reduce((a, b) => a + b) / v.length;
      return '${avg.toStringAsFixed(1)}/${v[(v.length * 0.9).floor().clamp(0, v.length - 1)].toStringAsFixed(1)}/${v.last.toStringAsFixed(1)}';
    }

    out.writeln('${p.name} | ${p.frames.length} | ${(p.frames.length / secs).toStringAsFixed(0)} | '
        '${stats(p.frames.map((f) => f.buildDuration))} | ${stats(p.frames.map((f) => f.rasterDuration))}');
  }
  stderr.writeln(out);
  exit(0);
}
