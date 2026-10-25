import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';

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
  AlbumRoute(this.id, {this.preview});

  final String id;
  final AlbumInfo? preview;
}

class RadioRoute extends AppRoute {
  RadioRoute(this.radio);

  final RadioInfo radio;
}

class ArtistRoute extends AppRoute {
  ArtistRoute(this.id, {this.name});

  final String id;
  final String? name;
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
  SearchResultRoute(this.keyword, {this.type = SearchType.all});

  final String keyword;
  final SearchType type;

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
