// ignore_for_file: use_build_context_synchronously, avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import '../data/models.dart';
import '../data/sources/source_manager.dart';
import '../features/common/actions.dart';
import '../features/settings/about_pages.dart' show AboutPage;
import '../features/shell/nav.dart';
import '../player/player_controller.dart';

/// 手机上的流畅度测试：adb shell am start -n com.marginalz.yunyin/.MainActivity --ez yunyin_bench true 启动后，
/// 依次打开各个页面、模拟手指滑动、返回，按页面统计帧耗时，结果以 “bench|” 开头写进日志。
///
/// 只读：不播放、不改账号与歌单；测液态玻璃开关时测完恢复原来的设置。正常启动不会触发。
/// 启动后问原生端这次是不是带着 yunyin_bench 打开的（Flutter 引擎由 audio_service 创建，收不到启动参数）。
Future<void> maybeRunMobileBenchmark(GlobalKey<NavigatorState> navKey) async {
  if (kIsWeb || !Platform.isAndroid) return;
  await Future<void>.delayed(const Duration(seconds: 2));
  try {
    final want = await const MethodChannel('yunyin/diagnostics').invokeMethod<bool>('benchRequested');
    if (want == true) await runMobileBenchmark(navKey);
  } catch (_) {}
}

class _Phase {
  _Phase(this.name);

  final String name;
  final List<FrameTiming> frames = [];
}

