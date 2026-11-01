import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models.dart';
import '../music_source.dart';
import '../netease/netease_source.dart' show parseLrc;

class QQApiException implements Exception {
  const QQApiException(this.code);
  final int code;
  @override
  String toString() => 'QQ 音乐接口返回 $code';
}

/// QQ 音乐播放源：搜索、热搜、排行榜、歌词与 QQ 扫码登录。
///
/// QQ 音乐的播放地址接口只对已登录账号开放：登录后按所选音质（Hi-Res / 无损 / 320k / 128k）依次获取，
/// 会员歌曲需要账号有对应会员；未登录时播放免费歌曲与官方试听片段。
class QQMusicSource extends MusicSource {
  QQMusicSource({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              responseType: ResponseType.plain,
              headers: {'Referer': 'https://y.qq.com/', 'User-Agent': _ua},
            ),
          );

  static const sourceId = 'qq';
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
  static const _api = 'https://u.y.qq.com/cgi-bin/musicu.fcg';
  static const _prefsKey = 'qq.account';

  final Dio _dio;

  String? _uin;
  String? _key;
  UserProfile? _user;

  /// 扫码登录过程中各个域名下发的 Cookie（只在登录流程中使用）。
  final Map<String, String> _loginCookies = {};
  int _loginGeneration = 0;
  String? _qrKey;

  @override
  String get id => sourceId;

  @override
  String get name => 'QQ 音乐';

  @override
  String get description => 'QQ 音乐的搜索、排行榜、歌词与账号，登录后按所选音质播放';

  @override
  Set<SourceFeature> get features => {
    SourceFeature.search,
    SourceFeature.hotSearch,
    SourceFeature.charts,
    SourceFeature.playlistCategories,
    SourceFeature.newAlbums,
    SourceFeature.lyrics,
    SourceFeature.lyricTranslation,
    SourceFeature.dailyRecommend,
    SourceFeature.artist,
    SourceFeature.album,
    SourceFeature.comments,
    SourceFeature.login,
    SourceFeature.qrLogin,
    if (_user != null) SourceFeature.userPlaylists,
  };

  @override
  UserProfile? get user => _user;

