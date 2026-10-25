import 'package:flutter/foundation.dart';

import '../models.dart';

/// 播放源支持的能力。界面根据能力决定显示哪些入口。
enum SourceFeature {
  dailyRecommend,
  charts,
  newAlbums,
  radio,
  comments,
  postComment,
  lyrics,
  lyricTranslation,
  artist,
  album,
  search,
  hotSearch,
  login,
  qrLogin,
  smsLogin,
  passwordLogin,
  userPlaylists,
  likeSong,
  recentPlays,
  followArtist,
}

class SourceUnsupported implements Exception {
  const SourceUnsupported(this.feature);

  final String feature;

  @override
  String toString() => '当前播放源不支持：$feature';
}

/// 一个音乐平台（播放源）。新增平台只需实现本接口并在 [SourceRegistry] 注册。
///
/// 所有方法默认抛出 [SourceUnsupported]，实现方按能力覆盖。
abstract class MusicSource extends ChangeNotifier {
  /// 唯一标识，会写入 [Song.sourceId]。
  String get id;

  /// 显示名称，例如“网易云音乐”。
  String get name;

  String get description;

  Set<SourceFeature> get features;

  bool supports(SourceFeature f) => features.contains(f);

  /// 初始化（读取本地登录状态等）。
  Future<void> init() async {}

  // ── 账号 ──────────────────────────────────────────
  UserProfile? get user => null;
  bool get loggedIn => user != null;

  Future<QrTicket> createQrLogin() => throw const SourceUnsupported('扫码登录');
  Future<QrState> checkQrLogin(QrTicket ticket) => throw const SourceUnsupported('扫码登录');
  Future<void> sendSmsCode(String phone, {String countryCode = '86'}) => throw const SourceUnsupported('验证码登录');
  Future<void> loginWithSms(String phone, String code, {String countryCode = '86'}) => throw const SourceUnsupported('验证码登录');
  Future<void> loginWithPassword(String account, String password, {String countryCode = '86'}) => throw const SourceUnsupported('密码登录');
  Future<void> logout() async {}

  // ── 发现 ──────────────────────────────────────────
  Future<HomeFeed> homeFeed() => throw const SourceUnsupported('首页推荐');
  Future<List<PlaylistInfo>> recommendPlaylists({int limit = 12}) => throw const SourceUnsupported('推荐歌单');
  Future<List<ChartInfo>> charts() => throw const SourceUnsupported('排行榜');
  Future<PlaylistInfo> soaringChart() => throw const SourceUnsupported('飙升榜');
  Future<List<AlbumInfo>> newAlbums({int limit = 12}) => throw const SourceUnsupported('新碟');
  Future<List<RadioInfo>> hotRadios({int limit = 12}) => throw const SourceUnsupported('电台');
  Future<PlaylistInfo> radioPrograms(RadioInfo radio) => throw const SourceUnsupported('电台');

  // ── 详情 ──────────────────────────────────────────
  Future<PlaylistInfo> playlist(String id) => throw const SourceUnsupported('歌单');
  Future<AlbumInfo> album(String id) => throw const SourceUnsupported('专辑');
  Future<ArtistInfo> artist(String id) => throw const SourceUnsupported('歌手');
  Future<List<AlbumInfo>> artistAlbums(String id, {int limit = 30}) => throw const SourceUnsupported('歌手专辑');
  Future<List<ArtistInfo>> similarArtists(String id) => throw const SourceUnsupported('相似歌手');
  Future<void> followArtist(String id, bool follow) => throw const SourceUnsupported('关注歌手');

  // ── 搜索 ──────────────────────────────────────────
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) => throw const SourceUnsupported('搜索');
  Future<List<HotSearch>> hotSearches() => throw const SourceUnsupported('热搜');

  // ── 播放 ──────────────────────────────────────────
  Future<StreamInfo> stream(Song song, AudioQuality quality);
  Future<Lyrics> lyrics(Song song) async => Lyrics.empty;

  // ── 评论 ──────────────────────────────────────────
  Future<CommentPage> comments(Song song, {CommentSort sort = CommentSort.recommend, int offset = 0}) => throw const SourceUnsupported('评论');
  Future<void> postComment(Song song, String content) => throw const SourceUnsupported('发表评论');
  Future<void> likeComment(Song song, Comment comment, bool like) => throw const SourceUnsupported('点赞评论');

  // ── 我的 ──────────────────────────────────────────
  Future<List<PlaylistInfo>> userPlaylists() => throw const SourceUnsupported('我的歌单');
  Future<List<Song>> recentSongs() => throw const SourceUnsupported('最近播放');
  Future<List<AlbumInfo>> subscribedAlbums() => throw const SourceUnsupported('收藏的专辑');
  Future<List<ArtistInfo>> followedArtists() => throw const SourceUnsupported('关注的歌手');
  Future<Set<String>> likedSongIds() async => const {};
  Future<void> likeSong(Song song, bool like) => throw const SourceUnsupported('喜欢');
}
