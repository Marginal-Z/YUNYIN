import '../../models.dart';
import '../music_source.dart';

/// 演示源：设计稿里的示例内容，离线可用，用于预览界面与无网络环境。
/// 播放为模拟进度（无真实音频）。
class DemoSource extends MusicSource {
  static const sourceId = 'demo';

  @override
  String get id => sourceId;

  @override
  String get name => '演示数据';

  @override
  String get description => '设计稿示例内容 · 离线可用 · 模拟播放';

  @override
  Set<SourceFeature> get features => {
        SourceFeature.dailyRecommend,
        SourceFeature.charts,
        SourceFeature.newAlbums,
        SourceFeature.radio,
        SourceFeature.comments,
        SourceFeature.postComment,
        SourceFeature.lyrics,
        SourceFeature.artist,
        SourceFeature.album,
        SourceFeature.search,
        SourceFeature.hotSearch,
        SourceFeature.userPlaylists,
        SourceFeature.likeSong,
        SourceFeature.recentPlays,
        SourceFeature.followArtist,
        SourceFeature.login,
        SourceFeature.smsLogin,
      };

  UserProfile? _user = const UserProfile(id: 'me', nickname: '云音用户', avatar: 'art:avatarCoral');
  final Set<String> _liked = {'s1'};
  final Set<String> _followed = {};
  final List<Comment> _myComments = [];

  @override
  UserProfile? get user => _user;

  static Song _s(String id, String name, String artistId, String artist, String albumId, String album, String cover, int sec,
          {String? plays}) =>
      Song(
        id: id,
        sourceId: sourceId,
        name: name,
        artists: [ArtistRef(artistId, artist)],
        album: AlbumRef(albumId, album, cover: 'art:$cover'),
        duration: Duration(seconds: sec),
        cover: 'art:$cover',
        playCount: plays,
      );

  static final songs = <String, Song>{
    for (final s in [
      _s('s1', '晚风信箱', 'a1', '沈南乔', 'al1', '夜行列车', 'teal', 248, plays: '4.2 亿次'),
      _s('s2', '港口的灯', 'a2', '阿澈', 'al2', '海岸线', 'coral', 222),
      _s('s3', '慢速旋转', 'a5', '青椒乐队', 'al3', '通宵营业', 'sage', 199, plays: '1.2 亿次'),
      _s('s4', '四月的底片', 'a4', '季然', 'al4', '光圈', 'dots', 241),
      _s('s5', '雨落在站台', 'a6', '周未明', 'al5', '站台', 'arch', 235, plays: '2.9 亿次'),
      _s('s6', '月亮背面', 'a3', '宋清和', 'al6', '背面', 'moon', 266, plays: '2.1 亿次'),
      _s('s7', '海边公路', 'a7', '许栖', 'al7', '公路电台', 'stripes', 217, plays: '1.6 亿次'),
      _s('s8', '通宵营业', 'a5', '青椒乐队', 'al3', '通宵营业', 'stripes', 204),
      _s('s9', '夜行列车', 'a1', '沈南乔', 'al1', '夜行列车', 'teal', 231),
      _s('s10', '晚风里的人', 'a2', '阿澈', 'al2', '海岸线', 'coral', 231),
      _s('s11', '晚风与海', 'a6', '周未明', 'al5', '站台', 'arch', 252),
      _s('s12', '等晚风停', 'a4', '季然', 'al4', '光圈', 'dots', 213),
    ])
      s.id: s,
  };

  static Song song(String id) => songs[id]!;

  static List<Song> list(List<String> ids) => [for (final i in ids) songs[i]!];

