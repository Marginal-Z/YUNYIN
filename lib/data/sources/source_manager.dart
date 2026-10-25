import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_source.dart';
import 'netease/netease_source.dart';

/// 已注册的播放源。新增平台：实现 [MusicSource] 并加入 [SourceRegistry.create]。
abstract final class SourceRegistry {
  static List<MusicSource> create() => [NeteaseSource()];
}

/// 管理当前播放源，并负责按 [Song.sourceId] 找回对应的源。
class SourceManager extends ChangeNotifier {
  SourceManager(this.sources);

  static const _prefsKey = 'source.current';

  final List<MusicSource> sources;
  late MusicSource _current = sources.first;

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
    _current = sources.firstWhere((s) => s.id == saved, orElse: () => sources.first);
  }

  void _onSourceChanged() {
    generation++;
    notifyListeners();
  }

  MusicSource byId(String id) => sources.firstWhere((s) => s.id == id, orElse: () => _current);

  Future<void> select(String id) async {
    if (id == _current.id) return;
    _current = byId(id);
    generation++;
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
