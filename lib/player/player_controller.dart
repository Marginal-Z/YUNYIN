import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/settings.dart';
import '../data/models.dart';
import '../data/sources/music_source.dart';
import '../data/sources/source_manager.dart';

enum PlayMode { sequence, shuffle, repeatOne }

/// 播放器提示（由界面以轻提示 / 弹窗展示）。
class PlayerNotice {
  const PlayerNotice(this.title, {this.message, this.blocking = false});

  final String title;
  final String? message;

  /// 需要用户确认的提示（例如“暂无播放版权”）。
  final bool blocking;
}

/// 播放队列与播放状态。音频由 media_kit（libmpv / HTML5 audio）驱动。
class PlayerController extends ChangeNotifier {
  PlayerController(this.sources, this.settings);

  final SourceManager sources;
  final AppSettings settings;

  Player? _player;
  final List<StreamSubscription<Object?>> _subs = [];

  List<Song> _queue = [];
  int _index = -1;
  List<int> _order = [];
  PlayMode mode = PlayMode.sequence;
  bool playing = false;
  bool buffering = false;
  String? queueTitle;

  /// 播放进度单独通知，避免整页重建。
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  Duration duration = Duration.zero;

  Lyrics lyrics = Lyrics.empty;
  final Set<String> _liked = {};
  final List<Song> history = [];

  final StreamController<PlayerNotice> _notices = StreamController.broadcast();
  Stream<PlayerNotice> get notices => _notices.stream;

  /// 查找已下载的本地副本（由下载管理器提供）。
  Song? Function(Song song)? localLookup;

  Timer? _simTimer;
  bool _simulated = false;
  Timer? _sleepTimer;
  DateTime? sleepAt;
  int _loadToken = 0;
  double _fade = 1;

  List<Song> get queue => List.unmodifiable(_queue);
  int get index => _index;
  Song? get current => _index >= 0 && _index < _queue.length ? _queue[_index] : null;
  double get volume => settings.volume;

  /// 接下来要播放的歌曲（不含当前）。
  List<Song> get upNext {
    if (_index < 0) return const [];
    final pos = _order.indexOf(_index);
    return [for (final i in _order.skip(pos + 1)) _queue[i]];
  }

  bool isLiked(Song s) => _liked.contains(s.key);

  /// 播放引擎初始化失败的原因（例如 Linux 上缺少 libmpv）。为 null 表示正常。
  String? engineError;

  Future<void> init() async {
    try {
      await _initEngine();
    } catch (e) {
      engineError = e.toString();
      debugPrint('player engine unavailable: $e');
    }
    settings.addListener(_applyNormalize);
    sources.addListener(_refreshLikes);
    await _restore();
    _refreshLikes();
  }