Future<void> runMobileBenchmark(GlobalKey<NavigatorState> navKey) async {
  final phases = <_Phase>[];
  _Phase? current;
  SchedulerBinding.instance.addTimingsCallback((list) => current?.frames.addAll(list));
  final view = PlatformDispatcher.instance.views.first;
  final rate = view.display.refreshRate <= 0 ? 60 : view.display.refreshRate;
  final budget = 1000 / rate;

  void report() {
    print('bench|===== 云音手机流畅度测试 · 屏幕 ${rate.toStringAsFixed(0)} Hz，一帧 ${budget.toStringAsFixed(2)} ms =====');
    print('bench|页面 | 帧数 | 超时帧 | 超时比例 | 最慢 ms | 构建 P90/最大 | 光栅 P90/最大');
    for (final p in phases) {
      final total = [for (final f in p.frames) f.totalSpan.inMicroseconds / 1000]..sort();
      final build = [for (final f in p.frames) f.buildDuration.inMicroseconds / 1000]..sort();
      final raster = [for (final f in p.frames) f.rasterDuration.inMicroseconds / 1000]..sort();
      double p90(List<double> v) => v.isEmpty ? 0 : v[(v.length * 0.9).floor().clamp(0, v.length - 1)];
      final late = total.where((t) => t > budget * 1.05).length;
      print(
        'bench|${p.name} | ${total.length} | $late | ${total.isEmpty ? 0 : (late * 100 / total.length).toStringAsFixed(1)}% | '
        '${total.isEmpty ? 0 : total.last.toStringAsFixed(1)} | ${p90(build).toStringAsFixed(1)}/${build.isEmpty ? 0 : build.last.toStringAsFixed(1)} | '
        '${p90(raster).toStringAsFixed(1)}/${raster.isEmpty ? 0 : raster.last.toStringAsFixed(1)}',
      );
    }
    print('bench|===== 结束 =====');
  }

  var finished = false;
  Timer(const Duration(minutes: 4), () {
    if (finished) return;
    print('bench|超时，输出已收集的数据');
    report();
  });

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> phase(String name, Future<void> Function() body) async {
    print('bench|开始 $name');
    final p = _Phase(name);
    phases.add(p);
    current = p;
    try {
      await body();
    } catch (e) {
      print('bench|$name 出错：$e');
    }
    await wait(300);
    current = null;
  }

  var pointer = 900;

  /// 模拟一次手指快速滑动：按下、每 8 毫秒移动一段、抬起，松手后由页面自己惯性滚动。
  Future<void> fling(Offset at, double dy) async {
    final id = ++pointer;
    const steps = 18;
    var pos = at;
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: id, position: pos, kind: PointerDeviceKind.touch));
    for (var i = 0; i < steps; i++) {
      await wait(8);
      final next = pos + Offset(0, dy / steps);
      GestureBinding.instance.handlePointerEvent(PointerMoveEvent(pointer: id, position: next, delta: next - pos, kind: PointerDeviceKind.touch));
      pos = next;
    }
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: id, position: pos, kind: PointerDeviceKind.touch));
  }

  Size logical() => view.physicalSize / view.devicePixelRatio;

  /// 往下滑两次、再往上滑两次，等惯性滚动停下。
  Future<void> scrollPage() async {
    final s = logical();
    final at = Offset(s.width * 0.5, s.height * 0.62);
    for (final dy in [-s.height * 0.45, -s.height * 0.45, s.height * 0.45, s.height * 0.45]) {
      await fling(at, dy);
      await wait(700);
    }
  }

  print('bench|等待首页数据');
  await wait(6000);
  final ctx = navKey.currentContext!;
  final nav = ctx.read<AppNav>();
  final settings = ctx.read<AppSettings>();
  final player = ctx.read<PlayerController>();
  final source = ctx.read<SourceManager>().current;
  nav.switchTab(0);
  await wait(800);

  await phase('首页·空闲', () => wait(2000));
  await phase('首页·滚动', scrollPage);
  if (settings.glass) {
    settings.setFlag('glass', false);
    await wait(800);
    await phase('首页·滚动（液态玻璃关）', scrollPage);
    settings.setFlag('glass', true);
    await wait(800);
  }
  await phase('底部标签切换', () async {
    for (final t in [1, 2, 0, 2, 1, 0]) {
      nav.switchTab(t);
      await wait(600);
    }
  });

  /// 打开页面（含转场）、滑动、返回（含返回转场）。
  Future<void> visit(String name, AppRoute route, {bool scroll = true}) async {
    await phase(name, () async {
      nav.push(route);
      await wait(1200);
      if (scroll) await scrollPage();
      nav.pop();
      await wait(900);
    });
  }

  await visit('发现', DiscoverRoute());
  await visit('乐库', LibraryRoute());
  await visit('搜索', SearchRoute(), scroll: false);
  await visit('个人中心', ProfileRoute());
  await visit('听歌统计', StatsRoute());
  await visit('设置', SettingsRoute());
  await visit('设置·外观', AppearanceRoute());
  await visit('设置·播放', PlaybackSettingsRoute());
  await visit('设置·音效', AudioEffectsRoute());
  await visit('设置·均衡器', EqualizerRoute());
  await visit('设置·存储', StorageSettingsRoute());
  await visit('设置·桌面歌词', LyricsOverlayRoute());
  await visit('设置·云音助手', AssistantSettingsRoute());
  await visit('设置·音色中心', VoiceCenterRoute());
  await visit('设置·桌宠', PetRoute());
  await visit('设置·关于', SettingsMoreRoute());
  await visit('设置·问题诊断', DiagnosticsRoute(), scroll: false);
  await visit('设置·隐私政策', AboutRoute(AboutPage.privacy));

  // 歌单、专辑、歌手：取当前平台的第一个推荐歌单。
  try {
    final lists = await source.recommendPlaylists(limit: 1);
    final pl = await source.playlist(lists.first.id);
    await visit('歌单', PlaylistRoute(pl.id, preview: pl, sourceId: pl.sourceId));
    final song = (pl.tracks ?? const <Song>[]).firstOrNull;
    final album = song?.album;
    if (album != null && album.id.isNotEmpty) await visit('专辑', AlbumRoute(album.id, sourceId: song!.sourceId));
    final artist = song?.artists.firstOrNull;
    if (artist != null && artist.id.isNotEmpty) await visit('歌手', ArtistRoute(artist.id, name: artist.name, sourceId: song!.sourceId));
  } catch (e) {
    print('bench|没有取到推荐歌单，跳过歌单、专辑与歌手：$e');
  }

  if (player.current != null) {
    await phase('播放页', () async {
      openPlayer(navKey.currentContext!);
      await wait(2500);
      navKey.currentState?.maybePop();
      await wait(1000);
    });
    await phase('歌词页', () async {
      openLyrics(navKey.currentContext!);
      await wait(3000);
      navKey.currentState?.maybePop();
      await wait(1000);
    });
  } else {
    print('bench|当前没有歌曲，跳过播放页与歌词页');
  }

  finished = true;
  report();
  nav.switchTab(0);
}
