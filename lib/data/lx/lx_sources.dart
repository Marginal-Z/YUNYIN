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
  const LxScript({required this.id, required this.name, this.description = '', this.version = '', this.author = '', this.url});

  final String id;
  final String name;
  final String description;
  final String version;
  final String author;

  /// 从链接导入时的地址（用于显示与更新）。
  final String? url;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'description': description, 'version': version, 'author': author, 'url': url};

  factory LxScript.fromJson(Map<String, dynamic> j) => LxScript(
    id: '${j['id']}',
    name: '${j['name']}',
    description: '${j['description'] ?? ''}',
    version: '${j['version'] ?? ''}',
    author: '${j['author'] ?? ''}',
    url: j['url'] as String?,
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

/// 洛雪自定义音源：导入、启用与取播放地址。
///
/// 网易云 / QQ 音乐 / 酷狗分别对应洛雪的 wy / tx / kg。当前平台自己取不到完整播放地址时，
/// 用启用的音源脚本按同一平台的歌曲 id 获取地址（仍是该平台的同一首歌，不会换成其他平台的版本）。
class LxSources extends ChangeNotifier {
  static const _prefsKey = 'lx.scripts';
  static const _prefsActive = 'lx.active';

  final List<LxScript> _scripts = [];
  String? _active;
  LxRuntime? _rt;
  String? _rtId;
  Future<LxRuntime>? _starting;

  /// 启用中的脚本声明支持的平台与音质（启动后可用）。
  Map<String, List<String>> get platforms => _rt?.sources ?? const {};
  String? lastError;

  List<LxScript> get scripts => List.unmodifiable(_scripts);
  LxScript? get active => _scripts.where((s) => s.id == _active).firstOrNull;

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
      _active = prefs.getString(_prefsActive);
    } catch (e) {
      debugPrint('lx sources: $e');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode([for (final s in _scripts) s.toJson()]));
    if (_active == null) {
      await prefs.remove(_prefsActive);
    } else {
      await prefs.setString(_prefsActive, _active!);
    }
  }

  /// 从链接下载音源脚本并导入。
  Future<LxScript> importUrl(String url) async {
    final res = await Dio().get<String>(
      url.trim(),
      options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 20)),
    );
    return importText(res.data ?? '', url: url.trim());
  }

  /// 导入脚本内容：先在运行环境中试运行，能完成初始化才保存并启用。
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
    _rt?.dispose();
    _rt = rt;
    _rtId = id;
    _active = id;
    lastError = null;
    await _save();
    notifyListeners();
    return s;
  }

  Future<void> setActive(String? id) async {
    if (id == _active) return;
    _active = id;
    _rt?.dispose();
    _rt = null;
    _rtId = null;
    lastError = null;
    await _save();
    notifyListeners();
    if (id != null) unawaited(_runtime().then((_) => notifyListeners(), onError: (_) => notifyListeners()));
  }

  Future<void> remove(String id) async {
    _scripts.removeWhere((s) => s.id == id);
    if (_active == id) await setActive(null);
    try {
      await File('${(await _dir()).path}/$id.js').delete();
    } catch (_) {}
    await _save();
    notifyListeners();
  }

  Future<LxRuntime> _runtime() {
    final s = active;
    if (s == null) return Future.error(Exception('没有启用的洛雪音源'));
    if (_rt != null && _rtId == s.id) return Future.value(_rt!);
    return _starting ??= () async {
      try {
        final code = await File('${(await _dir()).path}/${s.id}.js').readAsString();
        final rt = await LxRuntime.start(code, info: {'name': s.name, 'description': s.description, 'version': s.version, 'author': s.author});
        _rt = rt;
        _rtId = s.id;
        lastError = null;
        return rt;
      } catch (e) {
        lastError = '$e';
        rethrow;
      } finally {
        _starting = null;
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

  /// 当前平台取不到完整地址时调用：用启用的音源脚本获取 [song] 的播放地址。不支持该平台时返回 null。
  Future<StreamInfo?> resolve(Song song, AudioQuality quality) async {
    final key = platformKeys[song.sourceId];
    if (key == null || active == null) return null;
    final rt = await _runtime();
    final declared = rt.sources[key];
    if (declared == null) return null;
    final start = _qualities.indexOf(_wanted(quality));
    final type = _qualities.skip(start).firstWhere(declared.contains, orElse: () => declared.isEmpty ? '128k' : declared.last);
    final url = await rt.musicUrl(key, type, musicInfo(song, key));
    return StreamInfo(
      url: url,
      quality: switch (type) {
        'flac24bit' => AudioQuality.hires,
        'flac' => AudioQuality.lossless,
        '320k' => AudioQuality.exhigh,
        _ => AudioQuality.standard,
      },
    );
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
