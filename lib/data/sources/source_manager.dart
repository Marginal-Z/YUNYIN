import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo/demo_source.dart';
import 'music_source.dart';
import 'netease/netease_source.dart';

/// 已注册的播放源。新增平台：实现 [MusicSource] 并加入 [SourceRegistry.create]。
abstract final class SourceRegistry {
  static List<MusicSource> create() => [
        NeteaseSource(),
        DemoSource(),
      ];
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

  Future<void> init({String? fallbackId}) async {
    for (final s in sources) {
      await s.init();
      s.addListener(_onSourceChanged);
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey) ?? fallbackId;
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

/// 网易云的 Web 接口不允许浏览器跨域访问，Web 预览版默认使用演示源。
String? defaultSourceFor({required bool isWeb}) => isWeb ? DemoSource.sourceId : NeteaseSource.sourceId;
