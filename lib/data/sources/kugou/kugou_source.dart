import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/text_decode.dart';
import '../../models.dart';
import '../music_source.dart';
import '../netease/netease_source.dart' show parseLrc;

/// 酷狗音乐播放源：搜索、热搜、排行榜、歌单、专辑、歌手、评论、封面与歌词来自酷狗公开接口。
///
/// 酷狗的播放地址接口要求设备验证与会员；取不到地址时给出酷狗返回的原因。
class KugouSource extends MusicSource {
  KugouSource({Dio? dio})
    : _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15), responseType: ResponseType.plain));

  static const sourceId = 'kugou';
  static const _api = 'https://mobiles.kugou.com/api/v3';

  final Dio _dio;
  String _deviceId = md5.convert(utf8.encode('${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextDouble()}')).toString();

  @override
  String get id => sourceId;

  @override
  String get name => '酷狗音乐';

  @override
  String get description => '酷狗的搜索、排行榜与歌词';

  @override
  Set<SourceFeature> get features => const {
    SourceFeature.search,
    SourceFeature.hotSearch,
    SourceFeature.charts,
    SourceFeature.playlistCategories,
    SourceFeature.newAlbums,
    SourceFeature.lyrics,
    SourceFeature.dailyRecommend,
    SourceFeature.artist,
    SourceFeature.album,
    SourceFeature.comments,
    SourceFeature.login,
    SourceFeature.cookieLogin,
  };

  // ── 账号 ──────────────────────────────────────────
  //
  // 酷狗的登录接口需要客户端签名，云音不模拟这些请求：在酷狗官方登录页（应用内网页）登录，
  // 或从浏览器复制登录后的 Cookie。登录信息保存在 KuGoo Cookie 中（KugooID、t、NickName、Pic）。

  static const _prefsKey = 'kugou.account';
  Map<String, String>? _account;
  UserProfile? _user;

  @override
  UserProfile? get user => _user;

  @override
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('kugou.deviceId') ?? _deviceId;
      await prefs.setString('kugou.deviceId', _deviceId);
      final raw = prefs.getString(_prefsKey);
      if (raw != null) _setAccount(Map<String, String>.from(jsonDecode(raw) as Map));
    } catch (e) {
      debugPrint('kugou account: $e');
    }
  }

  void _setAccount(Map<String, String>? a) {
    if (a != null && ((a['KugooID'] ?? '').isEmpty || a['KugooID'] == '0' || (a['t'] ?? '').isEmpty)) {
      throw const FormatException('酷狗账号信息不完整，请重新登录');
    }
    _account = a;
    _user = a == null
        ? null
        : UserProfile(
            id: a['KugooID']!,
            nickname: (a['NickName'] ?? '').isEmpty ? '酷狗用户 ${a['KugooID']}' : a['NickName']!,
            avatar: (a['Pic'] ?? '').replaceFirst('http://', 'https://').ifEmpty(null),
          );
  }

  /// 解析 Cookie：可以是整段 Cookie 头，也可以只是 KuGoo 的值。值中的中文使用 %uXXXX 编码。
  static Map<String, String>? parseKugooCookie(String cookie) {
    if (cookie.contains('\r') || cookie.contains('\n')) return null;
    var text = cookie.trim();
    final m = RegExp(r'(?:^|;\s*)KuGoo=([^;]+)').firstMatch(text);
    if (m != null) text = m.group(1)!;
    final out = <String, String>{};
    for (final part in text.split('&')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      out[part.substring(0, i).trim()] = _unescape(part.substring(i + 1).trim());
    }
    final id = out['KugooID'] ?? '';
    if (id.isEmpty || id == '0' || (out['t'] ?? '').isEmpty) return null;
    // 原样保存 KuGoo 的值，请求时原样带回（各字段的编码保持不变）。
    out['_raw'] = text;
    final cookies = <String, String>{};
    for (final part in cookie.split(';')) {
      final equal = part.indexOf('=');
      if (equal > 0) cookies[part.substring(0, equal).trim()] = part.substring(equal + 1).trim();
    }
    final mid = cookies['kg_mid'] ?? cookies['kg_mid_temp'];
    if (mid != null && mid.isNotEmpty) out['_mid'] = mid;
    final dfid = cookies['kg_dfid'];
    if (dfid != null && dfid.isNotEmpty) out['_dfid'] = dfid;
    return out;
  }

  /// JavaScript escape() 的逆操作：%uXXXX 与 %XX。
  static String _unescape(String s) {
    final u = s.replaceAllMapped(RegExp(r'%u([0-9a-fA-F]{4})'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
    try {
      return Uri.decodeComponent(u);
    } catch (_) {
      return u.replaceAllMapped(RegExp(r'%([0-9a-fA-F]{2})'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
    }
  }

  @override
  Future<void> loginWithCookie(String cookie) async {
    final a = parseKugooCookie(cookie);
    if (a == null) throw Exception('没有找到酷狗的登录信息（需要包含 KuGoo 的 Cookie）');
    _setAccount(a);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(a));
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    _setAccount(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }

  @override
  Future<Membership?> membership() async {
    if (_account == null) return null;
    // Cookie 中没有会员信息，查询会员需要签名接口；在个人中心说明到期时间请在酷狗 App 中查看。
    return const Membership(platform: '酷狗音乐', title: '已登录', benefits: ['会员歌曲按账号权限播放', '免费歌曲直接播放']);
  }

  /// 酷狗榜单的分类（rank/list 返回的 classify）。
  static const _rankGroups = {1: '酷狗榜', 2: '地区榜', 3: '特色榜', 4: '全球榜', 5: '曲风榜'};

  /// 榜单 ID → 名称，打开榜单详情时显示（来自 [charts]）。
  final _rankNames = <String, String>{};

  Future<Map<String, dynamic>> _get(String url) async {
    final res = await _dio.get<String>(url, options: Options(headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) YunYin'}));
    // 部分接口返回的文字里有未转义的控制字符，宽松解析。
    final body = (res.data ?? '').replaceAll(RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f]'), ' ');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  static String? _cover(String? template, [int size = 400]) {
    if (template == null || template.isEmpty) return null;
    return template.replaceAll('{size}', '$size').replaceFirst('http://', 'https://');
  }

  /// 酷狗歌曲：id 编码为“hash:album_audio_id:album_id”，播放与歌词都需要。
  Song _song(Map<String, dynamic> j) {
    final hash = '${j['hash'] ?? j['FileHash'] ?? ''}'.toLowerCase();
    final audio = '${j['album_audio_id'] ?? j['MixSongID'] ?? ''}';
    final albumId = '${j['album_id'] ?? j['AlbumID'] ?? ''}';
    var name = '${j['songname'] ?? j['SongName'] ?? ''}'.trim();
    var singer = '${j['singername'] ?? j['SingerName'] ?? ''}'.trim();
    final filename = '${j['filename'] ?? ''}';
    if ((name.isEmpty || singer.isEmpty) && filename.contains(' - ')) {
      final i = filename.indexOf(' - ');
      singer = singer.isEmpty ? filename.substring(0, i).trim() : singer;
      name = name.isEmpty ? filename.substring(i + 3).trim() : name;
    }
    final cover = _cover(j['album_sizable_cover'] as String? ?? (j['trans_param'] is Map ? j['trans_param']['union_cover'] as String? : null));
    final albumName = '${j['album_name'] ?? j['AlbumName'] ?? ''}';
    final seconds = int.tryParse('${j['duration'] ?? j['Duration'] ?? 0}') ?? 0;
    return Song(
      id: '$hash:$audio:$albumId',
      sourceId: sourceId,
      name: name.isEmpty ? filename : name,
      artists: [
        for (final a in singer.split(RegExp(r'\s*[、/]\s*')))
          if (a.isNotEmpty) ArtistRef('kugou:$a', a),
      ],
      album: albumName.isEmpty && cover == null ? null : AlbumRef(albumId, albumName, cover: cover),
      duration: Duration(seconds: seconds),
      cover: cover,
      // privilege 为 10（或需要音乐包）的是会员歌曲。
      vip: j['privilege'] == 10 || (j['trans_param'] is Map && j['trans_param']['musicpack_advance'] == 1),
    );
  }

  ({String hash, String audio, String album}) _ids(Song s) {
    final p = s.id.split(':');
    return (hash: p.first, audio: p.length > 1 ? p[1] : '', album: p.length > 2 ? p[2] : '');
  }

  // ── 搜索 ──────────────────────────────────────────

  @override
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) async {
    final page = offset ~/ limit + 1;
    final kw = Uri.encodeQueryComponent(keyword);
    Future<List<Map<String, dynamic>>> list(String kind, int size, {bool flat = false}) async {
      final j = await _get('$_api/search/$kind?format=json&keyword=$kw&page=$page&pagesize=$size&showtype=1');
      final data = j['data'];
      // 歌手搜索的 data 直接是列表，其余为 {info: [...]}。
      final items = flat ? data : (data is Map ? data['info'] : null);
      return (items is List ? items : const []).cast<Map<String, dynamic>>();
    }

    Future<List<Song>> songs() async => [for (final x in await list('song', limit)) _song(x)];
    // 歌手搜索不返回头像：并行查询每位歌手的资料补上头像（取不到时界面显示名字首字）。
    Future<List<ArtistInfo>> artists(int size) async {
      final found = await list('singer', size, flat: true);
      return Future.wait([
        for (final a in found)
          _get('$_api/singer/info?singerid=${a['singerid']}&plat=0')
              .then((j) => _cover((j['data'] as Map?)?['imgurl'] as String?, 240))
              .timeout(const Duration(seconds: 4))
              .catchError((Object _) => null)
              .then((avatar) => ArtistInfo(id: '${a['singerid']}', sourceId: sourceId, name: '${a['singername']}', avatar: avatar)),
      ]);
    }

    Future<List<AlbumInfo>> albums(int size) async => [for (final a in await list('album', size)) _album(a)];
    Future<List<PlaylistInfo>> playlists(int size) async => [for (final p in await list('special', size)) _special(p)];
    switch (type) {
      case SearchType.song:
        final s = await songs();
        return SearchResult(songs: s, bestSong: s.firstOrNull);
      case SearchType.artist:
        return SearchResult(artists: await artists(limit));
      case SearchType.album:
        return SearchResult(albums: await albums(limit));
      case SearchType.playlist:
        return SearchResult(playlists: await playlists(limit));
      case SearchType.all:
        final r = await Future.wait([
          songs(),
          artists(4).then((a) => a.take(4).toList()).catchError((Object _) => <ArtistInfo>[]),
          albums(6).catchError((Object _) => <AlbumInfo>[]),
          playlists(6).catchError((Object _) => <PlaylistInfo>[]),
        ]);
        final s = r[0] as List<Song>;
        final pls = r[3] as List<PlaylistInfo>;
        return SearchResult(
          songs: s,
          artists: r[1] as List<ArtistInfo>,
          albums: r[2] as List<AlbumInfo>,
          playlists: pls,
          bestSong: s.firstOrNull,
          bestPlaylist: pls.firstOrNull,
        );
    }
  }

  AlbumInfo _album(Map a) => AlbumInfo(
    id: '${a['albumid']}',
    sourceId: sourceId,
    name: '${a['albumname'] ?? ''}',
    cover: _cover(a['imgurl'] as String?),
    artist: ArtistRef('kugou:${a['singername'] ?? ''}', '${a['singername'] ?? ''}'),
    publishTime: DateTime.tryParse('${a['publishtime'] ?? ''}'.replaceFirst(' ', 'T')),
    description: (a['intro'] as String?)?.trim(),
    size: (a['songcount'] as num?)?.toInt() ?? 0,
  );

  PlaylistInfo _special(Map p) => PlaylistInfo(
    id: 'special:${p['specialid']}',
    sourceId: sourceId,
    name: '${p['specialname'] ?? ''}',
    cover: _cover(p['imgurl'] as String?),
    creator: '${p['username'] ?? p['nickname'] ?? ''}',
    description: (p['intro'] as String?)?.trim(),
    playCount: (p['playcount'] as num?)?.toInt() ?? 0,
    trackCount: (p['songcount'] as num?)?.toInt() ?? 0,
  );

  @override
  Future<List<HotSearch>> hotSearches() async {
    final j = await _get('$_api/search/hot?format=json&plat=0&count=20');
    final info = ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>();
    return [for (final x in info) HotSearch('${x['keyword']}')];
  }

  // ── 排行榜与首页 ──────────────────────────────────────

  /// 榜单歌曲。酷狗每页最多 100 首，TOP500 等长榜单并行读取其余各页。
  Future<List<Song>> _rank(String rankId, {int size = 100, int max = 500}) async {
    Future<Map<String, dynamic>> page(int n) => _get('$_api/rank/song?rankid=$rankId&page=$n&pagesize=$size&area_code=1&plat=2&version=9108');
    List<Song> songs(Map<String, dynamic> j) => [for (final x in ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>()) _song(x)];
    final first = await page(1);
    final out = songs(first);
    final total = math.min(max, ((first['data'] as Map?)?['total'] as num?)?.toInt() ?? 0);
    if (size < 100 || out.length >= total) return out;
    final rest = await Future.wait([for (var n = 2; (n - 1) * size < total; n++) page(n).then(songs).catchError((Object _) => <Song>[])]);
    final seen = {for (final s in out) s.id};
    for (final list in rest) {
      out.addAll(list.where((s) => seen.add(s.id)));
    }
    return out;
  }

  @override
  Future<PlaylistInfo> playlist(String id) async {
    if (id.startsWith('special:')) return _specialDetail(id.substring(8));
    final rankId = id.startsWith('rank:') ? id.substring(5) : id;
    if (!_rankNames.containsKey(rankId)) await charts().catchError((Object _) => <ChartInfo>[]);
    final songs = await _rank(rankId);
    return PlaylistInfo(
      id: 'rank:$rankId',
      sourceId: sourceId,
      name: _rankNames[rankId] ?? '酷狗榜单',
      cover: songs.firstOrNull?.coverUrl,
      creator: '酷狗音乐',
      trackCount: songs.length,
      kind: PlaylistKind.chart,
      tracks: songs,
    );
  }

  @override
  Future<PlaylistInfo> soaringChart() => playlist('rank:6666');

  @override
  Future<List<ChartInfo>> charts() async {
    final j = await _get('$_api/rank/list?version=9108&plat=0&showtype=2&parentid=0&apiver=6&area_code=1&withsong=0');
    final info = ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map>();
    final out = <ChartInfo>[];
    for (final classify in _rankGroups.keys) {
      for (final r in info.where((r) => r['classify'] == classify)) {
        final id = '${r['rankid']}';
        _rankNames[id] = '${r['rankname']}';
        out.add(
          ChartInfo(
            id: 'rank:$id',
            name: '${r['rankname']}',
            cover: _cover(r['imgurl'] as String?),
            update: '${r['update_frequency'] ?? ''}'.trim().ifEmpty(null),
            group: _rankGroups[classify],
            preview: ['${r['intro'] ?? ''}'.trim()].where((t) => t.isNotEmpty).toList(),
          ),
        );
      }
    }
    return out;
  }

  @override
  Future<List<PlaylistCategory>> playlistCategories() async {
    final j = await _get('$_api/category/list?pid=0&apiver=2&plat=0');
    return [
      const PlaylistCategory(id: '0', name: '推荐'),
      for (final c in ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map>())
        PlaylistCategory(id: '${c['categoryid']}', name: '${c['categoryname']}', group: '分类'),
    ];
  }

  @override
  Future<List<PlaylistInfo>> categoryPlaylists(String categoryId, {int offset = 0, int limit = 30}) async {
    final j = await _get('$_api/category/special?categoryid=$categoryId&page=${offset ~/ limit + 1}&pagesize=$limit&withsong=0&sort=2&plat=2');
    return [for (final p in ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map>()) _special(p)];
  }

  @override
  Future<List<AlbumInfo>> newAlbums({int limit = 12}) async {
    final j = await _get('$_api/album/list?plat=0&page=1&pagesize=$limit&type=1');
    return [for (final a in ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map>()) _album(a)];
  }

  /// 推荐歌单：歌单广场按热度排序。
  @override
  Future<List<PlaylistInfo>> recommendPlaylists({int limit = 12}) => categoryPlaylists('0', limit: limit);

  Future<PlaylistInfo> _specialDetail(String specialId) async {
    final results = await Future.wait([
      _get('$_api/special/song?specialid=$specialId&page=1&pagesize=300&plat=2&version=9108'),
      _get('$_api/special/info?specialid=$specialId&plat=2').catchError((Object _) => <String, dynamic>{}),
    ]);
    final songs = [for (final x in ((results[0]['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>()) _song(x)];
    final info = results[1]['data'] as Map? ?? const {};
    return PlaylistInfo(
      id: 'special:$specialId',
      sourceId: sourceId,
      name: '${info['specialname'] ?? '酷狗歌单'}',
      cover: _cover(info['imgurl'] as String?) ?? songs.firstOrNull?.coverUrl,
      creator: '${info['nickname'] ?? info['username'] ?? ''}',
      description: (info['intro'] as String?)?.trim(),
      playCount: (info['playcount'] as num?)?.toInt() ?? 0,
      trackCount: songs.length,
      tracks: songs,
    );
  }

  @override
  Future<HomeFeed> homeFeed() async {
    final results = await Future.wait([_rank('6666', size: 30), recommendPlaylists(limit: 12)]);
    return HomeFeed(daily: results[0] as List<Song>, playlists: results[1] as List<PlaylistInfo>);
  }

  // ── 专辑与歌手 ──────────────────────────────────────

  @override
  Future<AlbumInfo> album(String id) async {
    final r = await Future.wait([_get('$_api/album/info?albumid=$id&plat=0'), _get('$_api/album/song?albumid=$id&page=1&pagesize=200&plat=2&version=9108')]);
    final info = r[0]['data'] as Map? ?? const {};
    final songs = [for (final x in ((r[1]['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>()) _song(x)];
    final a = _album({...info, 'albumid': id});
    return AlbumInfo(
      id: id,
      sourceId: sourceId,
      name: a.name,
      cover: a.cover ?? songs.firstOrNull?.coverUrl,
      artist: a.artist,
      publishTime: a.publishTime,
      description: a.description,
      songs: songs,
      size: songs.length,
    );
  }

  /// 歌曲里的歌手只有名字（id 为“kugou:名字”）：按名字搜索出歌手 id。
  Future<String> _singerId(String id) async {
    if (!id.startsWith('kugou:')) return id;
    final r = await search(id.substring(6), type: SearchType.artist, limit: 1);
    final found = r.artists.firstOrNull;
    if (found == null) throw Exception('没有找到这位歌手');
    return found.id;
  }

  @override
  Future<ArtistInfo> artist(String id) async {
    final singerId = await _singerId(id);
    final r = await Future.wait([
      _get('$_api/singer/info?singerid=$singerId&plat=0'),
      _get('$_api/singer/song?singerid=$singerId&page=1&pagesize=50&plat=2&version=9108'),
    ]);
    final info = r[0]['data'] as Map? ?? const {};
    final songs = [for (final x in ((r[1]['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>()) _song(x)];
    return ArtistInfo(
      id: singerId,
      sourceId: sourceId,
      name: '${info['singername'] ?? ''}',
      avatar: _cover(info['imgurl'] as String?),
      description: ((info['intro'] ?? info['profile']) as String?)?.trim(),
      hotSongs: songs,
    );
  }

  @override
  Future<List<AlbumInfo>> artistAlbums(String id, {int limit = 30}) async {
    final singerId = await _singerId(id);
    final j = await _get('$_api/singer/album?singerid=$singerId&page=1&pagesize=$limit&plat=0');
    return [for (final a in ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map>()) _album(a)];
  }

  // ── 评论 ──────────────────────────────────────────

  @override
  Future<CommentPage> comments(Song song, {CommentSort sort = CommentSort.recommend, int offset = 0}) async {
    const size = 20;
    final hash = _ids(song).hash.toUpperCase();
    final j = await _get(
      'https://mcomment.kugou.com/index.php?r=commentsv2/getCommentWithLike&code=fc4be23b4e972707f36b8a828a93ba8a&extdata=$hash&p=${offset ~/ size + 1}&pagesize=$size',
    );
    // 热门评论在第一页的 weightList 中（有时为空字符串），其余为按时间排列的 list。
    final hot = j['weightList'] is List ? (j['weightList'] as List).cast<Map>() : const <Map>[];
    final latest = (j['list'] as List? ?? const []).cast<Map>();
    final source = sort == CommentSort.latest || offset > 0 || hot.isEmpty ? latest : hot;
    final comments = [
      for (final c in source)
        if ('${c['content'] ?? ''}'.trim().isNotEmpty)
          Comment(
            id: '${c['id']}',
            userName: '${c['user_name'] ?? ''}',
            avatar: (c['user_pic'] as String? ?? '').replaceFirst('http://', 'https://').ifEmpty(null),
            content: '${c['content']}'.trim(),
            time: DateTime.tryParse('${c['addtime'] ?? ''}'.replaceFirst(' ', 'T')),
            likedCount: ((c['like'] as Map?)?['likenum'] as num?)?.toInt() ?? 0,
            replyCount: (c['reply_num'] as num?)?.toInt() ?? 0,
          ),
    ];
    final total = (j['count'] as num?)?.toInt() ?? comments.length;
    return CommentPage(total: total, comments: comments, hasMore: offset + latest.length < total && latest.isNotEmpty);
  }

  // ── 播放 ──────────────────────────────────────────

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async {
    return _webPlayInfo(song);
  }

  Future<StreamInfo> _webPlayInfo(Song song) async {
    const key = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
    final ids = _ids(song);
    if (ids.hash.isEmpty) throw Exception('这首歌缺少酷狗播放标识');
    final mid = _account?['_mid'] ?? _deviceId;
    final dfid = _account?['_dfid'] ?? '-';
    final params = <String, String>{
      'srcappid': '2919',
      'clientver': '20000',
      'clienttime': '${DateTime.now().millisecondsSinceEpoch}',
      'mid': mid,
      'uuid': mid,
      'dfid': dfid,
      'appid': '1014',
      'platid': '4',
      'hash': ids.hash,
      'album_id': ids.album.isEmpty ? '0' : ids.album,
      'album_audio_id': ids.audio,
      'token': _account?['t'] ?? '',
      'userid': _account?['KugooID'] ?? '0',
    };
    final keys = params.keys.toList()..sort();
    params['signature'] = md5.convert(utf8.encode('$key${keys.map((k) => '$k=${params[k]}').join()}$key')).toString();
    final res = await _dio.get<String>(
      'https://wwwapi.kugou.com/play/songinfo',
      queryParameters: params,
      options: Options(
        headers: {
          'Cookie': 'kg_mid=$mid; kg_dfid=$dfid${_account == null ? '' : '; KuGoo=${_account!['_raw'] ?? ''}'}',
          'User-Agent': 'Mozilla/5.0',
          'Referer': 'https://www.kugou.com/',
        },
        receiveTimeout: const Duration(seconds: 6),
      ),
    );
    final j = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
    final data = j['data'];
    final code = j['err_code'] ?? j['error_code'] ?? j['errcode'];
    if ('$code' == '30020' && data is Map) {
      if ('${data['is_publish']}' == '0' || '${data['privilege']}' == '5') {
        throw Exception('酷狗暂不允许播放这首歌（错误码 30020），请在酷狗官方客户端查看歌曲状态');
      }
      final event = '${data['SSA-CODE'] ?? res.headers.value('SSA-CODE') ?? ''}';
      final challengeMid = '${data['SSA-HMID'] ?? res.headers.value('SSA-HMID') ?? mid}';
      if (event.isNotEmpty) {
        final songUrl = Uri.https('www.kugou.com', '/song/', {'hash': ids.hash, 'album_id': ids.album, 'album_audio_id': ids.audio}).toString();
        final fragment = '/index/${[event, '1014', songUrl, challengeMid].map(Uri.encodeComponent).join('/')}';
        throw SourceVerificationRequired(
          message: '酷狗要求人机验证（错误码 30020）。请打开官方验证页完成验证，返回后重新点播放；若仍失败，请在酷狗官网播放一次并重新导入完整 Cookie（含 kg_mid、kg_dfid）。',
          url: Uri.parse('https://h5.kugou.com/apps/verify-h5/dist/').replace(fragment: fragment),
        );
      }
    }
    if (data is Map && '${j['status']}' == '1') {
      final candidates = [data['play_url'], data['play_backup_url']].expand((value) => value is List ? value : [value]);
      for (final value in candidates) {
        final url = value is String ? Uri.tryParse(value.trim()) : null;
        if (url == null || (url.scheme != 'http' && url.scheme != 'https') || url.host.isEmpty || url.userInfo.isNotEmpty) continue;
        var bitrate = int.tryParse('${data['bitrate'] ?? 0}') ?? 0;
        if (bitrate > 1000) bitrate ~/= 1000;
        final lossless = url.path.toLowerCase().endsWith('.flac') || '${data['extname']}'.toLowerCase() == 'flac';
        return StreamInfo(
          url: url.toString(),
          quality: lossless
              ? AudioQuality.lossless
              : bitrate >= 320
              ? AudioQuality.exhigh
              : bitrate >= 192
              ? AudioQuality.higher
              : AudioQuality.standard,
          trial: data['is_free_part'] == true || '${data['is_free_part']}' == '1',
          headers: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.kugou.com/'},
        );
      }
    }
    final msg = '${j['error'] ?? j['err_msg'] ?? j['msg'] ?? ''}'.trim();
    final refusal = [if (code != null) '错误码 $code', if (msg.isNotEmpty) msg].join('，');
    throw Exception('酷狗没有返回这首歌的播放地址${refusal.isEmpty ? '' : '（$refusal）'}');
  }

  // ── 歌词 ──────────────────────────────────────────

  @override
  Future<Lyrics> lyrics(Song song) async {
    final ids = _ids(song);
    try {
      final c = await _get(
        'https://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword=&duration=${song.duration.inMilliseconds}&hash=${ids.hash}&album_audio_id=${ids.audio}',
      );
      final candidates = (c['candidates'] as List? ?? const []).cast<Map<String, dynamic>>();
      if (candidates.isNotEmpty) {
        final first = candidates.first;
        final d = await _get('https://lyrics.kugou.com/download?ver=1&client=pc&id=${first['id']}&accesskey=${first['accesskey']}&fmt=lrc&charset=utf8');
        final content = d['content'] as String?;
        if (content != null && content.isNotEmpty) {
          final text = decodeText(base64.decode(content));
          final ly = parseLrc(text);
          if (ly.lines.isNotEmpty) return ly;
        }
      }
    } catch (e) {
      debugPrint('kugou lyrics: $e');
    }
    // 酷狗没有歌词时用网易云同一首歌的歌词（含翻译）。
    return Lyrics.empty;
  }
}

extension on String {
  String? ifEmpty(String? other) => isEmpty ? other : this;
}