  @override
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _uin = j['uin'] as String?;
      _key = j['key'] as String?;
      if (_uin != null) {
        _user = UserProfile(id: _uin!, nickname: '${j['nickname'] ?? 'QQ 用户'}', avatar: j['avatar'] as String?, vip: j['vip'] == true);
      }
    } catch (e) {
      debugPrint('qq account: $e');
    }
  }

  Future<void> _saveAccount() async {
    final prefs = await SharedPreferences.getInstance();
    if (_uin == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode({'uin': _uin, 'key': _key, 'nickname': _user?.nickname, 'avatar': _user?.avatar, 'vip': _user?.vip}));
    }
  }

  String get _cookie => _uin == null ? '' : 'uin=$_uin; qqmusic_key=$_key; qm_keyst=$_key; login_type=1';

  /// musicu.fcg 统一接口：一次请求可以带多个模块调用（[reqs] 的键为调用名）。
  Future<Map<String, dynamic>> _call(Map<String, Map<String, dynamic>> reqs) async {
    final body = {
      // 已登录时 tmeLoginType 为 2 表示 QQ 账号登录（1 为微信），musickey 需要与之匹配才会被认可。
      'comm': {
        'ct': '19',
        'cv': '1859',
        'uin': _uin ?? '0',
        if (_key != null) ...{'authst': _key, 'qq': _uin, 'tmeLoginType': '2'},
        'format': 'json',
      },
      ...reqs,
    };
    final res = await _dio.post<String>(
      _api,
      data: jsonEncode(body),
      options: Options(headers: {if (_uin != null) 'Cookie': _cookie}),
    );
    return jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _one(String module, String method, Map<String, dynamic> param) async {
    final j = await _call({
      'req': {'module': module, 'method': method, 'param': param},
    });
    final r = j['req'] as Map<String, dynamic>? ?? const {};
    final code = (r['code'] as num?)?.toInt() ?? -1;
    if (code != 0) throw QQApiException(code);
    return (r['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  static String _https(String? url) => (url ?? '').replaceFirst('http://', 'https://');

  static String? _albumCover(String? albumMid) =>
      albumMid == null || albumMid.isEmpty ? null : 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg';

  /// QQ 音乐歌曲：id 编码为“songmid:media_mid”，播放时需要 media_mid 拼文件名。
  /// 兼容新版（mid / name / singer / album / file）与旧版（songmid / songname / albummid / strMediaMid）字段。
  Song _song(Map<String, dynamic> j) {
    final mid = '${j['mid'] ?? j['songmid'] ?? ''}';
    final file = j['file'] as Map? ?? const {};
    final media = '${file['media_mid'] ?? j['strMediaMid'] ?? j['media_mid'] ?? mid}';
    final album = j['album'] as Map? ?? const {};
    final albumMid = '${album['mid'] ?? j['albummid'] ?? ''}';
    final albumName = '${album['name'] ?? album['title'] ?? j['albumname'] ?? ''}';
    final singers = (j['singer'] as List? ?? const []).cast<Map>();
    final pay = j['pay'] as Map? ?? const {};
    // 评论接口需要数字 id，一并编码在歌曲 id 中：“songmid:media_mid:数字 id”。
    final numeric = '${j['id'] ?? j['songid'] ?? ''}';
    return Song(
      id: numeric.isEmpty || numeric == '0' ? '$mid:$media' : '$mid:$media:$numeric',
      sourceId: sourceId,
      name: '${j['name'] ?? j['title'] ?? j['songname'] ?? ''}',
      artists: [for (final s in singers) ArtistRef('${s['mid'] ?? s['id'] ?? ''}', '${s['name'] ?? s['title'] ?? ''}')],
      album: AlbumRef(albumMid, albumName, cover: _albumCover(albumMid)),
      duration: Duration(seconds: (j['interval'] as num?)?.toInt() ?? 0),
      cover: _albumCover(albumMid),
      // 付费歌曲（数字专辑等）未购买时无法播放，但仍可换源播放，所以不标记为不可播放。
      playable: true,
      // 绿钻歌曲（pay_month）与付费数字专辑（pay_play）标记为 VIP。
      vip: (pay['pay_month'] as num?)?.toInt() == 1 || (pay['pay_play'] as num?)?.toInt() == 1,
    );
  }

  ({String mid, String media, String numeric}) _ids(Song s) {
    final p = s.id.split(':');
    return (mid: p.first, media: p.length > 1 ? p[1] : p.first, numeric: p.length > 2 ? p[2] : '');
  }

  // ── 搜索 ──────────────────────────────────────────

  @override
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) async {
    switch (type) {
      case SearchType.artist:
      case SearchType.album:
        final box = await _smartbox(keyword);
        return SearchResult(artists: type == SearchType.artist ? box.artists : const [], albums: type == SearchType.album ? box.albums : const []);
      case SearchType.playlist:
        return SearchResult(
          playlists: await _searchPlaylists(keyword, offset: offset, limit: limit),
        );
      case SearchType.song:
        final songs = await _searchSongs(keyword, offset: offset, limit: limit);
        return SearchResult(songs: songs, bestSong: songs.firstOrNull);
      case SearchType.all:
        Object? songError;
        final r = await Future.wait([
          _searchSongs(keyword, offset: offset, limit: limit).catchError((Object error) {
            songError = error;
            return <Song>[];
          }),
          _smartbox(keyword).catchError((Object _) => (artists: <ArtistInfo>[], albums: <AlbumInfo>[])),
          _searchPlaylists(keyword, limit: 6).catchError((Object _) => <PlaylistInfo>[]),
        ]);
        final songs = r[0] as List<Song>;
        final box = r[1] as ({List<ArtistInfo> artists, List<AlbumInfo> albums});
        final pls = r[2] as List<PlaylistInfo>;
        if (songs.isEmpty && box.artists.isEmpty && box.albums.isEmpty && pls.isEmpty && songError != null) throw songError!;
        return SearchResult(songs: songs, artists: box.artists, albums: box.albums, playlists: pls, bestSong: songs.firstOrNull, bestPlaylist: pls.firstOrNull);
    }
  }

  Future<List<Song>> _searchSongs(String keyword, {int offset = 0, int limit = 30}) async {
    final params = {
      'searchid': '${math.Random().nextInt(1 << 30)}',
      'query': keyword,
      'search_type': 0,
      'num_per_page': limit,
      'page_num': offset ~/ limit + 1,
      'highlight': 0,
      'grp': 1,
    };
    Map<String, dynamic> d;
    try {
      d = await _one('music.search.SearchCgiService', 'DoSearchForQQMusicMobile', params);
    } on QQApiException catch (error) {
      if (error.code != 2001) rethrow;
      d = await _one('music.search.SearchCgiService', 'DoSearchForQQMusicDesktop', params);
    }
    final body = d['body'] as Map? ?? const {};
    final songs = body['item_song'] as List? ?? (body['song'] as Map?)?['list'] as List? ?? const [];
    return [for (final song in songs.cast<Map<String, dynamic>>()) _song(song)];
  }

  /// 歌手与专辑搜索（联想接口，返回最相关的几个）。
  Future<({List<ArtistInfo> artists, List<AlbumInfo> albums})> _smartbox(String keyword) async {
    final res = await _dio.get<String>(
      'https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg',
      queryParameters: {'key': keyword, 'format': 'json', 'g_tk': 5381},
    );
    final d = ((jsonDecode(res.data ?? '{}') as Map)['data'] as Map?) ?? const {};
    List<Map> items(String k) => ((d[k] as Map?)?['itemlist'] as List? ?? const []).cast<Map>();
    return (
      artists: [
        for (final a in items('singer'))
          ArtistInfo(id: '${a['mid']}', sourceId: sourceId, name: '${a['name']}', avatar: 'https://y.gtimg.cn/music/photo_new/T001R300x300M000${a['mid']}.jpg'),
      ],
      albums: [
        for (final a in items('album'))
          AlbumInfo(
            id: '${a['mid']}',
            sourceId: sourceId,
            name: '${a['name']}',
            cover: _albumCover('${a['mid']}'),
            artist: ArtistRef('', '${a['singer'] ?? ''}'),
          ),
      ],
    );
  }

  Future<List<PlaylistInfo>> _searchPlaylists(String keyword, {int offset = 0, int limit = 20}) async {
    final res = await _dio.get<String>(
      'https://c.y.qq.com/soso/fcgi-bin/client_music_search_songlist',
      queryParameters: {
        'query': keyword,
        'page_no': offset ~/ limit,
        'num_per_page': limit,
        'format': 'json',
        'remoteplace': 'txt.yqq.playlist',
        'searchid': 1,
        'flag_qc': 0,
      },
    );
    final list = (((jsonDecode(res.data ?? '{}') as Map)['data'] as Map?)?['list'] as List? ?? const []).cast<Map>();
    return [
      for (final p in list)
        PlaylistInfo(
          id: 'diss:${p['dissid']}',
          sourceId: sourceId,
          name: _unescape('${p['dissname']}'),
          cover: _https(p['imgurl'] as String?),
          trackCount: (p['song_count'] as num?)?.toInt() ?? 0,
          playCount: (p['listennum'] as num?)?.toInt() ?? 0,
          creator: _unescape('${(p['creator'] as Map?)?['name'] ?? ''}'),
        ),
    ];
  }

  /// 旧接口的文字里带有 HTML 实体（&#39; 等）。
  static String _unescape(String s) =>
      s.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&nbsp;', ' ');

  @override
  Future<List<HotSearch>> hotSearches() async {
    final d = await _one('tencent_musicsoso_hotkey.HotkeyService', 'GetHotkeyForQQMusicMobile', {
      'remoteplace': 'txt.miniapp.wxada7aab80ba27074',
      // 搜索 id 是随机数；13 位时间戳会被拒绝（2001）。
      'searchid': '${math.Random().nextInt(1 << 30)}',
    });
    return [
      for (final x in (d['vec_hotkey'] as List? ?? const []).cast<Map>())
        if ('${x['query'] ?? x['title'] ?? ''}'.isNotEmpty) HotSearch('${x['query'] ?? x['title']}'),
    ];
  }

  // ── 排行榜与首页 ──────────────────────────────────────

  Future<List<Song>> _top(int topId, {int num = 100}) async {
    final d = await _one('musicToplist.ToplistInfoServer', 'GetDetail', {'topid': topId, 'offset': 0, 'num': num, 'period': ''});
    return [for (final x in (d['songInfoList'] as List? ?? const []).cast<Map<String, dynamic>>()) _song(x)];
  }

  @override
  Future<List<ChartInfo>> charts() async {
    final d = await _one('musicToplist.ToplistInfoServer', 'GetAll', {});
    final out = <ChartInfo>[];
    for (final g in (d['group'] as List? ?? const []).cast<Map>()) {
      for (final t in (g['toplist'] as List? ?? const []).cast<Map>()) {
        out.add(
          ChartInfo(
            id: 'top:${t['topId']}',
            name: '${t['title']}',
            cover: _https('${t['frontPicUrl'] ?? t['headPicUrl'] ?? ''}'),
            update: '${t['updateTime'] ?? t['period'] ?? ''}'.ifEmpty(null),
            group: '${g['groupName'] ?? ''}'.ifEmpty(null),
            preview: [for (final s in (t['song'] as List? ?? const []).cast<Map>().take(3)) '${s['title']} - ${s['singerName']}'],
          ),
        );
      }
    }
    return out;
  }

  @override
  Future<PlaylistInfo> playlist(String id) async {
    if (id.startsWith('top:')) {
      final topId = int.parse(id.substring(4));
      final d = await _one('musicToplist.ToplistInfoServer', 'GetDetail', {'topid': topId, 'offset': 0, 'num': 100, 'period': ''});
      final info = d['data'] as Map? ?? const {};
      final songs = [for (final x in (d['songInfoList'] as List? ?? const []).cast<Map<String, dynamic>>()) _song(x)];
      return PlaylistInfo(
        id: id,
        sourceId: sourceId,
        name: '${info['title'] ?? 'QQ 音乐榜单'}',
        cover: _https('${info['frontPicUrl'] ?? info['headPicUrl'] ?? ''}').ifEmpty(songs.firstOrNull?.coverUrl),
        description: info['intro'] as String?,
        creator: 'QQ 音乐',
        trackCount: songs.length,
        kind: PlaylistKind.chart,
        tracks: songs,
      );
    }
    // 歌单：diss:<歌单 id>
    final disstid = id.startsWith('diss:') ? id.substring(5) : id;
    final res = await _dio.get<String>(
      'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
      queryParameters: {'type': 1, 'json': 1, 'utf8': 1, 'onlysong': 0, 'new_format': 1, 'disstid': disstid, 'format': 'json', 'g_tk': 5381},
      options: Options(headers: {if (_uin != null) 'Cookie': _cookie}),
    );
    final j = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
    final cd = ((j['cdlist'] as List?)?.firstOrNull as Map?)?.cast<String, dynamic>() ?? const {};
    final songs = [for (final x in (cd['songlist'] as List? ?? const []).cast<Map<String, dynamic>>()) _song(x)];
    return PlaylistInfo(
      id: 'diss:$disstid',
      sourceId: sourceId,
      name: '${cd['dissname'] ?? 'QQ 音乐歌单'}',
      cover: _https(cd['logo'] as String?).ifEmpty(songs.firstOrNull?.coverUrl),
      description: cd['desc'] as String?,
      creator: cd['nickname'] as String?,
      trackCount: songs.length,
      tracks: songs,
    );
  }

  @override
  Future<PlaylistInfo> soaringChart() => playlist('top:62');

  /// 推荐歌单：歌单广场按热度排序。
  @override
  Future<List<PlaylistInfo>> recommendPlaylists({int limit = 12}) => categoryPlaylists(_recommendTag, limit: limit);

  /// 歌单广场的“推荐”分类。
  static const _recommendTag = '10000000';

  @override
  Future<List<PlaylistCategory>> playlistCategories() async {
    final d = await _one('playlist.PlaylistAllCategoriesServer', 'get_all_categories', {'qq': ''});
    return [
      const PlaylistCategory(id: _recommendTag, name: '推荐'),
      for (final g in (d['v_group'] as List? ?? const []).cast<Map>())
        for (final c in (g['v_item'] as List? ?? const []).cast<Map>()) PlaylistCategory(id: '${c['id']}', name: '${c['name']}', group: '${g['group_name']}'),
    ];
  }

  @override
  Future<List<PlaylistInfo>> categoryPlaylists(String categoryId, {int offset = 0, int limit = 30}) async {
    final d = await _one('playlist.PlayListPlazaServer', 'get_playlist_by_tag', {
      'id': int.parse(categoryId),
      'sin': offset,
      'size': limit,
      'order': 5,
      'cur_page': offset ~/ limit + 1,
    });
    return [
      for (final p in (d['v_playlist'] as List? ?? const []).cast<Map>())
        PlaylistInfo(
          id: 'diss:${p['tid']}',
          sourceId: sourceId,
          name: '${p['title']}',
          cover: _https('${p['cover_url_medium'] ?? p['cover_url_big'] ?? ''}'),
          playCount: (p['access_num'] as num?)?.toInt() ?? 0,
          creator: '${(p['creator_info'] as Map?)?['nick'] ?? ''}'.ifEmpty(null),
          description: p['desc'] as String?,
        ),
    ];
  }

  @override
  Future<HomeFeed> homeFeed() async {
    final results = await Future.wait([_top(62, num: 30), recommendPlaylists(limit: 12)]);
    return HomeFeed(daily: results[0] as List<Song>, playlists: results[1] as List<PlaylistInfo>);
  }

  @override
  Future<List<AlbumInfo>> newAlbums({int limit = 12}) async {
    final d = await _one('newalbum.NewAlbumServer', 'get_new_album_info', {'area': 1, 'sin': 0, 'num': limit});
    return [
      for (final a in (d['albums'] as List? ?? const []).cast<Map>())
        AlbumInfo(
          id: '${a['mid']}',
          sourceId: sourceId,
          name: '${a['name']}',
          cover: _albumCover('${a['mid']}'),
          artist: (a['singers'] as List?)?.isNotEmpty == true ? ArtistRef('${a['singers'][0]['mid']}', '${a['singers'][0]['name']}') : null,
          publishTime: DateTime.tryParse('${a['release_time'] ?? ''}'),
        ),
    ];
  }

  @override
  Future<AlbumInfo> album(String id) async {
    final j = await _call({
      'a': {
        'module': 'music.musichallAlbum.AlbumInfoServer',
        'method': 'GetAlbumDetail',
        'param': {'albumMid': id},
      },
      's': {
        'module': 'music.musichallAlbum.AlbumSongList',
        'method': 'GetAlbumSongList',
        'param': {'albumMid': id, 'begin': 0, 'num': 200, 'order': 2},
      },
    });
    final info = (((j['a'] as Map?)?['data'] as Map?)?['basicInfo'] as Map?) ?? const {};
    final singers = ((((j['a'] as Map?)?['data'] as Map?)?['singer'] as Map?)?['singerList'] as List? ?? const []).cast<Map>();
    final songs = [
      for (final x in ((((j['s'] as Map?)?['data'] as Map?)?['songList'] as List?) ?? const []).cast<Map>())
        if (x['songInfo'] is Map) _song(Map<String, dynamic>.from(x['songInfo'] as Map)),
    ];
    return AlbumInfo(
      id: id,
      sourceId: sourceId,
      name: '${info['albumName'] ?? ''}',
      cover: _albumCover(id),
      artist: singers.isNotEmpty ? ArtistRef('${singers.first['mid']}', '${singers.first['name']}') : songs.firstOrNull?.artists.firstOrNull,
      publishTime: DateTime.tryParse('${info['publishDate'] ?? ''}'),
      description: info['desc'] as String?,
      songs: songs,
      size: songs.length,
    );
  }

  @override
  Future<ArtistInfo> artist(String id) async {
    final j = await _call({
      'd': {
        'module': 'music.musichallSinger.SingerInfoInter',
        'method': 'GetSingerDetail',
        'param': {
          'singer_mids': [id],
          'ex_singer': 1,
          'wiki_singer': 1,
          'group_singer': 0,
          'pic': 1,
          'photos': 0,
        },
      },
      's': {
        'module': 'musichall.song_list_server',
        'method': 'GetSingerSongList',
        'param': {'singerMid': id, 'begin': 0, 'num': 50, 'order': 1},
      },
    });
    final singer = (((((j['d'] as Map?)?['data'] as Map?)?['singer_list'] as List?) ?? const []).firstOrNull as Map?) ?? const {};
    final basic = singer['basic_info'] as Map? ?? const {};
    final ex = singer['ex_info'] as Map? ?? const {};
    final songs = [
      for (final x in ((((j['s'] as Map?)?['data'] as Map?)?['songList'] as List?) ?? const []).cast<Map>())
        if (x['songInfo'] is Map) _song(Map<String, dynamic>.from(x['songInfo'] as Map)),
    ];
    return ArtistInfo(
      id: id,
      sourceId: sourceId,
      name: '${basic['name'] ?? songs.firstOrNull?.artists.firstOrNull?.name ?? ''}',
      avatar: 'https://y.gtimg.cn/music/photo_new/T001R500x500M000$id.jpg',
      description: ex['desc'] as String?,
      hotSongs: songs,
    );
  }

  @override
  Future<List<AlbumInfo>> artistAlbums(String id, {int limit = 30}) async {
    final d = await _one('music.musichallAlbum.AlbumListServer', 'GetAlbumList', {
      'singerMid': id,
      'order': 0,
      'begin': 0,
      'num': limit,
      'songNumTag': 0,
      'singerID': 0,
    });
    return [
      for (final a in (d['albumList'] as List? ?? const []).cast<Map>())
        AlbumInfo(
          id: '${a['albumMid']}',
          sourceId: sourceId,
          name: '${a['albumName']}',
          cover: _albumCover('${a['albumMid']}'),
          artist: ArtistRef(id, '${a['singerName'] ?? ''}'),
          publishTime: DateTime.tryParse('${a['publishDate'] ?? ''}'),
          size: (a['totalNum'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  @override
  Future<CommentPage> comments(Song song, {CommentSort sort = CommentSort.recommend, int offset = 0}) async {
    final ids = _ids(song);
    var bizId = ids.numeric;
    if (bizId.isEmpty) {
      // 旧格式的歌曲 id 没有数字 id：按 songmid 查一次歌曲信息。
      final d = await _one('music.pf_song_detail_svr', 'get_song_detail_yqq', {'song_mid': ids.mid});
      bizId = '${(d['track_info'] as Map?)?['id'] ?? ''}';
    }
    if (bizId.isEmpty) return const CommentPage(total: 0, comments: []);
    const size = 20;
    final latest = sort == CommentSort.latest;
    final d = await _one('music.globalComment.CommentReadServer', latest ? 'GetNewCommentList' : 'GetHotCommentList', {
      'BizType': 1,
      'BizId': bizId,
      'LastCommentSeqNo': '',
      'PageSize': size,
      'PageNum': offset ~/ size,
      if (latest) ...{'FromCommentId': '', 'WithHot': 0} else ...{'HotType': 1, 'WithAirborne': 0},
      'PicEnable': 1,
    });
    final list = d['CommentList'] as Map? ?? const {};
    final comments = [
      for (final c in (list['Comments'] as List? ?? const []).cast<Map>())
        // 跳过只有语音或图片的评论（文字只有“[音频]”“[图片]”）。
        if (!RegExp(r'^\s*(\[(音频|图片|表情)\]\s*)*$').hasMatch('${c['Content'] ?? ''}'))
          Comment(
            id: '${c['CmId']}',
            userName: '${c['Nick'] ?? ''}',
            avatar: _https(c['Avatar'] as String?).ifEmpty(null),
            content: _unescape('${c['Content']}'.trim()),
            time: int.tryParse('${c['PubTime']}') == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse('${c['PubTime']}') * 1000),
            location: (c['Location'] as String?)?.ifEmpty(null),
            likedCount: int.tryParse('${c['PraiseNum']}') ?? 0,
            replyCount: int.tryParse('${c['ReplyCnt']}') ?? 0,
          ),
    ];
    return CommentPage(
      total: (list['Total'] as num?)?.toInt() ?? comments.length,
      comments: comments,
      hasMore: list['HasMore'] == 1 || list['HasMore'] == true,
    );
  }

  @override
  Future<List<PlaylistInfo>> userPlaylists() async {
    if (_uin == null) return const [];
    final res = await _dio.get<String>(
      'https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss',
      queryParameters: {'hostuin': _uin, 'sin': 0, 'size': 60, 'format': 'json', 'g_tk': 5381},
      options: Options(headers: {'Cookie': _cookie}),
    );
    final j = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
    final list = ((j['data'] as Map?)?['disslist'] as List? ?? const []).cast<Map>();
    return [
      for (final d in list)
        if ('${d['tid']}' != '0')
          PlaylistInfo(
            id: 'diss:${d['tid']}',
            sourceId: sourceId,
            name: '${d['diss_name']}',
            cover: _https(d['diss_cover'] as String?),
            trackCount: (d['song_cnt'] as num?)?.toInt() ?? 0,
            creator: _user?.nickname,
          ),
    ];
  }

  // ── 播放 ──────────────────────────────────────────

  /// 各音质对应的文件名前缀与扩展名，从高到低。
  static const _files = [
    (AudioQuality.hires, 'RS01', 'flac'),
    (AudioQuality.lossless, 'F000', 'flac'),
    (AudioQuality.exhigh, 'M800', 'mp3'),
    (AudioQuality.higher, 'M500', 'mp3'),
    (AudioQuality.standard, 'C400', 'm4a'),
  ];

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async {
    // 未登录也向 QQ 音乐请求地址：免费歌曲给出完整文件；其余只有 60 秒的官方试听片段（RS02），标记为试听。
    final info = await _vkey(song, quality);
    if (info != null) return info;
    throw Exception(_uin == null ? '这首歌需要登录 QQ 音乐后播放' : '这首歌需要 QQ 音乐会员或单独购买');
  }

  /// 按音质从高到低一次请求多个文件名，取第一个有地址的；都没有时退回官方试听片段。
  Future<StreamInfo?> _vkey(Song song, AudioQuality quality) async {
    final ids = _ids(song);
    final wanted = [
      for (final f in _files)
        if (f.$1.index <= quality.index || f.$1 == AudioQuality.standard) f,
    ];
    final names = [for (final f in wanted) '${f.$2}${ids.media}.${f.$3}', 'RS02${ids.media}.mp3'];
    final guid = '${math.Random().nextInt(1 << 31)}';
    final d = await _one('vkey.GetVkeyServer', 'CgiGetVkey', {
      'guid': guid,
      'songmid': [for (final _ in names) ids.mid],
      'songtype': [for (final _ in names) 0],
      'filename': names,
      'uin': _uin ?? '0',
      'loginflag': 1,
      'platform': '20',
    });
    final sips = [for (final s in (d['sip'] as List? ?? const [])) '$s'];
    final sip = sips.firstWhere((s) => s.startsWith('https'), orElse: () => sips.firstOrNull ?? 'https://isure.stream.qqmusic.qq.com/');
    final infos = (d['midurlinfo'] as List? ?? const []).cast<Map>();
    for (var i = 0; i < infos.length && i < names.length; i++) {
      final purl = '${infos[i]['purl'] ?? ''}';
      if (purl.isEmpty) continue;
      if (i < wanted.length) return StreamInfo(url: '$sip$purl', quality: wanted[i].$1);
      return StreamInfo(url: '$sip$purl', quality: AudioQuality.standard, trial: true);
    }
    return null;
  }

  // ── 歌词 ──────────────────────────────────────────

  @override
  Future<Lyrics> lyrics(Song song) async {
    try {
      final res = await _dio.get<String>(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
        queryParameters: {'songmid': _ids(song).mid, 'format': 'json', 'nobase64': 1, 'g_tk': 5381},
      );
      final j = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
      final lyric = '${j['lyric'] ?? ''}';
      if (lyric.contains('[')) {
        final ly = parseLrc(lyric, translation: '${j['trans'] ?? ''}');
        // 只有“歌名 - 歌手”一行信息的歌词视为没有歌词。
        if (ly.lines.length > 2) return ly;
      }
    } catch (e) {
      debugPrint('qq lyrics: $e');
    }
    return Lyrics.empty;
  }

  // ── 扫码登录（QQ 或 TIM 扫码，经 QQ 互联授权登录 QQ 音乐） ─────────────────

  static const _appid = '716027609';
  static const _thirdAid = '100497308';

  /// ptlogin 与 QQ 互联使用的 hash33 / g_tk 算法。
  static int _hash33(String s, [int seed = 0]) {
    var h = seed;
    for (final c in s.codeUnits) {
      h += (h << 5) + c;
    }
    return h & 0x7fffffff;
  }

  /// 扫码登录过程中收到的 Cookie，按域名保存（键为“域名|名称”），请求时只带上该域名可见的 Cookie，
  /// 与浏览器和可用的开源客户端（Cookie Jar）一致：例如 graph.qq.com 的 p_skey 不会发给 QQ 音乐接口。
  final Map<String, (String, String)> _jar = {};

  void _absorb(Headers headers, Uri from) {
    for (final c in (headers['set-cookie'] ?? const <String>[]).expand((header) => header.split(RegExp(r',(?=\s*[^;,=\s]+\s*=)')))) {
      final parts = c.split(';');
      final kv = parts.first;
      final i = kv.indexOf('=');
      if (i <= 0) continue;
      final value = kv.substring(i + 1);
      final name = kv.substring(0, i).trim();
      var domain = from.host;
      for (final attr in parts.skip(1)) {
        final a = attr.trim();
        if (a.toLowerCase().startsWith('domain=')) domain = a.substring(7).trim().replaceFirst(RegExp(r'^\.'), '').toLowerCase();
      }
      if (value.isEmpty || value == 'deleted' || RegExp(r'(?:^|;)\s*max-age=0(?:;|$)', caseSensitive: false).hasMatch(c)) {
        _jar.remove('$domain|$name');
        _loginCookies.remove(name);
      } else {
        _jar['$domain|$name'] = (domain, value);
        _loginCookies[name] = value;
      }
    }
  }

  /// 扫码过程中收到的全部 Cookie（不区分域名）。
  String get _allLoginCookies => [for (final e in _jar.entries) '${e.key.substring(e.key.indexOf('|') + 1)}=${e.value.$2}'].join('; ');

  /// 发往 [to] 的 Cookie 请求头：只包含域名与目标主机匹配的 Cookie。
  String _cookiesFor(Uri to) {
    final host = to.host.toLowerCase();
    return [
      for (final e in _jar.entries)
        if (host == e.value.$1 || host.endsWith('.${e.value.$1}')) '${e.key.substring(e.key.indexOf('|') + 1)}=${e.value.$2}',
    ].join('; ');
  }

  @override
  Future<QrTicket> createQrLogin() async {
    cancelQrLogin();
    final generation = _loginGeneration;
    final res = await _dio.get<List<int>>(
      'https://ssl.ptlogin2.qq.com/ptqrshow',
      queryParameters: {'appid': _appid, 'e': 2, 'l': 'M', 's': 3, 'd': 72, 'v': 4, 't': math.Random().nextDouble(), 'daid': 383, 'pt_3rd_aid': _thirdAid},
      options: Options(responseType: ResponseType.bytes, headers: {'Referer': 'https://xui.ptlogin2.qq.com/'}),
    );
    _checkLoginGeneration(generation);
    _absorb(res.headers, Uri.https('ssl.ptlogin2.qq.com', '/ptqrshow'));
    final qrsig = _loginCookies['qrsig'];
    if (qrsig == null || res.data == null) throw Exception('获取二维码失败');
    _qrKey = qrsig;
    return QrTicket(qrsig, '', image: Uint8List.fromList(res.data!), app: 'QQ 或 TIM');
  }

  @override
  Future<QrState> checkQrLogin(QrTicket ticket) async {
    if (_qrKey != null && _qrKey != ticket.key) throw StateError('二维码已失效，请重新扫码');
    final generation = _loginGeneration;
    final res = await _dio.get<String>(
      'https://ssl.ptlogin2.qq.com/ptqrlogin',
      queryParameters: {
        'u1': 'https://graph.qq.com/oauth2.0/login_jump',
        'ptqrtoken': _hash33(ticket.key),
        'ptredirect': 0,
        'h': 1,
        't': 1,
        'g': 1,
        'from_ui': 1,
        'ptlang': 2052,
        'action': '0-0-${DateTime.now().millisecondsSinceEpoch}',
        'js_ver': 20102616,
        'js_type': 1,
        'pt_uistyle': 40,
        'aid': _appid,
        'daid': 383,
        'pt_3rd_aid': _thirdAid,
        'has_onekey': 1,
      },
      options: Options(
        headers: {
          'Referer': 'https://xui.ptlogin2.qq.com/',
          'Cookie': [_cookiesFor(Uri.https('ssl.ptlogin2.qq.com', '/ptqrlogin')), 'qrsig=${ticket.key}'].where((c) => c.isNotEmpty).join('; '),
        },
      ),
    );
    _checkLoginGeneration(generation);
    _absorb(res.headers, Uri.https('ssl.ptlogin2.qq.com', '/ptqrlogin'));
    final args = RegExp(r"'([^']*)'").allMatches(res.data ?? '').map((m) => m[1]!).toList();
    final code = args.firstOrNull ?? '';
    switch (code) {
      case '66':
        return QrState.waiting;
      case '67':
        return QrState.scanned;
      case '65':
        return QrState.expired;
      case '0':
        // 同一张二维码只换取一次凭据。
        if (_finishing != null && _finishing!.$1 == ticket.key) {
          await _finishing!.$2;
        } else {
          final f = _finishLogin(args.length > 2 ? args[2] : '', generation);
          _finishing = (ticket.key, f);
          try {
            await f;
          } catch (_) {
            if (_finishing?.$2 == f) _finishing = null;
            rethrow;
          }
        }
        _checkLoginGeneration(generation);
        return QrState.confirmed;
      default:
        throw Exception(args.length > 4 && args[4].isNotEmpty ? args[4] : '登录失败（$code）');
    }
  }

  /// 正在换取凭据的二维码与过程（避免重复换取）。
  (String, Future<void>)? _finishing;

  void _checkLoginGeneration(int generation) {
    if (generation != _loginGeneration) throw StateError('扫码登录已取消，请重新扫码');
  }

  @override
  void cancelQrLogin() {
    _loginGeneration++;
    _qrKey = null;
    _loginCookies.clear();
    _jar.clear();
    _finishing = null;
  }

  static Uri _loginUri(Uri uri) {
    if ((uri.scheme != 'https' && uri.scheme != 'http') ||
        (uri.host != 'qq.com' && !uri.host.endsWith('.qq.com')) ||
        uri.userInfo.isNotEmpty ||
        uri.port != (uri.scheme == 'https' ? 443 : 80)) {
      throw const FormatException('登录失败：授权跳转地址不属于可信的 QQ 服务器');
    }
    return uri.replace(scheme: 'https', port: 443);
  }

  static String _uuid() {
    final r = math.Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> _finishLogin(String checkSig, int generation) async {
    const ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    final callback = _loginUri(Uri.parse(checkSig));
    final query = callback.queryParameters;
    if (callback.path != '/check_sig' || (query['uin'] ?? '').isEmpty || (query['ptsigx'] ?? '').isEmpty) {
      throw const FormatException('登录失败：QQ 没有返回完整的扫码授权凭据，请重新扫码');
    }
    var current = Uri.https('ssl.ptlogin2.graph.qq.com', '/check_sig', {
      'uin': query['uin']!,
      'ptsigx': query['ptsigx']!,
      'pttype': '1',
      'service': 'ptqrlogin',
      'nodirect': '0',
      's_url': 'https://graph.qq.com/oauth2.0/login_jump',
      'ptlang': '2052',
      'ptredirect': '100',
      'aid': _appid,
      'daid': '383',
      'j_later': '0',
      'low_login_hour': '0',
      'regmaster': '0',
      'pt_login_type': '3',
      'pt_aid': '0',
      'pt_aaid': '16',
      'pt_light': '0',
      'pt_3rd_aid': _thirdAid,
    });
    for (var hop = 0; hop < 6; hop++) {
      final res = await _dio.get<String>(
        current.toString(),
        options: Options(
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
          // check_sig 与扫码接口不在同一个域名，但需要带上扫码时收到的全部 Cookie（与可用的 Swift 客户端一致）。
          headers: {'Cookie': _allLoginCookies, 'Referer': 'https://xui.ptlogin2.qq.com/', 'User-Agent': ua},
        ),
      );
      _checkLoginGeneration(generation);
      _absorb(res.headers, current);
      if ((_loginCookies['p_skey'] ?? '').isNotEmpty) break;
      final location = res.headers.value('location');
      if (res.statusCode == null || res.statusCode! < 300 || res.statusCode! >= 400 || location == null || location.isEmpty) break;
      current = _loginUri(current.resolve(location));
    }
    final pSkey = _loginCookies['p_skey'];
    if (pSkey == null || pSkey.isEmpty) throw Exception('登录失败：没有获得 QQ 互联授权凭据（p_skey），请重新扫码');
    // QQ 互联授权码只能用一次：按顺序尝试两种已知可用的交换方式，每次重新取一个授权码。
    // 1. 按域名发送 Cookie、tmeLoginType 2（Go / Rust / Python 客户端）；2. 发送全部 Cookie、不带 tmeLoginType（Swift 客户端）。
    final failures = <String>[];
    Map<String, dynamic>? j;
    for (final scoped in const [true, false]) {
      final auth = await _dio.post<String>(
        'https://graph.qq.com/oauth2.0/authorize',
        data: {
          'response_type': 'code',
          'client_id': _thirdAid,
          'redirect_uri': 'https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/',
          'scope': 'get_user_info,get_app_friends',
          'state': 'state',
          'switch': '',
          'from_ptlogin': 1,
          'src': 1,
          'update_auth': 1,
          'openapi': '1010_1030',
          'g_tk': _hash33(pSkey, 5381),
          'auth_time': DateTime.now().millisecondsSinceEpoch,
          'ui': _uuid(),
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
          headers: {'Cookie': _allLoginCookies, 'Referer': 'https://graph.qq.com/', 'Origin': 'https://graph.qq.com', 'User-Agent': ua},
        ),
      );
      _checkLoginGeneration(generation);
      _absorb(auth.headers, Uri.https('graph.qq.com', '/oauth2.0/authorize'));
      final location = auth.headers.value('location') ?? '';
      final code = Uri.tryParse(location)?.queryParameters['code'];
      if (code == null || code.isEmpty) {
        debugPrint('qq login authorize: status ${auth.statusCode} location $location');
        failures.add('授权码（HTTP ${auth.statusCode}）');
        continue;
      }
      final login = await _dio.post<String>(
        _api,
        data: jsonEncode({
          'comm': {'g_tk': 5381, 'platform': 'yqq', 'ct': 24, 'cv': 0, if (scoped) 'tmeLoginType': 2},
          'req': {
            'module': 'QQConnectLogin.LoginServer',
            'method': 'QQLogin',
            'param': {'code': code},
          },
        }),
        options: Options(
          headers: {
            'Cookie': scoped ? _cookiesFor(Uri.parse(_api)) : _allLoginCookies,
            'Referer': 'https://y.qq.com/',
            'User-Agent': ua,
            'Content-Type': 'application/json',
          },
        ),
      );
      _checkLoginGeneration(generation);
      final body = jsonDecode(login.data ?? '{}') as Map<String, dynamic>;
      final resultCode = int.tryParse('${(body['req'] as Map?)?['code'] ?? body['code'] ?? -1}') ?? -1;
      debugPrint('qq login exchange (${scoped ? 'scoped' : 'all'}): ${login.data}');
      if (resultCode == 0) {
        _absorb(login.headers, Uri.parse(_api));
        j = body;
        break;
      }
      final r = body['req'] as Map? ?? const {};
      final d = r['data'] as Map? ?? const {};
      final why = [
        '${r['msg'] ?? r['message'] ?? ''}',
        '${d['errMsg'] ?? d['errtip'] ?? ''}',
      ].map((t) => t.trim()).firstWhere((t) => t.isNotEmpty, orElse: () => '');
      failures.add('$resultCode${why.isEmpty ? '' : '：$why'}');
    }
    if (j == null) throw Exception('QQ 音乐凭据交换失败（${failures.join('；')}），请重新扫码');
    final data = (j['req'] as Map?)?['data'] as Map? ?? const {};
    // 部分账号的 musickey 放在 Set-Cookie 里而不是 JSON 中。
    var uin = '${data['musicid'] ?? data['uin'] ?? ''}'.replaceAll(RegExp(r'^0+$'), '');
    if (uin.isEmpty) uin = _loginCookies['uin']?.replaceFirst(RegExp(r'^o0*'), '') ?? '';
    var key = '${data['musickey'] ?? ''}';
    if (key.isEmpty) key = _loginCookies['qqmusic_key'] ?? _loginCookies['qm_keyst'] ?? '';
    if (uin.isEmpty || key.isEmpty) throw Exception('登录 QQ 音乐失败（${(j['req'] as Map?)?['code'] ?? j['code']}）');
    _uin = uin;
    _key = key;
    _loginCookies.clear();
    _jar.clear();
    _user = UserProfile(id: uin, nickname: 'QQ 用户 $uin');
    await _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    final uin = _uin;
    final key = _key;
    final generation = _loginGeneration;
    if (uin == null || key == null) return;
    try {
      final res = await _dio.get<String>(
        'https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg',
        queryParameters: {'cid': 205360838, 'userid': uin, 'reqfrom': 1, 'format': 'json', 'g_tk': _hash33(key, 5381)},
        options: Options(headers: {'Cookie': _cookie}),
      );
      final j = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
      final creator = ((j['data'] as Map?)?['creator'] as Map?) ?? const {};
      final m = await membership();
      if (generation != _loginGeneration || _uin != uin || _key != key) return;
      _user = UserProfile(
        id: _uin!,
        nickname: '${creator['nick'] ?? _user?.nickname ?? 'QQ 用户'}',
        avatar: _https(creator['headpic'] as String?).ifEmpty(null),
        vip: m?.active ?? false,
      );
    } catch (e) {
      debugPrint('qq profile: $e');
    }
    if (generation != _loginGeneration || _uin != uin || _key != key) return;
    await _saveAccount();
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    cancelQrLogin();
    _uin = null;
    _key = null;
    _user = null;
    await _saveAccount();
    notifyListeners();
  }

  @override
  Future<Membership?> membership() async {
    if (_uin == null) return null;
    final d = await _one('userInfo.VipQueryServer', 'SRFVipQuery_V2', {
      'uin_list': [_uin],
    });
    final info = ((d['infoMap'] as Map?)?[_uin] as Map?) ?? const {};
    int v(String k) => (info[k] as num?)?.toInt() ?? 0;
    final level = v('iVipLevel');
    DateTime? end(String k) {
      final t = v(k);
      return t > 0 ? DateTime.fromMillisecondsSinceEpoch(t * 1000) : null;
    }

    if (v('iSvip') == 1 || v('iSuperVip') == 1) {
      return Membership(
        platform: 'QQ 音乐',
        title: v('iSvip') == 1 ? '超级会员' : '豪华绿钻',
        active: true,
        level: level > 0 ? 'Lv.$level' : null,
        expires: end('iSvipEnd') ?? end('iSuperVipEnd') ?? end('iVipEnd'),
        benefits: const ['臻品母带与 Hi-Res 音质', '播放与下载会员歌曲', '绿钻全部权益'],
      );
    }
    if (v('iVipFlag') == 1 || v('iGreenVip') == 1) {
      return Membership(
        platform: 'QQ 音乐',
        title: '绿钻',
        active: true,
        level: level > 0 ? 'Lv.$level' : null,
        expires: end('iVipEnd'),
        benefits: const ['无损音质', '播放与下载会员歌曲'],
      );
    }
    return Membership(platform: 'QQ 音乐', title: '未开通会员', level: level > 0 ? '曾为 Lv.$level' : null);
  }
}

extension on String {
  String? ifEmpty(String? other) => isEmpty ? other : this;
}
