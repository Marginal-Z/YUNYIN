import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'sources/local/local_source.dart';

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
    final files = await FilePicker.pickFiles(
      dialogTitle: '选择要导入的音乐',
      type: FileType.custom,
      allowedExtensions: kAudioExtensions,
    );
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

  Future<ImportResult> _run(Future<ImportResult> Function() body) async {
    importing = true;
    notifyListeners();
    try {
      final r = await body();
      await _save();
      return r;
    } finally {
      importing = false;
      progress = null;
      notifyListeners();
    }
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

  Future<bool> _add(String path) async {
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
    _songs.add(Song(
      id: id,
      sourceId: LocalSource.sourceId,
      name: title!.trim(),
      artists: [ArtistRef('local:${artist ?? ''}', (artist ?? '').trim().isEmpty ? '未知歌手' : artist!.trim())],
      album: (album ?? '').trim().isEmpty ? null : AlbumRef('local:$album', album!.trim(), cover: cover),
      duration: duration,
      cover: cover,
      localPath: path,
    ));
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
