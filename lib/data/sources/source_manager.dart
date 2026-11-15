import 'package:flutter/foundation.dart';

import '../../core/data_cache.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_drives.dart';
import '../local_library.dart';
import 'cloud/cloud_source.dart';
import 'local/local_source.dart';
import 'music_source.dart';
import '../lx/lx_sources.dart';
import 'kugou/kugou_source.dart';
import 'lx/lx_library_source.dart';
import 'netease/netease_source.dart';
import 'qishui/qishui_source.dart';
import 'qq/qq_source.dart';

/// 已注册的播放源。新增平台：实现 [MusicSource] 并加入 [SourceRegistry.create]。
abstract final class SourceRegistry {
  static List<MusicSource> create(LocalLibrary library, CloudDrives drives, LxSources lx) {
    final netease = NeteaseSource();
    // 五个平台模式彼此独立（网易云、QQ 音乐、酷狗、汽水音乐、洛雪曲库）；网盘歌曲没有歌词文件时用网易云的歌词。
    return [netease, QQMusicSource(), KugouSource(), QishuiSource(), LxLibrarySource(lx), LocalSource(library), CloudSource(drives, fallback: netease)];
  }
}

/// 管理当前播放源，并负责按 [Song.sourceId] 找回对应的源。
class SourceManager extends ChangeNotifier {
  SourceManager(this.sources);

  static const _prefsKey = 'source.current';

  final List<MusicSource> sources;
  late MusicSource _current = sources.first;

  /// 可以切换为当前源的播放源。
  List<MusicSource> get selectable => [
    for (final s in sources)
      if (s.selectable) s,
  ];

  MusicSource get current => _current;

  /// 切换播放源时递增，页面据此重新加载。
  int generation = 0;

  /// 四个官方平台各自的账号标识（用户、会员）：只有它变了才需要重新加载页面。
  static const _platforms = {'netease', 'qq', 'kugou', 'qishui'};
  final Map<String, String> _identity = {};

  static String _identityOf(MusicSource s) {
    final u = s.user;
    return u == null ? '' : '${u.id}|${u.vip}';
  }

  Future<void> init() async {
    for (final s in sources) {
      await s.init();
      _identity[s.id] = _identityOf(s);
      s.addListener(() => _onSourceChanged(s));
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    _current = selectable.firstWhere((s) => s.id == saved, orElse: () => selectable.first);
  }

  void _onSourceChanged(MusicSource s) {
    // 官方平台在后台刷新账号（例如启动时网易云重新取一次资料）而账号没有变化时，不清缓存、不重新加载页面：
    // 此前每次都会让首页、搜索、歌单页重新加载，看起来像页面切过来才加载出来。
    final id = _identityOf(s);
    final changed = _identity[s.id] != id;
    _identity[s.id] = id;
    if (changed || !_platforms.contains(s.id)) {
      generation++;
      DataCache.clear();
    }
    notifyListeners();
  }

  MusicSource byId(String id) => sources.firstWhere((s) => s.id == id, orElse: () => throw StateError('播放源不存在：$id'));

  Future<void> select(String id) async {
    if (id == _current.id) return;
    final source = byId(id);
    if (!source.selectable) throw ArgumentError.value(id, 'id', '该播放源不能作为平台模式');
    _current = source;
    generation++;
    DataCache.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
