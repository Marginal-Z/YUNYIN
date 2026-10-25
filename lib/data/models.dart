/// 与具体平台无关的数据模型。每个对象都带 [sourceId]，
/// 以便播放队列可以混合来自不同播放源的歌曲。
library;

class ArtistRef {
  const ArtistRef(this.id, this.name);

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory ArtistRef.fromJson(Map<String, dynamic> j) => ArtistRef('${j['id']}', '${j['name']}');
}

class AlbumRef {
  const AlbumRef(this.id, this.name, {this.cover});

  final String id;
  final String name;
  final String? cover;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'cover': cover};
  factory AlbumRef.fromJson(Map<String, dynamic> j) => AlbumRef('${j['id']}', '${j['name']}', cover: j['cover'] as String?);
}

class Song {
  const Song({
    required this.id,
    required this.sourceId,
    required this.name,
    this.artists = const [],
    this.album,
    this.duration = Duration.zero,
    this.cover,
    this.playable = true,
    this.alias,
    this.localPath,
    this.playCount,
  });

  final String id;
  final String sourceId;
  final String name;
  final List<ArtistRef> artists;
  final AlbumRef? album;
  final Duration duration;
  final String? cover;

  /// 平台标记为无版权 / 需会员时为 false。
  final bool playable;
  final String? alias;

  /// 已下载到本地时的文件路径。
  final String? localPath;

  /// 热门歌曲的播放次数文案（例如“4.2 亿次”）。
  final String? playCount;

  String get key => '$sourceId:$id';
  String get artistText => artists.isEmpty ? '未知歌手' : artists.map((a) => a.name).join(' / ');
  String get albumName => album?.name ?? '';
  String get subtitle => albumName.isEmpty ? artistText : '$artistText · $albumName';
  String? get coverUrl => cover ?? album?.cover;

  Song copyWith({String? localPath, String? cover, Duration? duration}) => Song(
    id: id,
    sourceId: sourceId,
    name: name,
    artists: artists,
    album: album,
    duration: duration ?? this.duration,
    cover: cover ?? this.cover,
    playable: playable,
    alias: alias,
    localPath: localPath ?? this.localPath,
    playCount: playCount,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'name': name,
    'artists': artists.map((a) => a.toJson()).toList(),
    'album': album?.toJson(),
    'duration': duration.inMilliseconds,
    'cover': cover,
    'playable': playable,
    'alias': alias,
    'localPath': localPath,
  };

  factory Song.fromJson(Map<String, dynamic> j) => Song(
    id: '${j['id']}',
    sourceId: '${j['sourceId']}',
    name: '${j['name']}',
    artists: [for (final a in (j['artists'] as List? ?? const [])) ArtistRef.fromJson(Map<String, dynamic>.from(a as Map))],
    album: j['album'] == null ? null : AlbumRef.fromJson(Map<String, dynamic>.from(j['album'] as Map)),
    duration: Duration(milliseconds: (j['duration'] as num?)?.toInt() ?? 0),
    cover: j['cover'] as String?,
    playable: j['playable'] as bool? ?? true,
    alias: j['alias'] as String?,
    localPath: j['localPath'] as String?,
  );

  @override
  bool operator ==(Object other) => other is Song && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class PlaylistInfo {
  const PlaylistInfo({
    required this.id,
    required this.sourceId,
    required this.name,
    this.cover,
    this.trackCount = 0,
    this.creator,
    this.description,
    this.tags = const [],
    this.playCount = 0,
    this.tracks,
    this.subscribed = false,
    this.isLikedList = false,
    this.ownedByMe = false,
    this.downloaded = false,
    this.kind = PlaylistKind.playlist,
  });

  final String id;
  final String sourceId;
  final String name;
  final String? cover;
  final int trackCount;
  final String? creator;
  final String? description;
  final List<String> tags;
  final int playCount;
  final List<Song>? tracks;
  final bool subscribed;
  final bool isLikedList;
  final bool ownedByMe;
  final bool downloaded;
  final PlaylistKind kind;

  String get genre => tags.isEmpty ? '' : tags.first;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'name': name,
    'cover': cover,
    'trackCount': trackCount,
    'creator': creator,
    'description': description,
    'tags': tags,
    'playCount': playCount,
    'kind': kind.name,
  };

  factory PlaylistInfo.fromJson(Map<String, dynamic> j) => PlaylistInfo(
    id: '${j['id']}',
    sourceId: '${j['sourceId']}',
    name: '${j['name']}',
    cover: j['cover'] as String?,
    trackCount: (j['trackCount'] as num?)?.toInt() ?? 0,
    creator: j['creator'] as String?,
    description: j['description'] as String?,
    tags: [for (final t in (j['tags'] as List? ?? const [])) '$t'],
    playCount: (j['playCount'] as num?)?.toInt() ?? 0,
    kind: PlaylistKind.values.asNameMap()[j['kind']] ?? PlaylistKind.playlist,
  );

  Duration get totalDuration => (tracks ?? const <Song>[]).fold(Duration.zero, (a, s) => a + s.duration);

  PlaylistInfo withTracks(List<Song> songs) => PlaylistInfo(
    id: id,
    sourceId: sourceId,
    name: name,
    cover: cover,
    trackCount: trackCount == 0 ? songs.length : trackCount,
    creator: creator,
    description: description,
    tags: tags,
    playCount: playCount,
    tracks: songs,
    subscribed: subscribed,
    isLikedList: isLikedList,
    ownedByMe: ownedByMe,
    downloaded: downloaded,
    kind: kind,
  );
}

