import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../settings/about_pages.dart' show AboutPage;

/// 移动端页面周围的悬浮控件：玻璃导航栏、迷你播放条。
enum Chrome {
  /// 导航栏 + 迷你播放条。
  full,

  /// 只有导航栏（设置页）。
  navOnly,

  /// 只有迷你播放条，贴底（搜索结果）。
  miniOnly,

  /// 无（搜索、登录）。
  none,
}

/// 应用内页面。
sealed class AppRoute {
  AppRoute() : uid = _seq++;

  static int _seq = 0;
  final int uid;

  Chrome get chrome => Chrome.full;

  /// 桌面端侧边栏用于高亮的标识。
  String get sideKey => runtimeType.toString();
}

class HomeRoute extends AppRoute {
  @override
  String get sideKey => 'home';
}

class DiscoverRoute extends AppRoute {
  DiscoverRoute({this.tab = 0});

  final int tab;

  @override
  String get sideKey => tab == 2 ? 'radio' : 'discover';
}

class LibraryRoute extends AppRoute {}

class PlaylistRoute extends AppRoute {
  PlaylistRoute(this.id, {this.preview, this.sourceId});

  final String id;
  final PlaylistInfo? preview;
  final String? sourceId;

  @override
  String get sideKey => 'playlist:$id';
}

/// 我喜欢 / 最近播放 / 已下载 / 收藏的歌单 / 本地。
class CollectionRoute extends AppRoute {
  CollectionRoute(this.kind);

  final PlaylistKind kind;

  @override
  String get sideKey => 'collection:${kind.name}';
}

class AlbumRoute extends AppRoute {
  AlbumRoute(this.id, {this.preview, this.sourceId});

  final String id;
  final AlbumInfo? preview;

  /// 专辑所属的平台（从歌曲进入时为歌曲的平台）；为空时使用当前平台。
  final String? sourceId;
}

class RadioRoute extends AppRoute {
  RadioRoute(this.radio);

  final RadioInfo radio;
}

class ArtistRoute extends AppRoute {
  ArtistRoute(this.id, {this.name, this.sourceId});

  final String id;
  final String? name;

  /// 歌手所属的平台（从歌曲进入时为歌曲的平台）；为空时使用当前平台。
  final String? sourceId;
}

/// 我的收藏：歌单 / 专辑 / 歌手（乐库筛选 & 桌面端“专辑与歌手”）。
class MyCollectionsRoute extends AppRoute {
  MyCollectionsRoute({this.tab = 0});

  final int tab;

  @override
  String get sideKey => 'collections';
}

class SearchRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.none;
}

class SearchResultRoute extends AppRoute {
  SearchResultRoute(this.keyword, {this.type = SearchType.all, this.sourceId});

  final String keyword;
  final SearchType type;

  /// 搜索源（网易云 / QQ 音乐 / 酷狗）；为空时使用当前平台。
  final String? sourceId;

  @override
  Chrome get chrome => Chrome.miniOnly;

  @override
  String get sideKey => 'search';
}

class SettingsRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.navOnly;

  @override
  String get sideKey => 'settings';
}

/// 桌宠：挑选与预览桌宠，打开后显示在桌面上。
class PetRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.navOnly;

  @override
  String get sideKey => 'settings';
}

/// 音色中心：云音助手的音色与语音引擎。
class VoiceCenterRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.none;

  @override
  String get sideKey => 'settings';
}

/// 云音助手设置：语音唤醒与大模型接口。
class AssistantSettingsRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.navOnly;

  @override
  String get sideKey => 'settings';
}

/// 问题诊断（关于云音的二级页面）。
class DiagnosticsRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.navOnly;

  @override
  String get sideKey => 'settings';
}

class SettingsMoreRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.navOnly;

  @override
  String get sideKey => 'settings';
}

/// 外观（设置的二级页面）。
class AppearanceRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.navOnly;

  @override
  String get sideKey => 'settings';
}

/// 关于页中的隐私政策、用户协议、权限管理与意见反馈。
class AboutRoute extends AppRoute {
  AboutRoute(this.page);

  final AboutPage page;

  @override
  Chrome get chrome => Chrome.navOnly;

  @override
  String get sideKey => 'settings';
}

