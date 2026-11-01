import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'lx_runtime.dart';

/// 一个导入的洛雪音源脚本。
class LxScript {
  const LxScript({required this.id, required this.name, this.description = '', this.version = '', this.author = '', this.url, this.enabled = true});

  final String id;
  final String name;
  final String description;
  final String version;
  final String author;

  /// 从链接导入时的地址（用于显示与更新）。
  final String? url;

  /// 是否参与兜底（可以同时启用多个音源，按列表顺序依次尝试）。
  final bool enabled;

  LxScript copyWith({bool? enabled}) =>
      LxScript(id: id, name: name, description: description, version: version, author: author, url: url, enabled: enabled ?? this.enabled);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'description': description, 'version': version, 'author': author, 'url': url, 'enabled': enabled};

  factory LxScript.fromJson(Map<String, dynamic> j) => LxScript(
    id: '${j['id']}',
    name: '${j['name']}',
    description: '${j['description'] ?? ''}',
    version: '${j['version'] ?? ''}',
    author: '${j['author'] ?? ''}',
    url: j['url'] as String?,
    enabled: j['enabled'] as bool? ?? true,
  );

  /// 读取脚本开头注释中的 @name、@description、@version、@author。
  static Map<String, String> parseHeader(String code) {
    final head = RegExp(r'/\*[\s\S]*?\*/').firstMatch(code)?.group(0) ?? '';
    String? tag(String t) => RegExp('@$t\\s+([^\\n*]+)').firstMatch(head)?.group(1)?.trim();
    return {
      'name': tag('name') ?? '',
      'description': tag('description') ?? '',
      'version': tag('version') ?? '',
      'author': tag('author') ?? '',
      'homepage': tag('homepage') ?? '',
    };
  }
}

/// 洛雪自定义音源：导入、启用、排序与取播放地址。
///
/// 网易云 / QQ 音乐 / 酷狗分别对应洛雪的 wy / tx / kg。当前平台未登录、没有会员或只有试听时，
/// 按列表顺序依次用启用的音源获取同一首歌（同一平台的歌曲 id）的完整地址，第一个成功的音源生效。
class LxSources extends ChangeNotifier {
  static const _prefsKey = 'lx.scripts';
  static const _prefsActive = 'lx.active';

  final List<LxScript> _scripts = [];
  final Map<String, LxRuntime> _runtimes = {};
  final Map<String, Future<LxRuntime>> _starting = {};

  /// 各音源最近一次启动失败的原因。
  final Map<String, String> errors = {};

  /// 各音源最近一次取地址失败的原因（成功后清除），在音源列表中提示，便于发现失效的音源。
  final Map<String, String> lastFailures = {};

  List<LxScript> get scripts => List.unmodifiable(_scripts);
  List<LxScript> get enabled => [
    for (final s in _scripts)
      if (s.enabled) s,
  ];

  /// 已启动的音源声明支持的平台与音质。
  Map<String, List<String>> platformsOf(String id) => _runtimes[id]?.sources ?? const {};

