/// 与具体平台无关的数据模型。每个对象都带 [sourceId]，
/// 以便播放队列可以混合来自不同播放源的歌曲。
library;

import 'dart:typed_data';

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

/// 修正已保存的图片地址：酷我的图片服务器（kwcdn）不支持 https，早先保存成 https 的地址改回 http。
String? fixImageUrl(String? url) {
  if (url == null || !url.startsWith('https://') || !url.contains('.kwcdn.kuwo.cn/')) return url;
  return 'http://${url.substring(8)}';
}

/// 歌曲的付费类型，按各平台自己的规则判断：
/// - [vip]：平台会员可以完整播放（网易云黑胶 VIP、QQ 音乐绿钻、酷狗 VIP）；
/// - [paid]：需要单独购买（数字专辑、付费单曲），开通会员也不能播放完整版；
/// - [free]：免费歌曲。
enum SongFee { free, vip, paid }

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
    this.fee = SongFee.free,
    this.maxQuality,
    this.gainDb,
    this.peak,
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

  /// 平台规定的付费类型（列表中按平台样式显示 VIP / 付费标志）。
  final SongFee fee;

  /// 平台提供的最高音质（列表中显示 SQ / Hi-Res 标志）；不知道时为 null。
  final AudioQuality? maxQuality;

  /// 平台在歌曲信息中给出的响度增益（dB）与峰值（线性，1 为满刻度），用于音量均衡与不削波的音量增强。
  final double? gainDb;
  final double? peak;

  /// 会员或付费歌曲（未登录、没有会员或没有购买时通常只能试听）。
  bool get vip => fee != SongFee.free;

  String get key => '$sourceId:$id';
  String get artistText => artists.isEmpty ? '未知歌手' : artists.map((a) => a.name).join(' / ');
  String get albumName => album?.name ?? '';
  String get subtitle => albumName.isEmpty ? artistText : '$artistText · $albumName';
  String? get coverUrl => fixImageUrl(cover ?? album?.cover);

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
    fee: fee,
    maxQuality: maxQuality,
    gainDb: gainDb,
    peak: peak,
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
    if (fee != SongFee.free) 'fee': fee.name,
    if (maxQuality != null) 'maxQuality': maxQuality!.name,
    if (gainDb != null) 'gain': gainDb,
    if (peak != null) 'peak': peak,
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
    // 旧版本只保存了 vip 标记。
    fee: SongFee.values.asNameMap()[j['fee']] ?? (j['vip'] == true ? SongFee.vip : SongFee.free),
    maxQuality: AudioQuality.values.asNameMap()[j['maxQuality']],
    gainDb: (j['gain'] as num?)?.toDouble(),
    peak: (j['peak'] as num?)?.toDouble(),
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
  const ChartInfo({required this.id, required this.name, this.cover, this.update, this.preview = const [], this.group});

  final String id;
  final String name;
  final String? cover;
  final String? update;
  final List<String> preview;

  /// 平台上的榜单分组，例如“巅峰榜”“地区榜”“全球榜”。
  final String? group;
}

/// 歌单广场的分类（标签）。[id] 为请求该分类歌单时使用的平台标识。
class PlaylistCategory {
  const PlaylistCategory({required this.id, required this.name, this.group});

  final String id;
  final String name;

  /// 分组，例如“语种”“风格”“场景”；推荐 / 全部分类没有分组。
  final String? group;
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

/// 逐字歌词中的一个字 / 词：开始时间与持续时长。
class LyricWord {
  const LyricWord(this.start, this.duration, this.text);

  final Duration start;
  final Duration duration;
  final String text;

  Duration get end => start + duration;
}

class LyricLine {
  const LyricLine(this.time, this.text, {this.translation, this.words, this.duration});

  final Duration time;
  final String text;
  final String? translation;

  /// 逐字时间轴（网易云 yrc）；没有时为 null，按整行时长估算填色。
  final List<LyricWord>? words;

  /// 本行演唱时长（逐字歌词提供）。
  final Duration? duration;
}

class Lyrics {
  const Lyrics(this.lines, {this.synced = true});

  static const empty = Lyrics([]);

  final List<LyricLine> lines;
  final bool synced;

  bool get hasTranslation => lines.any((l) => (l.translation ?? '').isNotEmpty);

  /// 是否带逐字时间轴。
  bool get wordSynced => lines.any((l) => l.words != null);

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
  const CommentPage({required this.total, required this.comments, this.hasMore = false, this.next});

  final int total;
  final List<Comment> comments;
  final bool hasMore;

  /// 请求下一页时使用的 offset。平台会过滤掉部分评论（只有语音、图片的评论等），或者第一页混排了热门评论，
  /// 已显示的条数不等于平台的分页位置；为 null 时按已显示的条数计算。
  final int? next;
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

  bool get isEmpty => songs.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty && bestSong == null && bestPlaylist == null;
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

  Map<String, dynamic> toJson() => {
    'daily': [for (final s in daily) s.toJson()],
    'playlists': [for (final p in playlists) p.toJson()],
  };

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
  const StreamInfo({this.url, this.headers = const {}, this.trial = false, this.quality, this.gainDb, this.peak, this.cover, this.note});

  final String? url;
  final Map<String, String> headers;
  final bool trial;
  final AudioQuality? quality;

  /// 平台提供的响度增益（dB，类似 ReplayGain），用于音量均衡。
  final double? gainDb;

  /// 平台提供的峰值（线性，1 为满刻度）：桌面端没有限幅器时，按它计算音量增强最多能提升多少而不削波。
  final double? peak;

  /// 取地址时平台一并给出的封面（列表里没有封面的歌曲用它补上）。
  final String? cover;

  /// 给用户的说明（例如只拿到试听片段的原因：登录已失效、需要会员）。
  final String? note;
}

/// 二维码登录凭据。
class QrTicket {
  const QrTicket(this.key, this.content, {this.image, this.app = '网易云音乐 App'});

  final String key;

  /// 需要渲染成二维码的内容。
  final String content;

  /// 平台直接给出的二维码图片（PNG）；有时直接显示，不再渲染 [content]。
  final Uint8List? image;

  /// 用来扫码的 App 名称（显示在二维码下方）。
  final String app;
}

/// 平台会员信息（个人中心显示）。
class Membership {
  const Membership({
    required this.platform,
    required this.title,
    this.active = false,
    this.level,
    this.expires,
    this.benefits = const [],
    this.relogin = false,
  });

  /// 登录凭据已失效或来自旧的登录方式（例如酷狗网页登录、旧版本保存的 QQ 凭据无法续期），
  /// 需要重新扫码登录才能查询会员与播放会员歌曲。
  final bool relogin;

  /// 平台名称，例如“网易云音乐”。
  final String platform;

  /// 会员名称，例如“黑胶 VIP”“豪华绿钻”；未开通时为“未开通会员”。
  final String title;
  final bool active;

  /// 会员等级，例如“Lv.7”。
  final String? level;
  final DateTime? expires;

  /// 当前会员包含的权益（例如“无损音质”“下载会员歌曲”）。
  final List<String> benefits;
}

enum QrState { waiting, scanned, confirmed, expired }
