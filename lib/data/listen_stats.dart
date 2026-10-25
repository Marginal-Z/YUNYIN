import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../player/player_controller.dart';
import 'models.dart';

/// 单首歌的累计收听。
class SongListen {
  SongListen(this.song, {this.ms = 0, this.plays = 0});

  final Song song;
  int ms;
  int plays;

  Duration get time => Duration(milliseconds: ms);

  Map<String, dynamic> toJson() => {'song': song.toJson(), 'ms': ms, 'plays': plays};

  factory SongListen.fromJson(Map<String, dynamic> j) =>
      SongListen(Song.fromJson(Map<String, dynamic>.from(j['song'] as Map)), ms: (j['ms'] as num).toInt(), plays: (j['plays'] as num?)?.toInt() ?? 0);
}

/// 听歌时长统计：按实际播放进度累计（拖动进度条、暂停、缓冲都不计入），
/// 按天与按歌曲汇总，保存在应用数据目录。
class ListenStats extends ChangeNotifier {
  /// 'yyyy-MM-dd' → 毫秒。
  final Map<String, int> _days = {};
  final Map<String, SongListen> _songs = {};

  PlayerController? _player;
  String? _songKey;
  Duration _last = Duration.zero;

  /// 本次播放已累计的毫秒数，用于判断是否算作一次完整收听。
  int _session = 0;
  bool _counted = false;
  bool _dirty = false;
  Timer? _saveTimer;

  /// 一首歌连续收听达到该时长计为一次播放。
  static const playThreshold = Duration(seconds: 30);

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/stats/listen.json');

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      (j['days'] as Map? ?? const {}).forEach((k, v) => _days['$k'] = (v as num).toInt());
      for (final s in (j['songs'] as List? ?? const [])) {
        final e = SongListen.fromJson(Map<String, dynamic>.from(s as Map));
        _songs[_key(e.song)] = e;
      }
    } catch (e) {
      debugPrint('listen stats: $e');
    }
  }

  AppLifecycleListener? _lifecycle;

  void attach(PlayerController player) {
    _player = player;
    player.position.addListener(_onPosition);
    // 切到后台或窗口隐藏时立即保存。
    _lifecycle = AppLifecycleListener(onPause: flush, onHide: flush, onDetach: flush);
  }

  /// 测试用：直接记录一段收听。
  @visibleForTesting
  void record(Song song, Duration time) => _add(song, time.inMilliseconds);

  String _key(Song s) => '${s.sourceId}:${s.id}';

  void _onPosition() {
    final player = _player!;
    final song = player.current;
    final pos = player.position.value;
    if (song == null) return;
    final key = _key(song);
    if (key != _songKey) {
      _songKey = key;
      _last = pos;
      _session = 0;
      _counted = false;
      return;
    }
    final delta = pos - _last;
    _last = pos;
    // 只累计正常播放产生的小幅前进；拖动进度、切歌回到开头都不计入。
    if (!player.playing || delta <= Duration.zero || delta > const Duration(seconds: 3)) return;
    _add(song, delta.inMilliseconds);
  }

  void _add(Song song, int ms) {
    final day = dayKey(DateTime.now());
    _days[day] = (_days[day] ?? 0) + ms;
    final e = _songs.putIfAbsent(_key(song), () => SongListen(song));
    e.ms += ms;
    _session += ms;
    if (!_counted && _session >= playThreshold.inMilliseconds) {
      _counted = true;
      e.plays++;
    }
    _dirty = true;
    _saveTimer ??= Timer(const Duration(seconds: 20), _save);
    notifyListeners();
  }

  Future<void> _save() async {
    _saveTimer = null;
    if (!_dirty || kIsWeb) return;
    _dirty = false;
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'days': _days, 'songs': [for (final e in _songs.values) e.toJson()]}));
    } catch (e) {
      debugPrint('save listen stats: $e');
    }
  }

  /// 立即写盘（退出前）。
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _save();
  }

  Duration day(DateTime d) => Duration(milliseconds: _days[dayKey(d)] ?? 0);

  Duration get today => day(DateTime.now());

  /// 本周（周一起）。
  Duration get thisWeek {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    var total = Duration.zero;
    for (var i = 0; i < 7; i++) {
      total += day(monday.add(Duration(days: i)));
    }
    return total;
  }

  Duration get total => Duration(milliseconds: _days.values.fold(0, (a, b) => a + b));

  /// 有收听记录的天数。
  int get activeDays => _days.values.where((v) => v > 0).length;

  /// 最近 [n] 天（含今天，从早到晚）。
  List<(DateTime, Duration)> lastDays(int n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      for (var i = n - 1; i >= 0; i--) (today.subtract(Duration(days: i)), day(today.subtract(Duration(days: i)))),
    ];
  }

  List<SongListen> topSongs(int n) => (_songs.values.toList()..sort((a, b) => b.ms.compareTo(a.ms))).take(n).toList();

  /// 按歌手汇总（多位歌手时平均分配）。
  List<(String, Duration, String?)> topArtists(int n) {
    final ms = <String, double>{};
    final cover = <String, String?>{};
    for (final e in _songs.values) {
      final artists = e.song.artists.isEmpty ? const [ArtistRef('', '未知歌手')] : e.song.artists;
      for (final a in artists) {
        ms[a.name] = (ms[a.name] ?? 0) + e.ms / artists.length;
        cover[a.name] ??= e.song.coverUrl;
      }
    }
    final list = ms.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in list.take(n)) (e.key, Duration(milliseconds: e.value.round()), cover[e.key])];
  }

  bool get isEmpty => _days.isEmpty;

  @override
  void dispose() {
    _player?.position.removeListener(_onPosition);
    _lifecycle?.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// “2 小时 13 分”“45 分钟”“不到 1 分钟”。
String formatListen(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h > 0) return m > 0 ? '$h 小时 $m 分' : '$h 小时';
  if (d.inMinutes > 0) return '${d.inMinutes} 分钟';
  return d == Duration.zero ? '0 分钟' : '不到 1 分钟';
}