enum PlaylistKind { playlist, album, chart, daily, recent, liked, downloaded, radio, local }

class ArtistInfo {
  const ArtistInfo({
    required this.id,
    required this.sourceId,
    required this.name,
    this.avatar,
    this.fans,
    this.description,
    this.hotSongs = const [],
    this.followed = false,
  });

  final String id;
  final String sourceId;
  final String name;
  final String? avatar;
  final int? fans;
  final String? description;
  final List<Song> hotSongs;
  final bool followed;
}

class AlbumInfo {
  const AlbumInfo({
    required this.id,
    required this.sourceId,
    required this.name,
    this.cover,
    this.artist,
    this.publishTime,
    this.description,
    this.songs,
    this.size = 0,
  });

  final String id;
  final String sourceId;
  final String name;
  final String? cover;
  final ArtistRef? artist;
  final DateTime? publishTime;
  final String? description;
  final List<Song>? songs;
  final int size;
}

class ChartInfo {
  const ChartInfo({required this.id, required this.name, this.cover, this.update, this.preview = const []});

  final String id;
  final String name;
  final String? cover;
  final String? update;
  final List<String> preview;
}

class RadioInfo {
  const RadioInfo({required this.id, required this.sourceId, required this.name, this.cover, this.host, this.programCount = 0, this.category});

  final String id;
  final String sourceId;
  final String name;
  final String? cover;
  final String? host;
  final int programCount;
  final String? category;
}

class LyricLine {
  const LyricLine(this.time, this.text, {this.translation});

  final Duration time;
  final String text;
  final String? translation;
}

class Lyrics {
  const Lyrics(this.lines, {this.synced = true});

  static const empty = Lyrics([]);

  final List<LyricLine> lines;
  final bool synced;

  bool get hasTranslation => lines.any((l) => (l.translation ?? '').isNotEmpty);

  int indexAt(Duration pos) {
    if (!synced || lines.isEmpty) return -1;
    var lo = 0, hi = lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= pos) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }
}

class Comment {
  const Comment({
    required this.id,
    required this.userName,
    required this.content,
    this.avatar,
    this.time,
    this.location,
    this.likedCount = 0,
    this.liked = false,
    this.replyCount = 0,
  });

  final String id;
  final String userName;
  final String? avatar;
  final String content;
  final DateTime? time;
  final String? location;
  final int likedCount;
  final bool liked;
  final int replyCount;
}

class CommentPage {
  const CommentPage({required this.total, required this.comments, this.hasMore = false});

  final int total;
  final List<Comment> comments;
  final bool hasMore;
}

enum CommentSort { recommend, hot, latest }

class UserProfile {
  const UserProfile({required this.id, required this.nickname, this.avatar, this.signature, this.vip = false});

  final String id;
  final String nickname;
  final String? avatar;
  final String? signature;
  final bool vip;
}

enum SearchType { all, song, artist, album, playlist }

class SearchResult {
  const SearchResult({
    this.songs = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
    this.bestSong,
    this.bestPlaylist,
    this.songCount = 0,
  });

  final List<Song> songs;
  final List<ArtistInfo> artists;
  final List<AlbumInfo> albums;
  final List<PlaylistInfo> playlists;
  final Song? bestSong;
  final PlaylistInfo? bestPlaylist;
  final int songCount;
}

class HotSearch {
  const HotSearch(this.keyword, {this.score = 0, this.tag});

  final String keyword;
  final int score;

  /// hot / new / up
  final String? tag;
}

/// 首页数据。
class HomeFeed {
  const HomeFeed({required this.daily, required this.playlists});

  Map<String, dynamic> toJson() => {'daily': [for (final s in daily) s.toJson()], 'playlists': [for (final p in playlists) p.toJson()]};

  factory HomeFeed.fromJson(Map<String, dynamic> j) => HomeFeed(
    daily: [for (final s in (j['daily'] as List? ?? const [])) Song.fromJson(Map<String, dynamic>.from(s as Map))],
    playlists: [for (final p in (j['playlists'] as List? ?? const [])) PlaylistInfo.fromJson(Map<String, dynamic>.from(p as Map))],
  );

  /// 每日推荐歌曲。
  final List<Song> daily;
  final List<PlaylistInfo> playlists;
}

enum AudioQuality {
  standard('标准', 'standard', 128000),
  higher('较高', 'higher', 192000),
  exhigh('极高', 'exhigh', 320000),
  lossless('无损', 'lossless', 999000),
  hires('Hi-Res', 'hires', 1999000);

  const AudioQuality(this.label, this.level, this.bitrate);

  final String label;
  final String level;
  final int bitrate;
}

/// 播放地址。[url] 为空表示无法播放（无版权等）。
class StreamInfo {
  const StreamInfo({this.url, this.headers = const {}, this.trial = false, this.quality, this.gainDb});

  final String? url;
  final Map<String, String> headers;
  final bool trial;
  final AudioQuality? quality;

  /// 平台提供的响度增益（dB，类似 ReplayGain），用于音量均衡。
  final double? gainDb;
}

/// 二维码登录凭据。
class QrTicket {
  const QrTicket(this.key, this.content);

  final String key;

  /// 需要渲染成二维码的内容。
  final String content;
}

enum QrState { waiting, scanned, confirmed, expired }