  static final _playlists = <String, PlaylistInfo>{
    'p1': PlaylistInfo(
      id: 'p1',
      sourceId: sourceId,
      name: '雨天唱片行',
      cover: 'art:arch',
      trackCount: 36,
      creator: '阿澈',
      tags: const ['民谣'],
      description: '下雨的时候适合听的民谣与慢歌，从站台到海边，一张接一张慢慢放。',
      ownedByMe: true,
      downloaded: true,
      tracks: list(['s1', 's2', 's5', 's4', 's3', 's6', 's7']),
    ),
    'p2': PlaylistInfo(
        id: 'p2', sourceId: sourceId, name: '深夜电台', cover: 'art:moon', trackCount: 52, creator: '云音用户', tags: const ['氛围'], ownedByMe: true,
        tracks: list(['s6', 's9', 's1', 's3'])),
    'p3': PlaylistInfo(
        id: 'p3', sourceId: sourceId, name: '通勤节拍', cover: 'art:stripes', trackCount: 28, creator: '云音用户', tags: const ['电子'], ownedByMe: true,
        tracks: list(['s8', 's3', 's2', 's4'])),
    'p4': PlaylistInfo(
        id: 'p4', sourceId: sourceId, name: '海边公路', cover: 'art:teal', trackCount: 33, creator: '云音用户', tags: const ['流行'], ownedByMe: true,
        tracks: list(['s7', 's2', 's11', 's1'])),
    'p5': PlaylistInfo(
        id: 'p5', sourceId: sourceId, name: '港口的灯', cover: 'art:coral', trackCount: 12, creator: '阿澈', tags: const ['阿澈'],
        tracks: list(['s2', 's10'])),
    'p6': PlaylistInfo(
        id: 'p6', sourceId: sourceId, name: '周末散步', cover: 'art:sage', trackCount: 19, creator: '云音用户', tags: const ['轻音乐'], ownedByMe: true,
        tracks: list(['s3', 's4', 's5'])),
    'p7': PlaylistInfo(
        id: 'p7', sourceId: sourceId, name: '晚风合集', cover: 'art:coral', trackCount: 42, creator: '云音编辑部',
        tracks: list(['s1', 's10', 's11', 's12'])),
    'liked': PlaylistInfo(
        id: 'liked', sourceId: sourceId, name: '我喜欢的音乐', cover: 'art:teal', trackCount: 128, creator: '云音用户', isLikedList: true, ownedByMe: true,
        tracks: list(['s1', 's6', 's5'])),
  };

  static const _artists = <String, (String, String, int)>{
    'a1': ('沈南乔', 'art:avatarCoral', 1286000),
    'a2': ('阿澈', 'art:avatarBlue', 932000),
    'a3': ('宋清和', 'art:avatarYellow', 641000),
    'a4': ('季然', 'art:avatarTeal', 518000),
    'a5': ('青椒乐队', 'art:avatarYellow', 402000),
    'a6': ('周未明', 'art:avatarBlue', 377000),
    'a7': ('许栖', 'art:avatarTeal', 210000),
  };

  static AlbumInfo _albumInfo(String id) {
    final s = songs.values.firstWhere((s) => s.album?.id == id);
    return AlbumInfo(
      id: id,
      sourceId: sourceId,
      name: s.album!.name,
      cover: s.cover,
      artist: s.artists.first,
      songs: songs.values.where((x) => x.album?.id == id).toList(),
      publishTime: DateTime(2026, 9, 18),
      size: songs.values.where((x) => x.album?.id == id).length,
    );
  }

  Future<T> _delay<T>(T v) => Future.delayed(const Duration(milliseconds: 160), () => v);

  @override
  Future<HomeFeed> homeFeed() => _delay(HomeFeed(
        daily: list(['s1', 's2', 's3', 's4', 's5', 's6', 's7']),
        playlists: [for (final k in ['p1', 'p2', 'p3', 'p4', 'p5', 'p6']) _playlists[k]!],
        radar: PlaylistInfo(id: 'radar', sourceId: sourceId, name: '私人雷达', cover: 'art:teal', tracks: list(['s10', 's11', 's12', 's9'])),
      ));

  @override
  Future<List<PlaylistInfo>> recommendPlaylists({int limit = 12}) =>
      _delay([for (final k in ['p1', 'p2', 'p3', 'p4', 'p5', 'p6']) _playlists[k]!]);

  @override
  Future<PlaylistInfo> soaringChart() => _delay(PlaylistInfo(
        id: 'chart',
        sourceId: sourceId,
        name: '飙升榜',
        cover: 'art:coral',
        kind: PlaylistKind.chart,
        tracks: list(['s2', 's6', 's8', 's3', 's5', 's1', 's4']),
      ));

  @override
  Future<List<ChartInfo>> charts() => _delay(const [
        ChartInfo(id: 'chart', name: '飙升榜', cover: 'art:coral', update: '每天更新', preview: ['港口的灯 - 阿澈', '月亮背面 - 宋清和', '通宵营业 - 青椒乐队']),
        ChartInfo(id: 'p7', name: '新歌榜', cover: 'art:teal', update: '每天更新', preview: ['晚风信箱 - 沈南乔', '晚风里的人 - 阿澈', '晚风与海 - 周未明']),
        ChartInfo(id: 'p1', name: '民谣榜', cover: 'art:arch', update: '每周四更新', preview: ['雨落在站台 - 周未明', '四月的底片 - 季然', '慢速旋转 - 青椒乐队']),
      ]);

  @override
  Future<List<AlbumInfo>> newAlbums({int limit = 12}) =>
      _delay([for (final id in ['al2', 'al1', 'al3', 'al4', 'al5', 'al6', 'al7']) _albumInfo(id)]);

