import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'sources/local/local_source.dart';
import 'sources/music_source.dart';

/// 支持导入的音频格式。
const kAudioExtensions = ['mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wav', 'ape', 'wma', 'aiff', 'alac'];

/// 导入结果。
class ImportResult {
  const ImportResult(this.added, this.skipped);

  final int added;
  final int skipped;
}

/// 本地音乐库：导入的歌曲索引、读取标签与封面。
///
/// 桌面端直接引用原文件；Android / iOS 的文件选择器只给出受限访问的内容地址，导入时复制到应用目录。
class LocalLibrary extends ChangeNotifier {
  final List<Song> _songs = [];
  bool importing = false;
  String? progress;

  List<Song> get songs => List.unmodifiable(_songs);
  bool get supported => !kIsWeb;
  bool get canImportFolder => !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
  bool get _copyOnImport => Platform.isAndroid || Platform.isIOS;

  Future<Directory> _dir(String name) async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/$name');
    await d.create(recursive: true);
    return d;
  }

  Future<File> _index() async => File('${(await _dir('local')).path}/library.json');

  Future<void> init() async {
    if (!supported) return;
    try {
      final f = await _index();
      if (await f.exists()) {
        for (final j in jsonDecode(await f.readAsString()) as List) {
          final s = Song.fromJson(Map<String, dynamic>.from(j as Map));
          if (s.localPath != null && File(s.localPath!).existsSync()) _songs.add(s);
        }
      }
    } catch (e) {
      debugPrint('local library: $e');
    }
  }

  Future<void> _save() async {
    final f = await _index();
    await f.writeAsString(jsonEncode([for (final s in _songs) s.toJson()]));
  }

  bool _isAudio(String path) => kAudioExtensions.contains(path.split('.').last.toLowerCase());

  /// 选择若干音频文件导入。
  Future<ImportResult?> importFiles() async {
    final files = await FilePicker.pickFiles(dialogTitle: '选择要导入的音乐', type: FileType.custom, allowedExtensions: kAudioExtensions);
    if (files.isEmpty) return null;
    return _run(() async {
      var added = 0, skipped = 0;
      for (var i = 0; i < files.length; i++) {
        progress = '正在导入 ${i + 1}/${files.length}';
        notifyListeners();
        try {
          final path = await _materialize(files[i]);
          if (path != null && await _add(path)) {
            added++;
          } else {
            skipped++;
          }
        } catch (e) {
          debugPrint('import ${files[i].name}: $e');
          skipped++;
        }
      }
      return ImportResult(added, skipped);
    });
  }

  /// 选择一个文件夹，递归导入其中的音频（桌面端）。
  Future<ImportResult?> importFolder() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: '选择音乐文件夹');
    if (dir == null) return null;
    return _run(() async {
      final paths = <String>[];
      await for (final e in Directory(dir).list(recursive: true, followLinks: false)) {
        if (e is File && _isAudio(e.path)) paths.add(e.path);
      }
      var added = 0, skipped = 0;
      for (var i = 0; i < paths.length; i++) {
        progress = '正在导入 ${i + 1}/${paths.length}';
        notifyListeners();
        try {
          (await _add(paths[i])) ? added++ : skipped++;
        } catch (e) {
          skipped++;
        }
      }
      return ImportResult(added, skipped);
    });
  }

  /// 扫描本机歌曲：Android 读取系统媒体库（需要音频权限），桌面端遍历“音乐”与“下载”目录。
  /// 扫描到的文件直接引用原路径，不复制；短于 30 秒的音频（铃声、提示音）不导入。
  Future<ImportResult?> scanDevice() async {
    if (!supported || importing) return null;
    return _run(() async {
      progress = '正在扫描本机歌曲…';
      notifyListeners();
      final paths = Platform.isAndroid ? await _scanMediaStore() : await _scanFolders();
      var added = 0, skipped = 0;
      for (var i = 0; i < paths.length; i++) {
        progress = '正在读取 ${i + 1}/${paths.length}';
        notifyListeners();
        try {
          (await _add(paths[i], minDuration: const Duration(seconds: 30))) ? added++ : skipped++;
        } catch (e) {
          skipped++;
        }
      }
      return ImportResult(added, skipped);
    });
  }

  static const _media = MethodChannel('yunyin/media');

  Future<List<String>> _scanMediaStore() async {
    try {
      final list = await _media.invokeListMethod<String>('scanAudio');
      return [
        for (final p in list ?? const <String>[])
          if (File(p).existsSync()) p,
      ];
    } on PlatformException catch (e) {
      throw Exception(e.code == 'denied' ? '需要允许访问音乐与音频才能扫描本机歌曲' : (e.message ?? e.code));
    }
  }

  /// 桌面端的音乐目录：XDG 用户目录（Linux）与家目录下的常见名称。
  List<Directory> _musicFolders() {
    final home = Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (home == null) return [];
    final names = <String>{'Music', '音乐', 'Downloads', '下载'};
    if (Platform.isLinux) {
      try {
        final dirs = File('$home/.config/user-dirs.dirs').readAsLinesSync();
        for (final l in dirs) {
          final m = RegExp(r'^XDG_(MUSIC|DOWNLOAD)_DIR="(.+)"$').firstMatch(l.trim());
          if (m != null) names.add(m.group(2)!.replaceFirst(r'$HOME/', ''));
        }
      } catch (_) {}
    }
    final sep = Platform.pathSeparator;
    final seen = <String>{};
    return [
      for (final n in names)
        if (Directory('$home$sep$n').existsSync() && seen.add(Directory('$home$sep$n').resolveSymbolicLinksSync())) Directory('$home$sep$n'),
    ];
  }

  Future<List<String>> _scanFolders() async {
    final paths = <String>[];
    for (final dir in _musicFolders()) {
      try {
        await for (final e in dir.list(recursive: true, followLinks: false).handleError((_) {})) {
          if (e is! File || !_isAudio(e.path)) continue;
          // 跳过隐藏目录与很小的文件（提示音等）。
          if (e.path.split(Platform.pathSeparator).any((part) => part.startsWith('.') && part.length > 1)) continue;
          if (await e.length() < 300 * 1024) continue;
          paths.add(e.path);
        }
      } catch (e) {
        debugPrint('scan ${dir.path}: $e');
      }
    }
    return paths;
  }

  Future<ImportResult> _run(Future<ImportResult> Function() body) async {
    importing = true;
    notifyListeners();
    final before = _songs.length;
    try {
      final r = await body();
      await _save();
      return r;
    } finally {
      importing = false;
      progress = null;
      notifyListeners();
      // 新导入的歌曲在后台联网补全缺少的封面与歌词。
      if (_songs.length > before) unawaited(enrichOnline(only: _songs.sublist(before)));
    }
  }

  // ── 联网补全封面与歌词 ──────────────────────────────

  /// 用于匹配的在线播放源（网易云）。
  MusicSource? online;
  bool enriching = false;

  Future<File> _lyricsFile(Song s, {bool translation = false}) async => File('${(await _dir('lyrics')).path}/${s.id}.${translation ? 'tlrc' : 'lrc'}');

  Future<bool> _hasLyrics(Song s) async => (await lyricsFor(s)) != null;

  /// 为缺少封面或歌词的本地歌曲在网易云中查找同一首歌，下载封面并保存歌词（含翻译）。
  /// [force] 为 true 时即使已有封面与歌词也重新匹配。返回补全的歌曲数。
  Future<int> enrichOnline({Iterable<Song>? only, bool force = false}) async {
    final src = online;
    if (src == null || enriching) return 0;
    final targets = <Song>[];
    for (final s in only ?? List.of(_songs)) {
      if (force || s.cover == null || !await _hasLyrics(s)) targets.add(s);
    }
    if (targets.isEmpty) return 0;
    enriching = true;
    notifyListeners();
    var done = 0;
    try {
      for (var i = 0; i < targets.length; i++) {
        progress = '正在联网补全封面与歌词 ${i + 1}/${targets.length}';
        notifyListeners();
        try {
          if (await _enrichOne(src, targets[i], force: force)) done++;
        } catch (e) {
          debugPrint('enrich ${targets[i].name}: $e');
        }
        // 控制请求频率，避免触发风控。
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await _save();
    } finally {
      enriching = false;
      progress = null;
      notifyListeners();
    }
    return done;
  }

  Future<bool> _enrichOne(MusicSource src, Song s, {bool force = false}) async {
    final match = await _match(src, s);
    if (match == null) return false;
    var changed = false;
    var cover = s.cover;
    final url = match.coverUrl;
    if ((force || cover == null) && url != null && url.startsWith('http')) {
      final sized = url.contains('music.126.net') && !url.contains('?') ? '$url?param=800y800' : url;
      final res = await Dio().get<List<int>>(sized, options: Options(responseType: ResponseType.bytes));
      final bytes = res.data;
      if (bytes != null && bytes.isNotEmpty) {
        final f = File('${(await _dir('covers')).path}/${s.id}.jpg');
        await f.writeAsBytes(bytes);
        // 同一路径的图片被替换后需要清掉内存中的旧图。
        await FileImage(f).evict();
        cover = f.path;
        changed = true;
      }
    }
    if (force || !await _hasLyrics(s)) {
      final ly = await src.lyrics(match);
      if (ly.lines.isNotEmpty) {
        await (await _lyricsFile(s)).writeAsString(_toLrc(ly, translation: false));
        if (ly.hasTranslation) await (await _lyricsFile(s, translation: true)).writeAsString(_toLrc(ly, translation: true));
        changed = true;
      }
    }
    if (cover != s.cover) {
      final i = _songs.indexWhere((x) => x.id == s.id);
      if (i >= 0) _songs[i] = _songs[i].copyWith(cover: cover);
    }
    return changed;
  }

  /// 测试用：按歌名、歌手与时长在 [online] 中匹配。
  @visibleForTesting
  Future<Song?> matchOnline(Song s) => _match(online!, s);

  static String _norm(String x) => x.toLowerCase().replaceAll(RegExp(r'''[\s()（）\[\]【】《》\-_·.,，。!！?？'"“”‘’&/、]'''), '');

  /// 按歌名、歌手与时长打分，挑选最可能是同一首歌的结果。
  Future<Song?> _match(MusicSource src, Song s) async {
    final artist = s.artists.isEmpty || s.artistText == '未知歌手' ? '' : s.artists.first.name;
    final r = await src.search('${s.name} $artist'.trim(), type: SearchType.song, limit: 10);
    final title = _norm(s.name);
    final artists = [for (final a in s.artists) _norm(a.name)].where((a) => a.isNotEmpty && a != _norm('未知歌手')).toList();
    Song? best;
    var bestScore = 0;
    for (final c in r.songs) {
      final t = _norm(c.name);
      var score = t == title ? 4 : ((t.contains(title) || title.contains(t)) && t.isNotEmpty && title.isNotEmpty ? 2 : 0);
      if (score == 0) continue;
      final artistHit = artists.isNotEmpty && c.artists.any((a) => artists.any((x) => _norm(a.name) == x || _norm(a.name).contains(x) || x.contains(_norm(a.name))));
      if (artistHit) score += 3;
      if (s.duration > Duration.zero && c.duration > Duration.zero) {
        final diff = (s.duration - c.duration).abs();
        if (diff <= const Duration(seconds: 3)) {
          score += 2;
        } else if (diff > const Duration(seconds: 20)) {
          score -= 3;
        }
      }
      // 歌名部分吻合（如“晴天 (钢琴版)”）时必须歌手一致；歌手对不上时只接受歌名完全相同且时长几乎一致的结果，
      // 以免把翻唱、伴奏的封面当成原曲。
      final durationOk = s.duration > Duration.zero && c.duration > Duration.zero && (s.duration - c.duration).abs() <= const Duration(seconds: 3);
      if (t != title && !artistHit) continue;
      if (!artistHit && !durationOk) continue;
      if (score > bestScore) {
        best = c;
        bestScore = score;
      }
    }
    return best;
  }

  static String _toLrc(Lyrics ly, {required bool translation}) {
    String stamp(Duration d) =>
        '[${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}.${(d.inMilliseconds % 1000).toString().padLeft(3, '0')}]';
    return [
      for (final l in ly.lines)
        if (!translation || (l.translation ?? '').isNotEmpty) '${ly.synced ? stamp(l.time) : ''}${translation ? l.translation : l.text}',
    ].join('\n');
  }

  /// 联网获取的歌词翻译。
  Future<String?> translationFor(Song song) async {
    final f = await _lyricsFile(song, translation: true);
    return await f.exists() ? f.readAsString() : null;
  }

  /// 得到可直接读取的本地路径；移动端把内容复制到应用目录。
  Future<String?> _materialize(PlatformFile f) async {
    final direct = f.path;
    if (direct != null && !_copyOnImport) return direct;
    final dir = await _dir('music');
    final target = File('${dir.path}/${f.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}');
    if (await target.exists() && await target.length() == (f.lengthSync() ?? -1)) return target.path;
    final sink = target.openWrite();
    await sink.addStream(f.readAsByteStream());
    await sink.close();
    return target.path;
  }

  String _id(String path) => sha1.convert(utf8.encode(path)).toString().substring(0, 16);

  Future<bool> _add(String path, {Duration? minDuration}) async {
    final id = _id(path);
    if (_songs.any((s) => s.id == id)) return false;
    final file = File(path);
    String? title, artist, album, cover;
    var duration = Duration.zero;
    try {
      final m = readMetadata(file, getImage: true);
      title = m.title;
      artist = m.artist ?? m.albumArtist;
      album = m.album;
      duration = m.duration ?? Duration.zero;
      if (minDuration != null && duration > Duration.zero && duration < minDuration) return false;
      if (m.pictures.isNotEmpty) {
        final pic = m.pictures.first;
        final ext = pic.mimetype.contains('png') ? 'png' : 'jpg';
        final c = File('${(await _dir('covers')).path}/$id.$ext');
        await c.writeAsBytes(pic.bytes);
        cover = c.path;
      }
      if ((m.lyrics ?? '').trim().isNotEmpty) {
        await File('${(await _dir('lyrics')).path}/$id.lrc').writeAsString(m.lyrics!);
      }
    } catch (e) {
      debugPrint('metadata $path: $e');
    }
    // 没有标签时按“歌手 - 歌名”解析文件名。
    final base = file.uri.pathSegments.last.replaceFirst(RegExp(r'\.[^.]+$'), '');
    if ((title ?? '').trim().isEmpty) {
      final parts = base.split(' - ');
      if (parts.length >= 2) {
        artist ??= parts.first.trim();
        title = parts.sublist(1).join(' - ').trim();
      } else {
        title = base;
      }
    }
    _songs.add(
      Song(
        id: id,
        sourceId: LocalSource.sourceId,
        name: title!.trim(),
        artists: [ArtistRef('local:${artist ?? ''}', (artist ?? '').trim().isEmpty ? '未知歌手' : artist!.trim())],
        album: (album ?? '').trim().isEmpty ? null : AlbumRef('local:$album', album!.trim(), cover: cover),
        duration: duration,
        cover: cover,
        localPath: path,
      ),
    );
    return true;
  }

  /// 歌词：内嵌歌词（导入时提取）或同名 .lrc 文件。
  Future<String?> lyricsFor(Song song) async {
    final embedded = File('${(await _dir('lyrics')).path}/${song.id}.lrc');
    if (await embedded.exists()) return embedded.readAsString();
    final p = song.localPath;
    if (p == null) return null;
    final sidecar = File(p.replaceFirst(RegExp(r'\.[^.]+$'), '.lrc'));
    if (await sidecar.exists()) return sidecar.readAsString();
    return null;
  }

  Future<void> remove(Song song) async {
    _songs.removeWhere((s) => s.id == song.id);
    final p = song.localPath;
    // 只删除复制到应用目录里的副本，不动用户原文件。
    if (p != null && p.startsWith((await _dir('music')).path)) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    await _save();
    notifyListeners();
  }
}
