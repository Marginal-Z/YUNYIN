import '../../cloud/cloud_drives.dart';
import '../../models.dart';
import '../../song_matcher.dart';
import '../music_source.dart';
import '../netease/netease_source.dart' show parseLrc;

/// 网盘播放源：播放挂载网盘（WebDAV）中的音乐文件。不出现在“切换播放源”列表中。
///
/// 歌曲 id 为“网盘 id|文件路径”。歌词优先读取同目录的同名 .lrc，没有时用网易云同一首歌的歌词。
class CloudSource extends MusicSource {
  CloudSource(this.drives, {this.fallback});

  static const sourceId = 'cloud';

  final CloudDrives drives;

  /// 匹配歌词用的在线播放源（网易云音乐）。
  final MusicSource? fallback;
  final Map<String, Song?> _matches = {};

  @override
  String get id => sourceId;

  @override
  String get name => '网盘';

  @override
  String get description => '挂载的 WebDAV 网盘中的音乐';

  @override
  bool get selectable => false;

  @override
  Set<SourceFeature> get features => const {SourceFeature.lyrics};

  /// 网盘中的音乐文件转为歌曲。文件名为“歌手 - 歌名”时拆出歌手。
  static Song songOf(CloudDrive d, CloudEntry e) {
    var title = e.name;
    final dot = title.lastIndexOf('.');
    if (dot > 0) title = title.substring(0, dot);
    title = title.replaceFirst(RegExp(r'^\d{1,3}[\s.\-_、]+'), '').trim();
    var artists = const <ArtistRef>[];
    final sep = title.indexOf(' - ');
    if (sep > 0) {
      artists = [
        for (final a in title.substring(0, sep).split(RegExp(r'\s*[、/&,，]\s*')))
          if (a.trim().isNotEmpty) ArtistRef('cloud:${a.trim()}', a.trim()),
      ];
      title = title.substring(sep + 3).trim();
    }
    return Song(
      id: '${d.id}|${e.href}',
      sourceId: sourceId,
      name: title.isEmpty ? e.name : title,
      artists: artists,
      album: AlbumRef('', d.name),
    );
  }

  ({CloudDrive? drive, String href}) _locate(Song song) {
    final i = song.id.indexOf('|');
    if (i < 0) return (drive: null, href: '');
    return (
      drive: drives.byId(song.id.substring(0, i)),
      href: song.id.substring(i + 1),
    );
  }

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async {
    final f = _locate(song);
    final d = f.drive;
    if (d == null) throw Exception('这首歌所在的网盘已移除');
    final direct = await drives.resolveDirect(d, f.href);
    return direct != null
        ? StreamInfo(url: direct)
        : StreamInfo(url: d.fileUrl(f.href), headers: d.headers);
  }

  @override
  Future<Lyrics> lyrics(Song song) async {
    final f = _locate(song);
    final d = f.drive;
    if (d != null) {
      final dot = f.href.lastIndexOf('.');
      final text = dot > 0
          ? await drives.readText(d, '${f.href.substring(0, dot)}.lrc')
          : null;
      if (text != null && text.contains('[')) {
        final ly = parseLrc(text);
        if (ly.lines.isNotEmpty) return ly;
      }
    }
    final src = fallback;
    if (src == null) return Lyrics.empty;
    final m = _matches.containsKey(song.id)
        ? _matches[song.id]
        : _matches[song.id] = await SongMatcher.match(src, song);
    return m == null ? Lyrics.empty : src.lyrics(m);
  }
}
