import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';

/// 页面数据缓存：再次进入页面时先显示上次的数据，后台再刷新（不再每次都显示骨架屏）。
/// 首页数据另外保存到磁盘，冷启动时立即显示。
abstract final class DataCache {
  static const _capacity = 120;
  static final _entries = <String, (Object?, DateTime)>{};

  static (Object?, DateTime)? lookup(String key) {
    final e = _entries.remove(key);
    if (e != null) _entries[key] = e;
    return e;
  }

  static void put(String key, Object? value) {
    _entries.remove(key);
    _entries[key] = (value, DateTime.now());
    while (_entries.length > _capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// 登录、退出或切换播放源后清空，避免显示别的账号的数据。
  static void clear() => _entries.clear();

  static Future<File> _homeFile() async => File('${(await getApplicationSupportDirectory()).path}/cache/home.json');

  /// 读取磁盘上的首页数据放入缓存（标记为过期，显示后立即刷新）。
  static Future<void> restoreHome(String sourceId, String? account) async {
    if (kIsWeb) return;
    try {
      final f = await _homeFile();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (j['source'] != sourceId || j['account'] != account) return;
      _entries[homeKey(sourceId)] = (HomeFeed.fromJson(Map<String, dynamic>.from(j['feed'] as Map)), DateTime.fromMillisecondsSinceEpoch(0));
    } catch (e) {
      debugPrint('restore home: $e');
    }
  }

  static Future<void> saveHome(String sourceId, String? account, HomeFeed feed) async {
    if (kIsWeb) return;
    try {
      final f = await _homeFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'source': sourceId, 'account': account, 'feed': feed.toJson()}));
    } catch (e) {
      debugPrint('save home: $e');
    }
  }

  static String homeKey(String sourceId) => 'home:$sourceId';
}