  @override
  Future<List<RadioInfo>> hotRadios({int limit = 12}) => _delay(const [
        RadioInfo(id: 'r1', sourceId: sourceId, name: '深夜电台', cover: 'art:moon', host: '宋清和', programCount: 128, category: '情感'),
        RadioInfo(id: 'r2', sourceId: sourceId, name: '公路电台', cover: 'art:stripes', host: '许栖', programCount: 64, category: '旅行'),
        RadioInfo(id: 'r3', sourceId: sourceId, name: '站台广播', cover: 'art:arch', host: '周未明', programCount: 42, category: '音乐故事'),
      ]);

  @override
  Future<PlaylistInfo> radioPrograms(RadioInfo radio) => _delay(PlaylistInfo(
        id: radio.id,
        sourceId: sourceId,
        name: radio.name,
        cover: radio.cover,
        creator: radio.host,
        kind: PlaylistKind.radio,
        tracks: list(['s6', 's9', 's7']),
      ));

  @override
  Future<PlaylistInfo> playlist(String id) async {
    if (id == 'chart') return soaringChart();
    if (id == 'liked') {
      return _delay(_playlists['liked']!.withTracks([for (final i in _liked) songs[i]!]));
    }
    final p = _playlists[id];
    if (p == null) throw Exception('歌单不存在');
    return _delay(p);
  }

  @override
  Future<AlbumInfo> album(String id) => _delay(_albumInfo(id));

  @override
  Future<ArtistInfo> artist(String id) {
    final a = _artists[id] ?? ('未知歌手', 'art:avatarCoral', 0);
    final hot = id == 'a1'
        ? list(['s1', 's5', 's6', 's7', 's3'])
        : songs.values.where((s) => s.artists.any((x) => x.id == id)).toList();
    return _delay(ArtistInfo(
      id: id,
      sourceId: sourceId,
      name: a.$1,
      avatar: a.$2,
      fans: a.$3,
      hotSongs: hot,
      followed: _followed.contains(id),
      description: '独立音乐人，作品多围绕城市夜晚与旅途。',
    ));
  }

  @override
  Future<List<AlbumInfo>> artistAlbums(String id, {int limit = 30}) => _delay([
        for (final al in songs.values.where((s) => s.artists.any((a) => a.id == id)).map((s) => s.album!.id).toSet()) _albumInfo(al),
      ]);

  @override
  Future<List<ArtistInfo>> similarArtists(String id) => _delay([
        for (final e in _artists.entries.where((e) => e.key != id).take(4))
          ArtistInfo(id: e.key, sourceId: sourceId, name: e.value.$1, avatar: e.value.$2, fans: e.value.$3),
      ]);

  @override
  Future<void> followArtist(String id, bool follow) async {
    follow ? _followed.add(id) : _followed.remove(id);
  }

