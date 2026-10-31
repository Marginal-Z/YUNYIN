import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models.dart';
import '../../song_matcher.dart';
import '../music_source.dart';
import '../source_policy.dart';
import '../netease/netease_source.dart' show parseLrc;

/// QQ 音乐播放源：搜索、热搜、排行榜、歌词与 QQ 扫码登录。
///
/// QQ 音乐的播放地址接口只对已登录账号开放：登录后按所选音质（Hi-Res / 无损 / 320k / 128k）依次获取，
/// 会员歌曲需要账号有对应会员。打开“其他平台补位”后，取不到地址的歌曲换用网易云的同一首歌播放。
class QQMusicSource extends MusicSource {
  QQMusicSource(this.fallback, {Dio? dio})
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

  /// 换源播放用的播放源（网易云音乐）。
  final MusicSource? fallback;
  final Dio _dio;
  final Map<String, Song?> _matches = {};

  String? _uin;
  String? _key;
  UserProfile? _user;

  /// 扫码登录过程中各个域名下发的 Cookie（只在登录流程中使用）。
  final Map<String, String> _loginCookies = {};

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
    SourceFeature.lyrics,
    SourceFeature.lyricTranslation,
    SourceFeature.dailyRecommend,
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
      'comm': {'ct': '19', 'cv': '1859', 'uin': _uin ?? '0', if (_key != null) 'authst': _key, 'format': 'json'},
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
    if (code != 0) throw Exception('QQ 音乐接口返回 $code');
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
    return Song(
      id: '$mid:$media',
      sourceId: sourceId,
      name: '${j['name'] ?? j['title'] ?? j['songname'] ?? ''}',
      artists: [for (final s in singers) ArtistRef('${s['mid'] ?? s['id'] ?? ''}', '${s['name'] ?? s['title'] ?? ''}')],
      album: AlbumRef(albumMid, albumName, cover: _albumCover(albumMid)),
      duration: Duration(seconds: (j['interval'] as num?)?.toInt() ?? 0),
      cover: _albumCover(albumMid),
      // 付费歌曲（数字专辑等）未购买时无法播放，但仍可换源播放，所以不标记为不可播放。
      playable: true,
      alias: (pay['pay_play'] as num?)?.toInt() == 1 ? 'VIP' : null,
    );
  }

  ({String mid, String media}) _ids(Song s) {
    final i = s.id.indexOf(':');
    return i < 0 ? (mid: s.id, media: s.id) : (mid: s.id.substring(0, i), media: s.id.substring(i + 1));
  }

  // ── 搜索 ──────────────────────────────────────────

  @override
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) async {
    if (type != SearchType.all && type != SearchType.song) return const SearchResult();
    final d = await _one('music.search.SearchCgiService', 'DoSearchForQQMusicMobile', {
      // 搜索 id 是随机数；13 位时间戳会被拒绝（2001）。
      'searchid': '${math.Random().nextInt(1 << 30)}',
      'query': keyword,
      'search_type': 0,
      'num_per_page': limit,
      'page_num': offset ~/ limit + 1,
      'highlight': 0,
      'grp': 1,
    });
    final body = d['body'] as Map? ?? const {};
    final items = (body['item_song'] as List? ?? const []).cast<Map<String, dynamic>>();
    final songs = [for (final x in items) _song(x)];
    return SearchResult(songs: songs, bestSong: songs.firstOrNull);
  }

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

  @override
  Future<List<PlaylistInfo>> recommendPlaylists({int limit = 12}) async {
    final list = await charts();
    return [
      for (final c in list.take(limit)) PlaylistInfo(id: c.id, sourceId: sourceId, name: c.name, cover: c.cover, creator: 'QQ 音乐', kind: PlaylistKind.chart),
    ];
  }

  @override
  Future<HomeFeed> homeFeed() async {
    final results = await Future.wait([_top(62, num: 30), recommendPlaylists(limit: 6)]);
    return HomeFeed(daily: results[0] as List<Song>, playlists: results[1] as List<PlaylistInfo>);
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
    if (_uin != null) {
      try {
        final direct = await _vkey(song, quality);
        if (direct != null) return direct;
      } catch (e) {
        debugPrint('qq vkey: $e');
      }
    }
    final match = SourcePolicy.crossSource ? await _match(song) : null;
    if (match == null || fallback == null) {
      throw Exception(_uin == null ? '登录 QQ 音乐后才能播放（也可以在设置中导入洛雪音源）' : '这首歌需要 QQ 音乐会员或单独购买（也可以在设置中导入洛雪音源）');
    }
    return fallback!.stream(match, quality);
  }

  /// 按音质从高到低一次请求多个文件名，取第一个有地址的。
  Future<StreamInfo?> _vkey(Song song, AudioQuality quality) async {
    final ids = _ids(song);
    final wanted = [
      for (final f in _files)
        if (f.$1.index <= quality.index) f,
    ];
    final guid = '${math.Random().nextInt(1 << 31)}';
    final d = await _one('vkey.GetVkeyServer', 'CgiGetVkey', {
      'guid': guid,
      'songmid': [for (final _ in wanted) ids.mid],
      'songtype': [for (final _ in wanted) 0],
      'filename': [for (final f in wanted) '${f.$2}${ids.media}.${f.$3}'],
      'uin': _uin,
      'loginflag': 1,
      'platform': '20',
    });
    final sips = [for (final s in (d['sip'] as List? ?? const [])) '$s'];
    final sip = sips.firstWhere((s) => s.startsWith('https'), orElse: () => sips.firstOrNull ?? 'https://isure.stream.qqmusic.qq.com/');
    final infos = (d['midurlinfo'] as List? ?? const []).cast<Map>();
    for (var i = 0; i < infos.length && i < wanted.length; i++) {
      final purl = '${infos[i]['purl'] ?? ''}';
      if (purl.isNotEmpty) return StreamInfo(url: '$sip$purl', quality: wanted[i].$1);
    }
    return null;
  }

  Future<Song?> _match(Song song) async {
    if (_matches.containsKey(song.id)) return _matches[song.id];
    final src = fallback;
    final m = src == null ? null : await SongMatcher.match(src, song);
    _matches[song.id] = m;
    return m;
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
    if (!SourcePolicy.crossSource) return Lyrics.empty;
    final m = await _match(song);
    return m == null || fallback == null ? Lyrics.empty : fallback!.lyrics(m);
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

  void _absorb(Headers headers) {
    for (final c in headers['set-cookie'] ?? const <String>[]) {
      final kv = c.split(';').first;
      final i = kv.indexOf('=');
      if (i <= 0) continue;
      final value = kv.substring(i + 1);
      if (value.isEmpty) continue;
      _loginCookies[kv.substring(0, i).trim()] = value;
    }
  }

  String get _loginCookieHeader => _loginCookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  @override
  Future<QrTicket> createQrLogin() async {
    _loginCookies.clear();
    final res = await _dio.get<List<int>>(
      'https://ssl.ptlogin2.qq.com/ptqrshow',
      queryParameters: {'appid': _appid, 'e': 2, 'l': 'M', 's': 3, 'd': 72, 'v': 4, 't': math.Random().nextDouble(), 'daid': 383, 'pt_3rd_aid': _thirdAid},
      options: Options(responseType: ResponseType.bytes, headers: {'Referer': 'https://xui.ptlogin2.qq.com/'}),
    );
    _absorb(res.headers);
    final qrsig = _loginCookies['qrsig'];
    if (qrsig == null || res.data == null) throw Exception('获取二维码失败');
    return QrTicket(qrsig, '', image: Uint8List.fromList(res.data!), app: 'QQ 或 TIM');
  }

  @override
  Future<QrState> checkQrLogin(QrTicket ticket) async {
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
      options: Options(headers: {'Referer': 'https://xui.ptlogin2.qq.com/', 'Cookie': _loginCookieHeader}),
    );
    _absorb(res.headers);
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
        await _finishLogin(args.length > 2 ? args[2] : '');
        return QrState.confirmed;
      default:
        throw Exception(args.length > 4 && args[4].isNotEmpty ? args[4] : '登录失败（$code）');
    }
  }

  /// 扫码确认后：访问 check_sig 拿到 p_skey → QQ 互联授权拿到 code → 用 code 登录 QQ 音乐拿到 musickey。
  Future<void> _finishLogin(String checkSig) async {
    if (checkSig.isEmpty) throw Exception('登录失败：没有返回授权地址');
    final sig = await _dio.get<String>(
      checkSig,
      options: Options(followRedirects: false, validateStatus: (s) => s != null && s < 400, headers: {'Cookie': _loginCookieHeader}),
    );
    _absorb(sig.headers);
    final pSkey = _loginCookies['p_skey'];
    if (pSkey == null) throw Exception('登录失败：没有获得授权凭据');
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
        'ui': '${math.Random().nextInt(1 << 31)}',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 400,
        headers: {'Cookie': _loginCookieHeader, 'Referer': 'https://xui.ptlogin2.qq.com/'},
      ),
    );
    final location = auth.headers.value('location') ?? '';
    final code = Uri.tryParse(location)?.queryParameters['code'];
    if (code == null || code.isEmpty) throw Exception('登录失败：QQ 互联没有返回授权码');
    final login = await _dio.post<String>(
      _api,
      data: jsonEncode({
        'comm': {'g_tk': 5381, 'platform': 'yqq', 'ct': 24, 'cv': 0},
        'req': {
          'module': 'QQConnectLogin.LoginServer',
          'method': 'QQLogin',
          'param': {'code': code},
        },
      }),
    );
    final j = jsonDecode(login.data ?? '{}') as Map<String, dynamic>;
    final data = (j['req'] as Map?)?['data'] as Map? ?? const {};
    final uin = '${data['musicid'] ?? data['uin'] ?? ''}';
    final key = '${data['musickey'] ?? ''}';
    if (uin.isEmpty || uin == '0' || key.isEmpty) throw Exception('登录 QQ 音乐失败（${(j['req'] as Map?)?['code']}）');
    _uin = uin;
    _key = key;
    _loginCookies.clear();
    _user = UserProfile(id: uin, nickname: 'QQ 用户 $uin');
    await _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    try {
      final res = await _dio.get<String>(
        'https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg',
        queryParameters: {'cid': 205360838, 'userid': _uin, 'reqfrom': 1, 'format': 'json', 'g_tk': 5381},
        options: Options(headers: {'Cookie': _cookie}),
      );
      final j = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
      final creator = ((j['data'] as Map?)?['creator'] as Map?) ?? const {};
      final m = await membership();
      _user = UserProfile(
        id: _uin!,
        nickname: '${creator['nick'] ?? _user?.nickname ?? 'QQ 用户'}',
        avatar: _https(creator['headpic'] as String?).ifEmpty(null),
        vip: m?.active ?? false,
      );
    } catch (e) {
      debugPrint('qq profile: $e');
    }
    await _saveAccount();
    notifyListeners();
  }

  @override
  Future<void> logout() async {
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
