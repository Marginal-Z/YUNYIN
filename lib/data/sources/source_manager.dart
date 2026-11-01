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
import 'qq/qq_source.dart';

/// 已注册的播放源。新增平台：实现 [MusicSource] 并加入 [SourceRegistry.create]。
abstract final class SourceRegistry {
  static List<MusicSource> create(LocalLibrary library, CloudDrives drives, LxSources lx) {
    final netease = NeteaseSource();
    // 四个平台模式彼此独立（网易云、QQ 音乐、酷狗、洛雪曲库）；网盘歌曲没有歌词文件时用网易云的歌词。
    return [netease, QQMusicSource(), KugouSource(), LxLibrarySource(lx), LocalSource(library), CloudSource(drives, fallback: netease)];
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

  Future<void> init() async {
    for (final s in sources) {
      await s.init();
      s.addListener(_onSourceChanged);
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    _current = selectable.firstWhere((s) => s.id == saved, orElse: () => selectable.first);
  }

  void _onSourceChanged() {
    generation++;
    DataCache.clear();
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
    for (final s in sources) {
      s.removeListener(_onSourceChanged);
    }
    super.dispose();
  }
}