  /// Linux 发行包会把 libmpv 及其依赖放在可执行文件旁的 lib 目录中，优先使用它。
  static String? bundledLibmpv() {
    if (kIsWeb || !Platform.isLinux) return null;
    final dir = File(Platform.resolvedExecutable).parent.path;
    for (final name in ['libmpv.so.2', 'libmpv.so.1', 'libmpv.so']) {
      final f = File('$dir/lib/$name');
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  Future<void> _initEngine() async {
    if (!kIsWeb) MediaKit.ensureInitialized(libmpv: bundledLibmpv());
    final p = Player(configuration: const PlayerConfiguration(title: '云音', logLevel: MPVLogLevel.error));
    _player = p;
    _subs.addAll([
      p.stream.playing.listen((v) {
        if (_simulated) return;
        playing = v;
        notifyListeners();
      }),
      p.stream.position.listen((v) {
        // 界面上的进度每 250ms 刷新一次即可，避免每帧重绘（玻璃模糊开销很大）。
        if (_simulated) return;
        if ((v - position.value).abs() >= const Duration(milliseconds: 250) || v < position.value) position.value = v;
      }),
      p.stream.duration.listen((v) {
        if (_simulated || v == Duration.zero) return;
        duration = v;
        notifyListeners();
      }),
      p.stream.buffering.listen((v) {
        buffering = v;
        notifyListeners();
      }),
      p.stream.completed.listen((done) {
        if (done && !_simulated) _onCompleted();
      }),
      p.stream.error.listen((e) {
        if (current != null && e.isNotEmpty) debugPrint('player error: $e');
      }),
    ]);
    await p.setVolume(settings.volume * 100);
    _applyNormalize();
  }

  PlayerNotice get _engineNotice => PlayerNotice(
        '缺少播放组件',
        message: !kIsWeb && Platform.isLinux
            ? '没有找到 libmpv。请在终端运行 sudo apt install libmpv2 后重新打开云音。'
            : '播放引擎初始化失败：$engineError',
        blocking: true,
      );

  bool? _normalizeApplied;
  void _applyNormalize() {
    if (kIsWeb || _player == null || _normalizeApplied == settings.normalize) return;
    _normalizeApplied = settings.normalize;
    try {
      (_player!.platform as dynamic)
          .setProperty('af', settings.normalize ? 'lavfi=[loudnorm=I=-16:TP=-1.5:LRA=11]' : '');
    } catch (_) {}
  }

  Future<void> _refreshLikes() async {
    final ids = <String>{};
    for (final s in sources.sources) {
      try {
        for (final id in await s.likedSongIds()) {
          ids.add('${s.id}:$id');
        }
      } catch (_) {}
    }
    _liked
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  // ── 队列 ──────────────────────────────────────────

  void _rebuildOrder({bool keepCurrentFirst = true}) {
    final n = _queue.length;
    _order = List.generate(n, (i) => i);
    if (mode == PlayMode.shuffle && n > 1) {
      _order.shuffle(math.Random());
      if (keepCurrentFirst && _index >= 0) {
        _order.remove(_index);
        _order.insert(0, _index);
      }
    }
  }

  Future<void> playSongs(List<Song> songs, {int start = 0, bool shuffle = false, String? title}) async {
    if (songs.isEmpty) return;
    _queue = List.of(songs);
    queueTitle = title;
    if (shuffle) {
      mode = PlayMode.shuffle;
      start = math.Random().nextInt(songs.length);
    }
    _index = start.clamp(0, songs.length - 1);
    _rebuildOrder();
    _saveQueue();
    await _load(autoplay: true);
  }

  /// 插到当前歌曲之后并立即播放。
  Future<void> playSong(Song song, {List<Song>? context, String? title}) async {
    if (context != null) {
      final i = context.indexOf(song);
      return playSongs(context, start: i < 0 ? 0 : i, title: title);
    }
    final existing = _queue.indexOf(song);
    if (existing >= 0) {
      _index = existing;
    } else {
      _queue.insert(_index + 1, song);
      _index = _index + 1;
      _rebuildOrder();
    }
    _saveQueue();
    await _load(autoplay: true);
  }

  void playNext(Song song) {
    if (current == null) {
      playSongs([song]);
      return;
    }
    final existing = _queue.indexOf(song);
    if (existing == _index) return;
    if (existing >= 0) {
      _queue.removeAt(existing);
      if (existing < _index) _index--;
    }
    _queue.insert(_index + 1, song);
    _rebuildOrder();
    if (mode == PlayMode.shuffle) {
      _order.remove(_index + 1);
      _order.insert(_order.indexOf(_index) + 1, _index + 1);
    }
    _saveQueue();
    notifyListeners();
  }

  void addToQueue(List<Song> songs) {
    if (current == null) {
      playSongs(songs);
      return;
    }
    for (final s in songs) {
      if (!_queue.contains(s)) _queue.add(s);
    }
    _rebuildOrder();
    _saveQueue();
    notifyListeners();
  }

  void removeSong(Song song) {
    final i = _queue.indexOf(song);
    if (i < 0 || i == _index) return;
    _queue.removeAt(i);
    if (i < _index) _index--;
    _rebuildOrder();
    _saveQueue();
    notifyListeners();
  }

  /// 在“接下来播放”列表中拖动排序。
  void moveUpNext(int from, int to) {
    final upcoming = upNext;
    if (from < 0 || from >= upcoming.length) return;
    final song = upcoming.removeAt(from);
    upcoming.insert(to.clamp(0, upcoming.length), song);
    final cur = current!;
    final before = [for (final i in _order.take(_order.indexOf(_index))) _queue[i]];
    _queue = [...before, cur, ...upcoming];
    _index = before.length;
    _order = List.generate(_queue.length, (i) => i);
    _saveQueue();
    notifyListeners();
  }

  /// 清空队列（保留当前播放）。
  void clearUpcoming() {
    final cur = current;
    if (cur == null) return;
    _queue = [cur];
    _index = 0;
    _rebuildOrder();
    _saveQueue();
    notifyListeners();
  }

  void setMode(PlayMode m) {
    if (mode == m) return;
    mode = m;
    _rebuildOrder();
    notifyListeners();
  }

  void cycleMode() => setMode(PlayMode.values[(mode.index + 1) % PlayMode.values.length]);

  // ── 控制 ──────────────────────────────────────────

  Future<void> toggle() => playing ? pause() : play();

  Future<void> play() async {
    if (current == null) return;
    if (_simulated) {
      playing = true;
      _startSim();
      notifyListeners();
      return;
    }
    if (_player?.state.playlist.medias.isEmpty ?? true) {
      await _load(autoplay: true, keepPosition: true);
      return;
    }
    if (settings.crossfade) {
      await _setFade(0);
      await _player?.play();
      await _rampFade(1, 380);
    } else {
      await _player?.play();
    }
  }

  Future<void> pause() async {
    if (_simulated) {
      playing = false;
      _simTimer?.cancel();
      notifyListeners();
      return;
    }
    if (settings.crossfade && playing) {
      await _rampFade(0, 320);
      await _player?.pause();
      await _setFade(1);
    } else {
      await _player?.pause();
    }
  }

  Future<void> next({bool auto = false}) async {
    if (_queue.isEmpty) return;
    final pos = _order.indexOf(_index);
    if (pos + 1 >= _order.length) {
      if (auto && mode == PlayMode.sequence) {
        // 列表循环。
      }
      _index = _order.first;
    } else {
      _index = _order[pos + 1];
    }
    await _load(autoplay: true);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (position.value > const Duration(seconds: 4)) {
      await seek(Duration.zero);
      return;
    }
    final pos = _order.indexOf(_index);
    _index = pos <= 0 ? _order.last : _order[pos - 1];
    await _load(autoplay: true);
  }

  Future<void> jumpTo(Song song) async {
    final i = _queue.indexOf(song);
    if (i < 0) return;
    _index = i;
    await _load(autoplay: true);
  }

  Future<void> seek(Duration d) async {
    if (_simulated) {
      position.value = d;
      return;
    }
    position.value = d;
    await _player?.seek(d);
  }

  Future<void> seekFraction(double f) {
    final total = duration.inMilliseconds;
    return seek(Duration(milliseconds: (total * f).round()));
  }

  Future<void> setVolume(double v) async {
    settings.setVolume(v.clamp(0, 1));
    await _player?.setVolume(settings.volume * 100 * _fade);
    notifyListeners();
  }

  Future<void> _setFade(double f) async {
    _fade = f;
    await _player?.setVolume(settings.volume * 100 * f);
  }

  Future<void> _rampFade(double to, int ms) async {
    const steps = 12;
    final from = _fade;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(Duration(milliseconds: ms ~/ steps));
      await _setFade(from + (to - from) * i / steps);
    }
  }

  void _onCompleted() {
    if (mode == PlayMode.repeatOne) {
      seek(Duration.zero).then((_) => _player?.play());
    } else {
      next(auto: true);
    }
  }

  void _startSim() {
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!playing) return;
      final p = position.value + const Duration(milliseconds: 250);
      if (p >= duration && duration > Duration.zero) {
        _simTimer?.cancel();
        mode == PlayMode.repeatOne ? seek(Duration.zero).then((_) => _startSim()) : next(auto: true);
        return;
      }
      position.value = p;
    });
  }

  Future<void> _load({required bool autoplay, bool keepPosition = false}) async {
    final song = current;
    if (song == null) return;
    final token = ++_loadToken;
    _simTimer?.cancel();
    final resume = keepPosition ? position.value : Duration.zero;
    if (!keepPosition) position.value = Duration.zero;
    duration = song.duration;
    lyrics = Lyrics.empty;
    buffering = true;
    _addHistory(song);
    notifyListeners();

    final source = sources.byId(song.sourceId);
    _loadLyrics(source, song, token);

    StreamInfo info;
    try {
      final local = song.localPath ?? localLookup?.call(song)?.localPath;
      if (local != null) {
        info = StreamInfo(url: local);
      } else {
        info = await source.stream(song, settings.quality);
      }
    } catch (e) {
      if (token != _loadToken) return;
      buffering = false;
      notifyListeners();
      _notices.add(PlayerNotice('播放失败', message: e.toString()));
      return;
    }
    if (token != _loadToken) return;

    if (info.simulated) {
      _simulated = true;
      await _player?.stop();
      buffering = false;
      playing = autoplay;
      position.value = resume;
      if (autoplay) _startSim();
      notifyListeners();
      return;
    }
    _simulated = false;
    if (_player == null) {
      buffering = false;
      notifyListeners();
      _notices.add(_engineNotice);
      return;
    }
    if (info.url == null) {
      buffering = false;
      notifyListeners();
      _notices.add(const PlayerNotice('暂无播放版权', message: '该歌曲暂时无法播放，已为你切到下一首。', blocking: true));
      if (_queue.length > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (token == _loadToken) await next(auto: true);
      }
      return;
    }
    if (info.trial) _notices.add(const PlayerNotice('当前为试听片段'));
    final p = _player!;
    if (settings.crossfade && playing) await _rampFade(0, 260);
    await p.open(Media(info.url!, httpHeaders: info.headers), play: false);
    if (resume > Duration.zero) await p.seek(resume);
    if (autoplay) {
      if (settings.crossfade) {
        await _setFade(0);
        await p.play();
        await _rampFade(1, 420);
      } else {
        await _setFade(1);
        await p.play();
      }
    }
  }

  Future<void> _loadLyrics(MusicSource source, Song song, int token) async {
    try {
      final l = await source.lyrics(song);
      if (token != _loadToken) return;
      lyrics = l;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleLike(Song song) async {
    final liked = isLiked(song);
    final src = sources.byId(song.sourceId);
    try {
      await src.likeSong(song, !liked);
      liked ? _liked.remove(song.key) : _liked.add(song.key);
      notifyListeners();
      _notices.add(PlayerNotice(liked ? '已取消喜欢' : '已添加到「我喜欢的音乐」'));
    } catch (e) {
      _notices.add(PlayerNotice(e.toString()));
    }
  }

  // ── 睡眠定时 ──────────────────────────────────────

  void setSleepTimer(Duration? d) {
    _sleepTimer?.cancel();
    sleepAt = d == null ? null : DateTime.now().add(d);
    if (d != null) {
      _sleepTimer = Timer(d, () {
        pause();
        sleepAt = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  // ── 持久化 ────────────────────────────────────────

  void _addHistory(Song s) {
    history.remove(s);
    history.insert(0, s);
    if (history.length > 200) history.removeLast();
    SharedPreferences.getInstance().then((p) => p.setString(
          'player.history',
          jsonEncode([for (final h in history.take(200)) h.toJson()]),
        ));
  }

  void _saveQueue() {
    SharedPreferences.getInstance().then((p) {
      p.setString('player.queue', jsonEncode([for (final s in _queue) s.toJson()]));
      p.setInt('player.index', _index);
      p.setString('player.title', queueTitle ?? '');
    });
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    try {
      final h = p.getString('player.history');
      if (h != null) {
        history.addAll([for (final j in jsonDecode(h) as List) Song.fromJson(Map<String, dynamic>.from(j as Map))]);
      }
      final q = p.getString('player.queue');
      if (q != null) {
        _queue = [for (final j in jsonDecode(q) as List) Song.fromJson(Map<String, dynamic>.from(j as Map))];
        _index = (p.getInt('player.index') ?? 0).clamp(-1, _queue.length - 1);
        queueTitle = p.getString('player.title');
        if (queueTitle?.isEmpty ?? false) queueTitle = null;
        _rebuildOrder();
        if (current != null) {
          duration = current!.duration;
          final source = sources.byId(current!.sourceId);
          _loadLyrics(source, current!, _loadToken);
          _simulated = source.id == 'demo';
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    settings.removeListener(_applyNormalize);
    sources.removeListener(_refreshLikes);
    _simTimer?.cancel();
    _sleepTimer?.cancel();
    _player?.dispose();
    _notices.close();
    super.dispose();
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