/// 听歌统计。
class StatsRoute extends AppRoute {
  @override
  String get sideKey => 'stats';
}

/// 本地歌曲手动匹配歌词与封面。
class LocalMatchRoute extends AppRoute {
  LocalMatchRoute(this.song);

  final Song song;

  @override
  Chrome get chrome => Chrome.none;
}

/// 洛雪音源（设置的二级页面）。
class LxSourcesRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.none;

  @override
  String get sideKey => 'settings';
}

/// 音效（均衡器与音量）。
class AudioEffectsRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.navOnly;

  @override
  String get sideKey => 'settings';
}

/// 桌面歌词与状态栏歌词设置。
class LyricsOverlayRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.navOnly;

  @override
  String get sideKey => 'settings';
}

/// 播放设置（设置的二级页面）。
class PlaybackSettingsRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.navOnly;

  @override
  String get sideKey => 'settings';
}

/// 下载与缓存（设置的二级页面）。
class StorageSettingsRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.navOnly;

  @override
  String get sideKey => 'settings';
}

/// 个人中心。
class ProfileRoute extends AppRoute {
  @override
  String get sideKey => 'profile';
}

/// 网盘列表。
class CloudDrivesRoute extends AppRoute {
  @override
  String get sideKey => 'cloud';
}

/// 添加或编辑网盘（[driveId] 为空时添加）。
class CloudEditRoute extends AppRoute {
  CloudEditRoute([this.driveId]);

  final String? driveId;

  @override
  Chrome get chrome => Chrome.none;

  @override
  String get sideKey => 'cloud';
}

/// 浏览网盘中的文件夹。
class CloudBrowseRoute extends AppRoute {
  CloudBrowseRoute(this.driveId, {this.href = '', this.title});

  final String driveId;
  final String href;
  final String? title;

  @override
  String get sideKey => 'cloud';
}

class LoginRoute extends AppRoute {
  @override
  Chrome get chrome => Chrome.none;
}

/// 页面导航状态：移动端三个标签各自一个栈；桌面端使用单栈 + 前进栈。
class AppNav extends ChangeNotifier {
  int tab = 0;
  final List<List<AppRoute>> stacks = [
    [HomeRoute()],
    [DiscoverRoute()],
    [LibraryRoute()],
  ];
  final List<AppRoute> _forward = [];

  List<AppRoute> get stack => stacks[tab];
  AppRoute get top => stack.last;
  bool get canBack => stack.length > 1;
  bool get canForward => _forward.isNotEmpty;

  void push(AppRoute r) {
    stack.add(r);
    _forward.clear();
    notifyListeners();
  }

  /// 替换栈顶（例如在搜索结果页再次搜索）。
  void replace(AppRoute r) {
    if (stack.length > 1) stack.removeLast();
    stack.add(r);
    notifyListeners();
  }

  bool pop() {
    if (stack.length <= 1) return false;
    _forward.add(stack.removeLast());
    notifyListeners();
    return true;
  }

  void forward() {
    if (_forward.isEmpty) return;
    stack.add(_forward.removeLast());
    notifyListeners();
  }

  /// 切换平台后，各标签里打开的页面属于原来的平台：只保留各标签的首页（当前标签保留正在看的页面，
  /// 例如个人中心）。
  void resetForPlatform() {
    for (var i = 0; i < stacks.length; i++) {
      final s = stacks[i];
      if (s.length <= 1) continue;
      final keep = i == tab ? [s.first, s.last] : [s.first];
      s
        ..clear()
        ..addAll(keep);
    }
    _forward.clear();
    notifyListeners();
  }

  void switchTab(int i) {
    if (i == tab) {
      if (stack.length > 1) {
        stack.removeRange(1, stack.length);
        notifyListeners();
      }
      return;
    }
    tab = i;
    notifyListeners();
  }

  /// 导航器手势返回后同步状态。
  void removed(int tabIndex, AppRoute r) {
    final s = stacks[tabIndex];
    if (s.length > 1 && s.contains(r)) {
      s.remove(r);
      notifyListeners();
    }
  }

  /// 系统返回键。
  void handleBack() {
    if (pop()) return;
    if (tab != 0) {
      switchTab(0);
      return;
    }
    SystemNavigator.pop();
  }
}
