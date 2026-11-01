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
  const LxScript({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '',
    this.author = '',
    this.url,
    this.enabled = true,
    this.platforms = const [],
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final String author;

  /// 从链接导入时的地址（用于显示与更新）。
  final String? url;

  /// 洛雪曲库播放时是否使用（可以同时启用多个音源，按列表顺序依次尝试）。
  final bool enabled;

  /// 脚本声明支持的平台代号（kw / kg / tx / wy / mg），启动过一次后记住，用来决定可以浏览哪些曲库。
  final List<String> platforms;

  LxScript copyWith({bool? enabled, List<String>? platforms}) => LxScript(
    id: id,
    name: name,
    description: description,
    version: version,
    author: author,
    url: url,
    enabled: enabled ?? this.enabled,
    platforms: platforms ?? this.platforms,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'author': author,
    'url': url,
    'enabled': enabled,
    'platforms': platforms,
  };

  /// 音源标识会拼进脚本文件名：只接受字母、数字、下划线与连字符，防止“../”之类的路径。
  static bool isSafeId(String id) => RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id);

  factory LxScript.fromJson(Map<String, dynamic> j) => LxScript(
    id: '${j['id']}',
    name: '${j['name']}',
    description: '${j['description'] ?? ''}',
    version: '${j['version'] ?? ''}',
    author: '${j['author'] ?? ''}',
    url: j['url'] as String?,
    enabled: j['enabled'] as bool? ?? true,
    platforms: [for (final p in j['platforms'] as List? ?? const []) '$p'],
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

/// 音源的可用状态（最近一次检测的结果）。
class LxHealth {
  const LxHealth({this.ok, this.checking = false, this.latency, this.message});

  /// null 表示还没有检测过。
  final bool? ok;
  final bool checking;
  final Duration? latency;
  final String? message;
}

/// 洛雪自定义音源：导入、启用、排序与取播放地址。
///
/// 网易云 / QQ 音乐 / 酷狗分别对应洛雪的 wy / tx / kg。当前平台未登录、没有会员或只有试听时，
/// 按列表顺序依次用启用的音源获取同一首歌（同一平台的歌曲 id）的完整地址，第一个成功的音源生效。
class LxSources extends ChangeNotifier {
  static const _prefsKey = 'lx.scripts';
  static const _prefsActive = 'lx.active';
  static const _prefsCatalog = 'lx.catalog';

  final List<LxScript> _scripts = [];
  final Map<String, LxRuntime> _runtimes = {};
  final Map<String, Future<LxRuntime>> _starting = {};
  bool _disposed = false;

  /// 各音源最近一次启动失败的原因。
  final Map<String, String> errors = {};

  /// 各音源最近一次取地址失败的原因（成功后清除），在音源列表中提示，便于发现失效的音源。
  final Map<String, String> lastFailures = {};

  /// 各音源最近一次可用性检测的结果。
  final Map<String, LxHealth> health = {};

  List<LxScript> get scripts => List.unmodifiable(_scripts);
  List<LxScript> get enabled => [
    for (final s in _scripts)
      if (s.enabled) s,
  ];

  /// 已启动的音源声明支持的平台与音质。
  Map<String, List<String>> platformsOf(String id) => _runtimes[id]?.sources ?? const {};

  /// 云音的歌曲来源对应洛雪的平台代号；洛雪曲库（lx）中没有标明平台的歌曲来自酷我（kw）。
  static const platformKeys = {'netease': 'wy', 'qq': 'tx', 'kugou': 'kg', 'lx': 'kw'};
  static const platformNames = {'wy': '网易云', 'tx': 'QQ 音乐', 'kg': '酷狗', 'kw': '酷我', 'mg': '咪咕'};

  /// 洛雪曲库可以浏览的曲库（咪咕没有可用的公开曲库接口）。
  static const catalogs = ['kw', 'kg', 'tx', 'wy'];

  String _catalog = 'kw';

  /// 启用的音源支持的曲库，按 [catalogs] 的顺序。
  List<String> get availableCatalogs => [
    for (final k in catalogs)
      if (enabled.any((s) => s.platforms.contains(k))) k,
  ];

  /// 洛雪曲库当前浏览的曲库：选中的曲库不再被启用的音源支持时，改用第一个支持的曲库。
  String get catalog {
    final available = availableCatalogs;
    return available.isEmpty || available.contains(_catalog) ? _catalog : available.first;
  }

  Future<void> setCatalog(String key) async {
    if (!catalogs.contains(key) || key == _catalog) return;
    _catalog = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCatalog, key);
    if (!_disposed) notifyListeners();
  }

  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/lx');
    await d.create(recursive: true);
    return d;
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 重复调用不会追加重复记录；单条记录损坏或标识不安全时跳过它，不影响后面的有效音源。
      _scripts.clear();
      final saved = jsonDecode(prefs.getString(_prefsKey) ?? '[]');
      for (final j in saved is List ? saved : const []) {
        if (j is! Map) continue;
        try {
          final script = LxScript.fromJson(Map<String, dynamic>.from(j));
          if (LxScript.isSafeId(script.id) && !_scripts.any((s) => s.id == script.id)) _scripts.add(script);
        } catch (e) {
          debugPrint('lx source record: $e');
        }
      }
      _catalog = catalogs.firstWhere((k) => k == prefs.getString(_prefsCatalog), orElse: () => 'kw');
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
    // 旧版本没有记录音源支持的平台：在后台启动一次，得到可以浏览的曲库。
    for (final s in enabled.where((s) => s.platforms.isEmpty)) {
      unawaited(_runtime(s).then((_) {}, onError: (Object _) {}));
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
    if (_disposed) {
      rt.dispose();
      throw StateError('音源已停止');
    }
    if (rt.sources.isEmpty) {
      rt.dispose();
      throw Exception('音源脚本没有声明支持的平台');
    }
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    try {
      await File('${(await _dir()).path}/$id.js').writeAsString(code);
      if (_disposed) throw StateError('音源已停止');
      final s = LxScript(
        id: id,
        name: header['name']!.isEmpty ? '未命名音源' : header['name']!,
        description: header['description']!,
        version: header['version']!,
        author: header['author']!,
        url: url,
        platforms: rt.sources.keys.toList(),
      );
      _scripts.add(s);
      _runtimes[id] = rt;
      errors.remove(id);
      await _save();
      if (_disposed) throw StateError('音源已停止');
      notifyListeners();
      return s;
    } catch (_) {
      _scripts.removeWhere((script) => script.id == id);
      _runtimes.remove(id);
      rt.dispose();
      rethrow;
    }
  }

  Future<void> setEnabled(String id, bool on) async {
    final i = _scripts.indexWhere((s) => s.id == id);
    if (i < 0) return;
    _scripts[i] = _scripts[i].copyWith(enabled: on);
    final script = _scripts[i];
    if (!on) {
      _runtimes.remove(id)?.dispose();
      health.remove(id);
    }
    await _save();
    if (_disposed) return;
    notifyListeners();
    if (on) {
      unawaited(
        _runtime(script).then(
          (_) {
            if (!_disposed) notifyListeners();
          },
          onError: (Object _) {
            if (!_disposed) notifyListeners();
          },
        ),
      );
    }
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
    lastFailures.remove(id);
    health.remove(id);
    if (LxScript.isSafeId(id)) {
      try {
        await File('${(await _dir()).path}/$id.js').delete();
      } catch (_) {}
    }
    await _save();
    notifyListeners();
  }

  Future<LxRuntime> _runtime(LxScript s) {
    if (_disposed) return Future.error(StateError('音源已停止'));
    final rt = _runtimes[s.id];
    if (rt != null) return Future.value(rt);
    return _starting[s.id] ??= () async {
      try {
        final code = await File('${(await _dir()).path}/${s.id}.js').readAsString();
        final rt = await LxRuntime.start(code, info: {'name': s.name, 'description': s.description, 'version': s.version, 'author': s.author});
        if (_disposed || !_scripts.any((script) => script.id == s.id && script.enabled)) {
          rt.dispose();
          throw StateError('音源已停止');
        }
        _runtimes[s.id] = rt;
        errors.remove(s.id);
        // 记住脚本支持的平台（可浏览的曲库随之更新）。
        final i = _scripts.indexWhere((script) => script.id == s.id);
        final platforms = rt.sources.keys.toList();
        if (i >= 0 && !listEquals(_scripts[i].platforms, platforms)) {
          _scripts[i] = _scripts[i].copyWith(platforms: platforms);
          await _save();
          if (!_disposed) notifyListeners();
        }
        return rt;
      } catch (e) {
        if (!_disposed && _scripts.any((script) => script.id == s.id && script.enabled)) errors[s.id] = '$e';
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
  Future<StreamInfo?> resolve(Song song, AudioQuality quality, {String? platform}) async {
    final key = platform ?? platformKeys[song.sourceId];
    if (key == null) return null;
    Object? lastError;
    for (final s in enabled) {
      try {
        final rt = await _runtime(s);
        if (_disposed || !_scripts.any((script) => script.id == s.id && script.enabled)) continue;
        final declared = rt.sources[key];
        if (declared == null) continue;
        final start = _qualities.indexOf(_wanted(quality));
        final type = _qualities.skip(start).firstWhere(declared.contains, orElse: () => declared.isEmpty ? '128k' : declared.last);
        final url = await rt.musicUrl(key, type, musicInfo(song, key), timeout: const Duration(seconds: 15));
        if (_disposed || !_scripts.any((script) => script.id == s.id && script.enabled)) continue;
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
        if (_disposed || !_scripts.any((script) => script.id == s.id && script.enabled)) continue;
        debugPrint('lx ${s.name}: $e');
        lastFailures[s.id] = e.toString().replaceFirst('Exception: ', '');
        notifyListeners();
        lastError = Exception('${s.name}：${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    if (lastError != null) throw lastError;
    return null;
  }

  /// 检测启用的音源当前是否可用：用 [sample]（[platform] 平台的一首歌）取 128k 地址，并确认地址能访问。
  Future<void> check(Song sample, String platform, {Dio? dio}) async {
    final targets = enabled;
    for (final s in targets) {
      health[s.id] = LxHealth(checking: true, ok: health[s.id]?.ok, latency: health[s.id]?.latency, message: health[s.id]?.message);
    }
    if (targets.isNotEmpty) notifyListeners();
    final client = dio ?? Dio();
    await Future.wait([
      for (final s in targets)
        () async {
          final watch = Stopwatch()..start();
          LxHealth result;
          try {
            final rt = await _runtime(s);
            final declared = rt.sources[platform];
            if (declared == null) {
              result = LxHealth(ok: false, message: '不支持${platformNames[platform] ?? platform}');
            } else {
              final type = declared.contains('128k') || declared.isEmpty ? '128k' : declared.last;
              final url = await rt.musicUrl(platform, type, musicInfo(sample, platform), timeout: const Duration(seconds: 10));
              final res = await client.get<List<int>>(
                url,
                options: Options(
                  headers: const {'Range': 'bytes=0-1'},
                  responseType: ResponseType.bytes,
                  receiveTimeout: const Duration(seconds: 6),
                  validateStatus: (_) => true,
                ),
              );
              final status = res.statusCode ?? 0;
              result = status >= 200 && status < 400
                  ? LxHealth(ok: true, latency: watch.elapsed)
                  : LxHealth(ok: false, latency: watch.elapsed, message: '地址无法访问（HTTP $status）');
            }
          } catch (e) {
            result = LxHealth(ok: false, latency: watch.elapsed, message: e.toString().replaceFirst('Exception: ', ''));
          }
          if (_disposed || !_scripts.any((script) => script.id == s.id)) return;
          health[s.id] = result;
          if (result.ok == true) lastFailures.remove(s.id);
          notifyListeners();
        }(),
    ]);
    if (dio == null) client.close();
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

  @override
  void dispose() {
    _disposed = true;
    for (final runtime in _runtimes.values) {
      runtime.dispose();
    }
    _runtimes.clear();
    super.dispose();
  }
}
