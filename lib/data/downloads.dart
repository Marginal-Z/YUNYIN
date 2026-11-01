import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../core/settings.dart';
import 'models.dart';
import 'sources/source_manager.dart';
import 'sources/source_policy.dart';

/// 下载管理：把歌曲保存到下载目录，并维护一份索引。
class DownloadManager extends ChangeNotifier {
  DownloadManager(this.sources, this.settings);

  final SourceManager sources;
  final AppSettings settings;
  final Dio _dio = Dio();

  final List<Song> _items = [];
  final Map<String, double> progress = {};
  final Map<String, Future<bool>> _pending = {};
  Future<void> _saving = Future.value();
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  List<Song> get items => List.unmodifiable(_items);
  bool get supported => !kIsWeb;

  bool isDownloaded(Song s) => _items.any((x) => x.key == s.key);
  Song? local(Song s) => _items.where((x) => x.key == s.key).firstOrNull;

  Future<String> defaultDir() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final base = Platform.isAndroid ? await getExternalStorageDirectory() : null;
      return '${(base ?? await getApplicationDocumentsDirectory()).path}/Music';
    }
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return '$home${Platform.pathSeparator}Music${Platform.pathSeparator}云音';
  }

  Future<String> dir() async => settings.downloadDir ?? await defaultDir();

  /// 用于界面显示（例如 ~/Music/云音）。
  Future<String> displayDir() async {
    final d = await dir();
    if (kIsWeb) return d;
    final home = Platform.environment['HOME'];
    return home != null && d.startsWith(home) ? '~${d.substring(home.length)}' : d;
  }

  Future<File> _index() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/downloads.json');
  }

  Future<void> init() async {
    if (!supported) return;
    try {
      final f = await _index();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        for (final j in list) {
          final s = Song.fromJson(Map<String, dynamic>.from(j as Map));
          if (s.localPath != null && File(s.localPath!).existsSync()) _items.add(s);
        }
      }
    } catch (_) {}
  }

  Future<void> _save() {
    final data = jsonEncode([for (final song in _items) song.toJson()]);
    final save = _saving.then((_) async {
      final file = await _index();
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(data, flush: true);
      await temporary.rename(file.path);
    });
    _saving = save.catchError((Object _) {});
    return save;
  }

  String _safe(String name) => String.fromCharCodes(name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').runes.take(48));

  /// 下载歌曲；返回 false 表示无可用下载地址。
  Future<bool> download(Song song) {
    if (!supported || _disposed) return Future.value(false);
    if (isDownloaded(song)) return Future.value(true);
    return _pending[song.key] ??= _download(song).whenComplete(() {
      _pending.remove(song.key);
    });
  }

  Future<bool> _download(Song song) async {
    progress[song.key] = 0;
    _notify();
    File? temporary;
    try {
      final source = sources.byId(song.sourceId);
      final info = await resolveStream(source, song, settings.downloadQuality);
      if (info.url == null || _disposed) return false;
      final folder = Directory(await dir());
      await folder.create(recursive: true);
      final ext = Uri.parse(info.url!).pathSegments.lastOrNull?.split('.').last.toLowerCase() ?? '';
      final suffix = const {'mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wav', 'ape', 'wma', 'aiff', 'alac', 'dsf', 'dff'}.contains(ext) ? ext : 'mp3';
      final identity = sha256.convert(utf8.encode(song.key)).toString().substring(0, 16);
      final path = '${folder.path}${Platform.pathSeparator}${_safe('${song.artistText} - ${song.name}')} [$identity].$suffix';
      temporary = File('$path.part');
      await _dio.download(
        info.url!,
        temporary.path,
        options: Options(headers: info.headers),
        onReceiveProgress: (r, t) {
          if (t > 0) {
            progress[song.key] = r / t;
            _notify();
          }
        },
      );
      await temporary.rename(path);
      _items.insert(0, song.copyWith(localPath: path));
      await _save();
      return true;
    } finally {
      if (temporary != null && await temporary.exists()) await temporary.delete();
      progress.remove(song.key);
      _notify();
    }
  }

  Future<int> downloadAll(List<Song> songs) async {
    var n = 0;
    for (final s in songs) {
      try {
        if (await download(s)) n++;
      } catch (_) {}
    }
    return n;
  }

  Future<void> remove(Song song) async {
    final s = local(song);
    if (s == null) return;
    _items.remove(s);
    try {
      await File(s.localPath!).delete();
    } catch (_) {}
    await _save();
    _notify();
  }

  // ── 缓存 ──────────────────────────────────────────

  Future<int> cacheBytes() async {
    if (!supported) return 0;
    try {
      final tmp = await getTemporaryDirectory();
      final d = Directory('${tmp.path}/${DefaultCacheManager.key}');
      if (!await d.exists()) return 0;
      var total = 0;
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearCache() async {
    await DefaultCacheManager().emptyCache();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _dio.close(force: true);
    super.dispose();
  }
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}
