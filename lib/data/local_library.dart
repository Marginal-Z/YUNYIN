import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/text_decode.dart';
import 'models.dart';
import 'sources/local/local_source.dart';
import 'song_matcher.dart';
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

  /// 已导入歌曲的 id，用于快速去重（几千首歌时逐个比较会很慢）。
  final Set<String> _ids = {};
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 导入与补全过程中更新进度：最多每 150ms 通知一次界面，避免几千首歌时界面被频繁重建。
  void _progress(String text, {bool force = false}) {
    progress = text;
    final now = DateTime.now();
    if (!force && now.difference(_lastNotify) < const Duration(milliseconds: 150)) return;
    _lastNotify = now;
    notifyListeners();
  }

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
          final s = _repaired(Song.fromJson(Map<String, dynamic>.from(j as Map)));
          if (s.localPath != null && File(s.localPath!).existsSync() && _ids.add(s.id)) _songs.add(s);
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
      final paths = <String>[];
      for (var i = 0; i < files.length; i++) {
        _progress('正在复制 ${i + 1}/${files.length}');
        try {
          final path = await _materialize(files[i]);
          if (path != null) paths.add(path);
        } catch (e) {
          debugPrint('import ${files[i].name}: $e');
        }
      }
      final added = await _addMany(paths);
      return ImportResult(added, files.length - added);
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
      final added = await _addMany(paths);
      return ImportResult(added, paths.length - added);
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
      final added = await _addMany(paths, minDuration: const Duration(seconds: 30));
      return ImportResult(added, paths.length - added);
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

  /// 用于匹配封面与歌词的在线平台，按顺序尝试（网易云、QQ 音乐、酷狗）：
  /// 一个平台上没有这首歌或没有歌词时，继续在下一个平台中查找。
  List<MusicSource> onlineSources = const [];

  /// 只用一个平台匹配（测试用）。
  set online(MusicSource? s) => onlineSources = [?s];
  MusicSource? get online => onlineSources.firstOrNull;
  bool enriching = false;

  Future<File> _lyricsFile(Song s, {bool translation = false}) async => File('${(await _dir('lyrics')).path}/${s.id}.${translation ? 'tlrc' : 'lrc'}');

  Future<bool> _hasLyrics(Song s) async => (await lyricsFor(s)) != null;

  /// 为缺少封面或歌词的本地歌曲在网易云中查找同一首歌，下载封面并保存歌词（含翻译）。
  /// [force] 为 true 时即使已有封面与歌词也重新匹配。返回补全的歌曲数。
  Future<int> enrichOnline({Iterable<Song>? only, bool force = false}) async {
    if (onlineSources.isEmpty || enriching) return 0;
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
        _progress('正在联网补全封面与歌词 ${i + 1}/${targets.length}');
        try {
          if (await _enrichOne(targets[i], force: force)) done++;
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

  /// 依次在各平台中匹配，直到封面与歌词都补齐。
  Future<bool> _enrichOne(Song s, {bool force = false}) async {
    var needCover = force || s.cover == null;
    var needLyrics = force || !await _hasLyrics(s);
    var changed = false;
    for (final src in onlineSources) {
      if (!needCover && !needLyrics) break;
      Song? match;
      try {
        match = await _match(src, s);
      } catch (e) {
        debugPrint('match ${src.id} ${s.name}: $e');
      }
      if (match == null) continue;
      final r = await _apply(s, src, match, cover: needCover, lyrics: needLyrics);
      if (r.cover) needCover = false;
      if (r.lyrics) needLyrics = false;
      changed = changed || r.cover || r.lyrics;
    }
    return changed;
  }

  /// 把在线歌曲 [match] 的封面与歌词保存给本地歌曲 [s]。返回是否保存了封面 / 歌词。
  Future<({bool cover, bool lyrics})> _apply(Song s, MusicSource src, Song match, {bool cover = true, bool lyrics = true}) async {
    var gotCover = false, gotLyrics = false;
    final url = match.coverUrl;
    if (cover && url != null && url.startsWith('http')) {
      try {
        final sized = url.contains('music.126.net') && !url.contains('?') ? '$url?param=800y800' : url;
        final res = await Dio().get<List<int>>(sized, options: Options(responseType: ResponseType.bytes));
        final bytes = res.data;
        if (bytes != null && bytes.isNotEmpty) {
          final f = File('${(await _dir('covers')).path}/${s.id}.jpg');
          await f.writeAsBytes(bytes);
          // 同一路径的图片被替换后需要清掉内存中的旧图。
          await FileImage(f).evict();
          final i = _songs.indexWhere((x) => x.id == s.id);
          if (i >= 0) _songs[i] = _songs[i].copyWith(cover: f.path);
          gotCover = true;
        }
      } catch (e) {
        debugPrint('cover ${s.name}: $e');
      }
    }
    if (lyrics) {
      try {
        final ly = await src.lyrics(match);
        if (ly.lines.isNotEmpty) {
          await (await _lyricsFile(s)).writeAsString(_toLrc(ly, translation: false));
          final t = await _lyricsFile(s, translation: true);
          if (ly.hasTranslation) {
            await t.writeAsString(_toLrc(ly, translation: true));
          } else if (await t.exists()) {
            await t.delete();
          }
          gotLyrics = true;
        }
      } catch (e) {
        debugPrint('lyrics ${s.name}: $e');
      }
    }
    return (cover: gotCover, lyrics: gotLyrics);
  }

  /// 手动匹配：在各平台中搜索候选歌曲。
  Future<List<(MusicSource, Song)>> searchMatches(String keyword) async {
    final results = await Future.wait([
      for (final src in onlineSources)
        src
            .search(keyword, type: SearchType.song, limit: 8)
            .then((r) => [for (final x in r.songs) (src, x)])
            .catchError((Object _) => <(MusicSource, Song)>[]),
    ]);
    return [for (final r in results) ...r];
  }

  /// 手动匹配：用选中的在线歌曲替换本地歌曲的封面与歌词。
  Future<({bool cover, bool lyrics})> applyMatch(Song s, MusicSource src, Song match) async {
    final r = await _apply(s, src, match);
    await _save();
    notifyListeners();
    return r;
  }

  /// 测试用：按歌名、歌手与时长在 [online] 中匹配。
  @visibleForTesting
  Future<Song?> matchOnline(Song s) => _match(online!, s);

  /// 按歌名、歌手与时长挑选同一首歌（见 [SongMatcher]）。
  Future<Song?> _match(MusicSource src, Song s) => SongMatcher.match(src, s);

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
    return await f.exists() ? decodeText(await f.readAsBytes()) : null;
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

  /// 批量导入：标签、封面与内嵌歌词在后台 isolate 中解析（每批 24 个文件），界面线程只负责写文件与建立歌曲。
  /// 返回新增的歌曲数。
  Future<int> _addMany(List<String> paths, {Duration? minDuration}) async {
    final todo = [
      for (final p in paths)
        if (!_ids.contains(_id(p))) p,
    ];
    var added = 0;
    final minMs = minDuration?.inMilliseconds;
    for (var start = 0; start < todo.length; start += 24) {
      final chunk = todo.sublist(start, math.min(start + 24, todo.length));
      _progress('正在读取 ${math.min(start + chunk.length, todo.length)}/${todo.length}');
      final tags = await Isolate.run(() => [for (final p in chunk) readLocalTags(p, minMs)]);
      for (final t in tags) {
        if (t == null) continue;
        if (await _addTags(t)) added++;
      }
    }
    return added;
  }

  Future<bool> _addTags(LocalTags t) async {
    final id = _id(t.path);
    if (!_ids.add(id)) return false;
    String? cover;
    if (t.picture != null) {
      final c = File('${(await _dir('covers')).path}/$id.${t.pictureExt}');
      await c.writeAsBytes(t.picture!);
      cover = c.path;
    } else if (t.folderCover != null) {
      cover = t.folderCover;
    }
    if ((t.lyrics ?? '').trim().isNotEmpty) {
      await File('${(await _dir('lyrics')).path}/$id.lrc').writeAsString(t.lyrics!);
    }
    final artist = t.artist;
    final album = t.album;
    _songs.add(
      Song(
        id: id,
        sourceId: LocalSource.sourceId,
        name: t.title,
        artists: [ArtistRef('local:${artist ?? ''}', (artist ?? '').trim().isEmpty ? '未知歌手' : artist!.trim())],
        album: (album ?? '').trim().isEmpty ? null : AlbumRef('local:$album', album!.trim(), cover: cover),
        duration: Duration(milliseconds: t.durationMs),
        cover: cover,
        localPath: t.path,
      ),
    );
    return true;
  }

  /// 修复早先导入时乱码的歌名、歌手与专辑名。
  static Song _repaired(Song s) {
    final fixed = _reparsedName(s);
    if (fixed != null) return fixed;
    final name = repairMojibake(s.name);
    final artists = [for (final a in s.artists) ArtistRef(a.id, repairMojibake(a.name))];
    final album = s.album == null ? null : AlbumRef(s.album!.id, repairMojibake(s.album!.name), cover: s.album!.cover);
    if (name == s.name && artists.every((a) => s.artists.any((b) => b.name == a.name)) && album?.name == s.album?.name) return s;
    return Song(
      id: s.id,
      sourceId: s.sourceId,
      name: name,
      artists: artists,
      album: album,
      duration: s.duration,
      cover: s.cover,
      playable: s.playable,
      alias: s.alias,
      localPath: s.localPath,
      playCount: s.playCount,
    );
  }

  /// 早先按“歌手 - 歌名”解析的“歌名 - 歌手[专辑]”文件名：歌名与歌手是反的，按新的规则重新解析。
  static Song? _reparsedName(Song s) {
    final path = s.localPath;
    if (path == null) return null;
    final base = path.split(RegExp(r'[/\\]')).last.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final parsed = parseFileName(base);
    if (parsed.album == null || parsed.artist == null) return null;
    // 只修正与旧规则结果一致的歌曲（旧规则：第一段是歌手、其余是歌名）。
    final clean = base.replaceFirst(RegExp(r'^\d{1,3}[\s.\-_、]+'), '').trim();
    final parts = clean.split(RegExp(r'\s+-\s+'));
    if (parts.length != 2 || s.name != parts.last.trim() || s.artistText != parts.first.trim()) return null;
    final cover = s.album?.cover ?? s.cover;
    return Song(
      id: s.id,
      sourceId: s.sourceId,
      name: parsed.title,
      artists: [ArtistRef('local:${parsed.artist}', parsed.artist!)],
      album: AlbumRef('local:${parsed.album}', parsed.album!, cover: cover),
      duration: s.duration,
      cover: s.cover,
      playable: s.playable,
      alias: s.alias,
      localPath: s.localPath,
      playCount: s.playCount,
    );
  }

  /// 歌词：内嵌歌词（导入时提取）或同名 .lrc 文件（UTF-8、UTF-16 或 GBK 编码）。
  Future<String?> lyricsFor(Song song) async {
    final embedded = File('${(await _dir('lyrics')).path}/${song.id}.lrc');
    if (await embedded.exists()) return repairMojibake(decodeText(await embedded.readAsBytes()));
    final p = song.localPath;
    if (p == null) return null;
    final sidecar = File(p.replaceFirst(RegExp(r'\.[^.]+$'), '.lrc'));
    if (await sidecar.exists()) return decodeText(await sidecar.readAsBytes());
    return null;
  }

  Future<void> remove(Song song) async {
    _songs.removeWhere((s) => s.id == song.id);
    _ids.remove(song.id);
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

/// 后台 isolate 中解析出的本地歌曲信息（只含可在 isolate 之间传递的字段）。
class LocalTags {
  LocalTags({
    required this.path,
    required this.title,
    this.artist,
    this.album,
    this.durationMs = 0,
    this.lyrics,
    this.picture,
    this.pictureExt = 'jpg',
    this.folderCover,
  });

  final String path;
  final String title;
  final String? artist;
  final String? album;
  final int durationMs;
  final String? lyrics;
  final Uint8List? picture;
  final String pictureExt;

  /// 没有内嵌封面时，同目录下的 cover.jpg / folder.jpg 等图片。
  final String? folderCover;
}

/// 读取一个音频文件的标签（在后台 isolate 中运行）。比 [minMs] 短的音频（铃声、提示音）返回 null。
@visibleForTesting
LocalTags? readLocalTags(String path, int? minMs) {
  final file = File(path);
  String? title, artist, album, lyrics;
  var durationMs = 0;
  Uint8List? picture;
  var ext = 'jpg';
  try {
    final m = readMetadata(file, getImage: true);
    // 旧版播放器写入的 GBK 标签会被当作 Latin-1 读出，按原始字节重新解码。
    String? fix(String? s) => s == null ? null : repairMojibake(s);
    title = fix(m.title);
    artist = fix(m.artist ?? m.albumArtist);
    album = fix(m.album);
    durationMs = m.duration?.inMilliseconds ?? 0;
    if (minMs != null && durationMs > 0 && durationMs < minMs) return null;
    if (m.pictures.isNotEmpty) {
      final pic = m.pictures.first;
      picture = Uint8List.fromList(pic.bytes);
      if (pic.mimetype.contains('png')) ext = 'png';
    }
    if ((m.lyrics ?? '').trim().isNotEmpty) lyrics = repairMojibake(m.lyrics!);
  } catch (e) {
    debugPrint('metadata $path: $e');
  }
  // 没有标签时按文件名解析歌名、歌手与专辑（见 [parseFileName]）。
  final base = file.uri.pathSegments.last.replaceFirst(RegExp(r'\.[^.]+$'), '');
  if ((title ?? '').trim().isEmpty) {
    final parsed = parseFileName(base);
    title = parsed.title;
    artist ??= parsed.artist;
    album ??= parsed.album;
  }
  String? folderCover;
  if (picture == null) {
    final dir = file.parent.path;
    final sep = Platform.pathSeparator;
    for (final name in const ['cover.jpg', 'cover.png', 'folder.jpg', 'folder.png', 'front.jpg', 'Cover.jpg', 'Folder.jpg', 'AlbumArt.jpg', 'album.jpg']) {
      final f = File('$dir$sep$name');
      if (f.existsSync()) {
        folderCover = f.path;
        break;
      }
    }
  }
  return LocalTags(
    path: path,
    title: title!.trim().isEmpty ? base : title.trim(),
    artist: artist,
    album: album,
    durationMs: durationMs,
    lyrics: lyrics,
    picture: picture,
    pictureExt: ext,
    folderCover: folderCover,
  );
}

/// 从没有标签的音乐文件名中取歌名、歌手与专辑（不含扩展名）。
///
/// 先去掉开头的音轨号，再按“ - ”分成两段：常见的是“歌手 - 歌名”；
/// 下载站常用“歌名 - 歌手[专辑]”，带方括号（或【】）后缀的那一段是“歌手[专辑]”，另一段就是歌名。
/// 文件名中被替换成下划线的非法字符（如“…_”结尾）一并去掉。
({String title, String? artist, String? album}) parseFileName(String base) {
  final clean = base.replaceFirst(RegExp(r'^\d{1,3}[\s.\-_、]+'), '').trim();
  final parts = clean.split(RegExp(r'\s+-\s+'));
  if (parts.length < 2) return (title: clean, artist: null, album: null);
  final bracket = RegExp(r'^(.+?)\s*[\[【]([^\]】]*)[\]】]$');
  String tidy(String v) => v.replaceAll(RegExp(r'_+$'), '').trim();
  final last = bracket.firstMatch(parts.last.trim());
  if (parts.length == 2 && last != null) {
    final album = tidy(last.group(2)!);
    return (title: parts.first.trim(), artist: tidy(last.group(1)!), album: album.isEmpty ? null : album);
  }
  return (title: parts.sublist(1).join(' - ').trim(), artist: parts.first.trim(), album: null);
}