  @override
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) {
    final k = keyword.trim();
    final matched = songs.values
        .where((s) => s.name.contains(k) || s.artistText.contains(k) || s.albumName.contains(k))
        .toList();
    final result = matched.isEmpty && k.isNotEmpty ? <Song>[] : matched;
    final artistList = [
      for (final e in _artists.entries)
        if (k.isEmpty || e.value.$1.contains(k) || result.any((s) => s.artists.any((a) => a.id == e.key)))
          ArtistInfo(id: e.key, sourceId: sourceId, name: e.value.$1, avatar: e.value.$2, fans: e.value.$3),
    ];
    final albums = {for (final s in result) s.album!.id}.map(_albumInfo).toList();
    final pls = _playlists.values.where((p) => p.name.contains(k) || (p.tracks ?? []).any(result.contains)).toList();
    if (k == '晚风') {
      return _delay(SearchResult(
        songs: list(['s1', 's10', 's11', 's12']),
        bestSong: song('s1'),
        bestPlaylist: _playlists['p7'],
        artists: [for (final a in ['a1', 'a2', 'a3', 'a4']) ArtistInfo(id: a, sourceId: sourceId, name: _artists[a]!.$1, avatar: _artists[a]!.$2)],
        albums: [
          _albumInfo('al1'),
          AlbumInfo(id: 'al3', sourceId: sourceId, name: '晚风集', cover: 'art:stripes', artist: const ArtistRef('a5', '青椒乐队')),
          _albumInfo('al2'),
          AlbumInfo(id: 'al4', sourceId: sourceId, name: '光圈', cover: 'art:sage', artist: const ArtistRef('a4', '季然')),
          _albumInfo('al5'),
          _albumInfo('al6'),
        ],
        playlists: [_playlists['p7']!, _playlists['p1']!],
        songCount: 4,
      ));
    }
    return _delay(SearchResult(
      songs: result,
      bestSong: result.firstOrNull,
      bestPlaylist: pls.firstOrNull,
      artists: artistList.take(4).toList(),
      albums: albums,
      playlists: pls,
      songCount: result.length,
    ));
  }

  @override
  Future<List<HotSearch>> hotSearches() => _delay(const [
        HotSearch('晚风信箱', score: 1280000, tag: 'hot'),
        HotSearch('港口的灯', score: 960000, tag: 'new'),
        HotSearch('慢速旋转', score: 880000),
        HotSearch('四月的底片', score: 740000, tag: 'up'),
        HotSearch('雨落在站台', score: 660000),
        HotSearch('月亮背面', score: 590000),
        HotSearch('海边公路', score: 510000),
        HotSearch('夜行列车', score: 470000),
      ]);

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async => const StreamInfo(simulated: true);

  static const _lyric = [
    '站台的钟停在十一点半',
    '站台很长 风也很长',
    '我把没寄出的信折进口袋',
    '晚风把信投进站台的灯',
    '你在末班车上读了一半',
    '光落在你抬头的地方',
    '我数着回家的每一个路口',
    '别回头 别让夜晚听见我',
    '字迹被雨水轻轻晕开',
    '像一座没有名字的城',
    '我把名字折成纸船',
    '放进凌晨的第一班风',
  ];

  @override
  Future<Lyrics> lyrics(Song song) => _delay(Lyrics([
        for (var i = 0; i < _lyric.length; i++)
          LyricLine(Duration(milliseconds: 4000 + i * (song.duration.inMilliseconds - 8000) ~/ _lyric.length), _lyric[i]),
      ]));

  static final _comments = [
    Comment(id: 'c1', userName: '夜航船', avatar: 'art:avatarCoral', content: '第一次听就想起了小时候的末班车，站台的灯真的像信箱。',
        time: DateTime.now().subtract(const Duration(hours: 2)), location: '上海', likedCount: 24000, replyCount: 36),
    Comment(id: 'c2', userName: '小满', avatar: 'art:avatarBlue', content: '“晚风把信投进站台的灯”这一句，循环了一整晚。',
        time: DateTime.now().subtract(const Duration(days: 1)), location: '成都', likedCount: 18000, replyCount: 21),
    Comment(id: 'c3', userName: '林间', avatar: 'art:avatarYellow', content: '编曲里的钢琴太干净了，耳机党狂喜。',
        time: DateTime.now().subtract(const Duration(days: 3)), location: '杭州', likedCount: 9802, replyCount: 8),
    Comment(id: 'c4', userName: '阿默', avatar: 'art:avatarTeal', content: '雨天配这首，刚刚好。',
        time: DateTime.now().subtract(const Duration(days: 7)), location: '广州', likedCount: 6317, replyCount: 4),
  ];

  @override
  Future<CommentPage> comments(Song song, {CommentSort sort = CommentSort.recommend, int offset = 0}) {
    var list = [..._myComments, ..._comments];
    if (sort == CommentSort.hot) list.sort((a, b) => b.likedCount.compareTo(a.likedCount));
    if (sort == CommentSort.latest) list.sort((a, b) => (b.time ?? DateTime(0)).compareTo(a.time ?? DateTime(0)));
    return _delay(CommentPage(total: 23418 + _myComments.length, comments: offset == 0 ? list : const []));
  }

  @override
  Future<void> postComment(Song song, String content) async {
    _myComments.insert(0, Comment(id: 'm${_myComments.length}', userName: _user?.nickname ?? '云音用户', avatar: 'art:avatarCoral', content: content, time: DateTime.now(), location: '本地'));
  }

  @override
  Future<void> likeComment(Song song, Comment comment, bool like) async {}

  @override
  Future<List<PlaylistInfo>> userPlaylists() => _delay([
        _playlists['liked']!,
        for (final k in ['p1', 'p2', 'p3', 'p6', 'p4']) _playlists[k]!,
        _playlists['p7']!,
        _playlists['p5']!,
      ]);

  @override
  Future<List<Song>> recentSongs() => _delay(list(['s1', 's2', 's3', 's4']));

  @override
  Future<List<AlbumInfo>> subscribedAlbums() => _delay([for (final id in ['al1', 'al2', 'al5', 'al4']) _albumInfo(id)]);

  @override
  Future<List<ArtistInfo>> followedArtists() => _delay([
        for (final id in {'a1', 'a2', 'a3', 'a4', ..._followed})
          ArtistInfo(id: id, sourceId: sourceId, name: _artists[id]!.$1, avatar: _artists[id]!.$2, fans: _artists[id]!.$3, followed: true),
      ]);

  @override
  Future<Set<String>> likedSongIds() async => {..._liked};

  @override
  Future<void> likeSong(Song song, bool like) async {
    like ? _liked.add(song.id) : _liked.remove(song.id);
  }

  @override
  Future<void> sendSmsCode(String phone, {String countryCode = '86'}) async {}

  @override
  Future<void> loginWithSms(String phone, String code, {String countryCode = '86'}) async {
    _user = const UserProfile(id: 'me', nickname: '云音用户', avatar: 'art:avatarCoral');
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    _user = null;
    notifyListeners();
  }
}
