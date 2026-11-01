import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/music_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/player/player_controller.dart';

class _Streams implements PlayerStream {
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<String> get error => const Stream.empty();
  @override
  Stream<PlayerLog> get log => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engine implements Player {
  bool failOpen = false;
  int playCalls = 0;
  final stops = <Completer<void>>[];
  bool delayStop = false;
  @override
  PlayerStream get stream => _Streams();
  @override
  PlayerState get state => const PlayerState();
  @override
  PlatformPlayer? get platform => null;
  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (failOpen) throw Exception('open failed');
  }

  @override
  Future<void> stop() async {
    if (!delayStop) return;
    final completion = Completer<void>();
    stops.add(completion);
    await completion.future;
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> seek(Duration duration) async {}
  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Source extends MusicSource {
  _Source(this.id);
  @override
  final String id;
  Object? streamError;
  Completer<StreamInfo>? pendingStream;
  @override
  String get name => id;
  @override
  String get description => '';
  @override
  Set<SourceFeature> get features => const {};
  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async {
    if (streamError != null) throw streamError!;
    if (pendingStream != null) return pendingStream!.future;
    return const StreamInfo(url: 'https://example.com/audio.mp3');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppSettings settings;
  late SourceManager sources;
  late _Engine engine;
  late PlayerController player;
  const first = Song(id: '1', sourceId: 'a', name: 'first');
  const second = Song(id: '2', sourceId: 'a', name: 'second');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings();
    await settings.init();
    settings.crossfade = false;
    sources = SourceManager([_Source('a'), _Source('b'), _Source('c')]);
    await sources.init();
    engine = _Engine();
    player = PlayerController(sources, settings, engine: engine);
    await player.init();
  });

  tearDown(() {
    player.dispose();
    sources.dispose();
    settings.dispose();
  });

  test('播放引擎打开失败后结束加载并发出提示', () async {
    engine.failOpen = true;
    final notice = player.notices.first;
    await player.playSongs([first]);
    expect(player.loading, isFalse);
    expect(player.buffering, isFalse);
    expect((await notice).message, contains('open failed'));
  });

  test('取地址期间暂停后，迟到的地址不能自动开始播放', () async {
    final source = sources.byId('a') as _Source;
    source.pendingStream = Completer<StreamInfo>();
    final loading = player.playSongs([first]);
    await Future<void>.delayed(Duration.zero);
    await player.pause();
    source.pendingStream!.complete(const StreamInfo(url: 'https://example.com/audio.mp3'));
    await loading;
    expect(engine.playCalls, 0);
    expect(player.loading, isFalse);
  });

  test('旧歌曲失败的停止操作结束后不再弹出过期失败提示', () async {
    final source = sources.byId('a') as _Source;
    source.streamError = Exception('旧歌曲失败');
    engine.delayStop = true;
    final notices = <PlayerNotice>[];
    final subscription = player.notices.listen(notices.add);
    addTearDown(subscription.cancel);
    final oldLoading = player.playSongs([first]);
    await Future<void>.delayed(Duration.zero);
    source.streamError = null;
    await player.playSongs([second]);
    engine.stops.single.complete();
    await oldLoading;
    await Future<void>.delayed(Duration.zero);
    expect(player.current, second);
    expect(notices, isEmpty);
  });

  test('平台要求验证时保留官方验证入口，停止播放但不连续跳歌', () async {
    final url = Uri.parse('https://h5.kugou.com/apps/verify-h5/dist/#/index/test');
    (sources.byId('a') as _Source).streamError = SourceVerificationRequired(message: '酷狗要求验证', url: url);
    final notice = player.notices.first;
    await player.playSongs([first, second]);
    final result = await notice;
    expect(result.blocking, isTrue);
    expect(result.actionUrl, url);
    expect(player.current, first);
    expect(player.loading, isFalse);
    expect(player.buffering, isFalse);
  });

  test('切歌更新持久化索引，切到空平台后下一首仍正常', () async {
    await player.playSongs([first, second]);
    await player.next();
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('player.queue.a.index'), 1);
    await sources.select('b');
    await Future<void>.delayed(Duration.zero);
    expect(player.current, isNull);
    expect(player.upNext, isEmpty);
    await player.next();
  });

  test('快速切换平台时旧异步停止不会覆盖新平台队列', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player.queue.b', '[{"id":"b1","sourceId":"b","name":"B"}]');
    await prefs.setString('player.queue.c', '[{"id":"c1","sourceId":"c","name":"C"}]');
    engine.delayStop = true;
    await sources.select('b');
    await sources.select('c');
    engine.stops[1].complete();
    await Future<void>.delayed(Duration.zero);
    engine.stops[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(player.current?.sourceId, 'c');
    expect(prefs.getString('player.queue.b'), contains('b1'));
  });

  test('拖动进度限制在合法范围，未知播放源明确报错', () async {
    player.duration = const Duration(seconds: 10);
    await player.seek(const Duration(seconds: -2));
    expect(player.position.value, Duration.zero);
    await player.seekFraction(2);
    expect(player.position.value, const Duration(seconds: 10));
    await player.seekFraction(double.nan);
    expect(() => sources.byId('missing'), throwsStateError);
  });

  test('播放模式持久化，销毁后不会响应设置与播放源通知', () async {
    player.setMode(PlayMode.repeatOne);
    await Future<void>.delayed(Duration.zero);
    expect((await SharedPreferences.getInstance()).getString('player.mode'), 'repeatOne');
    final disposed = PlayerController(sources, settings, engine: _Engine());
    await disposed.init();
    expect(disposed.mode, PlayMode.repeatOne);
    disposed.dispose();
    settings.notifyListeners();
    await sources.select('b');
    await Future<void>.delayed(Duration.zero);
  });
}