  static const platformKeys = {'netease': 'wy', 'qq': 'tx', 'kugou': 'kg'};
  static const platformNames = {'wy': '网易云', 'tx': 'QQ 音乐', 'kg': '酷狗', 'kw': '酷我', 'mg': '咪咕'};

  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/lx');
    await d.create(recursive: true);
    return d;
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final j in jsonDecode(prefs.getString(_prefsKey) ?? '[]') as List) {
        _scripts.add(LxScript.fromJson(Map<String, dynamic>.from(j as Map)));
      }
      // 旧版本只能启用一个音源：迁移为只启用当时选中的那个。
      final active = prefs.getString(_prefsActive);
      if (active != null) {
        for (var i = 0; i < _scripts.length; i++) {
          _scripts[i] = _scripts[i].copyWith(enabled: _scripts[i].id == active);
        }
        await prefs.remove(_prefsActive);
        await _save();
      }
    } catch (e) {
      debugPrint('lx sources: $e');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode([for (final s in _scripts) s.toJson()]));
  }

  /// 从链接下载音源脚本并导入。
  Future<LxScript> importUrl(String url) async {
    final res = await Dio().get<String>(
      url.trim(),
      options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 20)),
    );
    return importText(res.data ?? '', url: url.trim());
  }

  /// 导入脚本内容：先在运行环境中试运行，能完成初始化才保存，并加到列表末尾（默认启用）。
  Future<LxScript> importText(String code, {String? url}) async {
    if (!code.contains('lx')) throw Exception('这不是洛雪音源脚本');
    final header = LxScript.parseHeader(code);
    final rt = await LxRuntime.start(code, info: header);
    if (rt.sources.isEmpty) {
      rt.dispose();
      throw Exception('音源脚本没有声明支持的平台');
    }
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await File('${(await _dir()).path}/$id.js').writeAsString(code);
    final s = LxScript(
      id: id,
      name: header['name']!.isEmpty ? '未命名音源' : header['name']!,
      description: header['description']!,
      version: header['version']!,
      author: header['author']!,
      url: url,
    );
    _scripts.add(s);
    _runtimes[id] = rt;
    errors.remove(id);
    await _save();
    notifyListeners();
    return s;
  }

  Future<void> setEnabled(String id, bool on) async {
    final i = _scripts.indexWhere((s) => s.id == id);
    if (i < 0) return;
    _scripts[i] = _scripts[i].copyWith(enabled: on);
    if (!on) _runtimes.remove(id)?.dispose();
    await _save();
    notifyListeners();
    if (on) unawaited(_runtime(_scripts[i]).then((_) => notifyListeners(), onError: (_) => notifyListeners()));
  }

  /// 调整优先级：把音源上移一位（排在前面的先尝试）。
  Future<void> moveUp(String id) async {
    final i = _scripts.indexWhere((s) => s.id == id);
    if (i <= 0) return;
    final s = _scripts.removeAt(i);
    _scripts.insert(i - 1, s);
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _scripts.removeWhere((s) => s.id == id);
    _runtimes.remove(id)?.dispose();
    errors.remove(id);
    try {
      await File('${(await _dir()).path}/$id.js').delete();
    } catch (_) {}
    await _save();
    notifyListeners();
  }

  Future<LxRuntime> _runtime(LxScript s) {
    final rt = _runtimes[s.id];
    if (rt != null) return Future.value(rt);
    return _starting[s.id] ??= () async {
      try {
        final code = await File('${(await _dir()).path}/${s.id}.js').readAsString();
        final rt = await LxRuntime.start(code, info: {'name': s.name, 'description': s.description, 'version': s.version, 'author': s.author});
        _runtimes[s.id] = rt;
        errors.remove(s.id);
        return rt;
      } catch (e) {
        errors[s.id] = '$e';
        rethrow;
      } finally {
        _starting.remove(s.id);
      }
    }();
  }

  /// 洛雪的音质代号，从高到低。
  static const _qualities = ['flac24bit', 'flac', '320k', '128k'];

  static String _wanted(AudioQuality q) => switch (q) {
    AudioQuality.hires => 'flac24bit',
    AudioQuality.lossless => 'flac',
    AudioQuality.exhigh => '320k',
    _ => '128k',
  };

  /// 当前平台取不到完整地址时调用：按顺序用启用的音源获取 [song] 的播放地址，第一个成功的生效。
  /// 没有启用的音源或都不支持该平台时返回 null；都失败时抛出最后一个错误。
  Future<StreamInfo?> resolve(Song song, AudioQuality quality) async {
    final key = platformKeys[song.sourceId];
    if (key == null) return null;
    Object? lastError;
    for (final s in enabled) {
      try {
        final rt = await _runtime(s);
        final declared = rt.sources[key];
        if (declared == null) continue;
        final start = _qualities.indexOf(_wanted(quality));
        final type = _qualities.skip(start).firstWhere(declared.contains, orElse: () => declared.isEmpty ? '128k' : declared.last);
        final url = await rt.musicUrl(key, type, musicInfo(song, key), timeout: const Duration(seconds: 15));
        if (lastFailures.remove(s.id) != null) notifyListeners();
        return StreamInfo(
          url: url,
          quality: switch (type) {
            'flac24bit' => AudioQuality.hires,
            'flac' => AudioQuality.lossless,
            '320k' => AudioQuality.exhigh,
            _ => AudioQuality.standard,
          },
        );
      } catch (e) {
        debugPrint('lx ${s.name}: $e');
        lastFailures[s.id] = e.toString().replaceFirst('Exception: ', '');
        notifyListeners();
        lastError = Exception('${s.name}：${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    if (lastError != null) throw lastError;
    return null;
  }

  /// 洛雪的 musicInfo：同时提供旧版（顶层字段）与新版（meta）格式。
  @visibleForTesting
  static Map<String, dynamic> musicInfo(Song s, String key) {
    final parts = s.id.split(':');
    final d = s.duration;
    final interval = '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    final base = <String, dynamic>{
      'name': s.name,
      'singer': s.artists.map((a) => a.name).join('、'),
      'albumName': s.albumName,
      'interval': interval,
      'img': s.coverUrl,
      'source': key,
    };
    switch (key) {
      case 'tx':
        base.addAll({
          'songmid': parts.first,
          'strMediaMid': parts.length > 1 ? parts[1] : parts.first,
          'albumMid': s.album?.id ?? '',
          'albumId': s.album?.id ?? '',
        });
      case 'kg':
        base.addAll({'hash': parts.first, 'songmid': parts.length > 1 ? parts[1] : '', 'albumId': parts.length > 2 ? parts[2] : ''});
      default:
        base.addAll({'songmid': s.id, 'albumId': s.album?.id ?? ''});
    }
    base['meta'] = {
      'songId': base['songmid'],
      'albumName': s.albumName,
      'picUrl': s.coverUrl,
      if (base['hash'] != null) 'hash': base['hash'],
      if (base['strMediaMid'] != null) 'strMediaMid': base['strMediaMid'],
      if (base['albumId'] != null) 'albumId': base['albumId'],
    };
    return base;
  }
}
