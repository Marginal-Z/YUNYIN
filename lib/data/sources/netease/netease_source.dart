import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models.dart';
import '../music_source.dart';
import 'netease_crypto.dart';

class NeteaseApiException implements Exception {
  NeteaseApiException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => message;
}

/// 网易云音乐播放源：直接请求官方 weapi / eapi 接口，无需自建服务端。
class NeteaseSource extends MusicSource {
  NeteaseSource();

  static const sourceId = 'netease';
  static const _prefsCookie = 'netease.cookie';
  static const _prefsProfile = 'netease.profile';
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  final Map<String, String> _cookies = {};
  UserProfile? _user;

  @override
  String get id => sourceId;

  @override
  String get name => '网易云音乐';

  @override
  String get description => '官方接口 · 支持登录、每日推荐、评论与歌词';

  @override
  Set<SourceFeature> get features => SourceFeature.values.toSet();

  @override
  UserProfile? get user => _user;

  @override
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsCookie);
    if (raw != null) _cookies.addAll(Map<String, String>.from(jsonDecode(raw) as Map));
    _cookies.putIfAbsent('_ntes_nuid', () => NeteaseCrypto.randomHex(32));
    _cookies.putIfAbsent('NMTID', () => '00O${NeteaseCrypto.randomHex(29)}');
    final p = prefs.getString(_prefsProfile);
    if (p != null && _cookies.containsKey('MUSIC_U')) {
      final j = jsonDecode(p) as Map<String, dynamic>;
      _user = UserProfile(
        id: '${j['id']}',
        nickname: '${j['nickname']}',
        avatar: j['avatar'] as String?,
        signature: j['signature'] as String?,
        vip: j['vip'] as bool? ?? false,
      );
      // 后台刷新账号信息，失效则清除。
      _refreshAccount().catchError((_) {});
    }
  }

  // ── 请求 ──────────────────────────────────────────

  String get _cookieHeader {
    final m = {..._cookies, 'os': 'pc', 'appver': '3.0.18.203152', '__remember_me': 'true'};
    return m.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<void> _saveCookies() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCookie, jsonEncode(_cookies));
  }

  void _absorbCookies(Headers headers) {
    final list = headers.map['set-cookie'];
    if (list == null) return;
    var changed = false;
    for (final c in list) {
      final first = c.split(';').first;
      final i = first.indexOf('=');
      if (i <= 0) continue;
      final k = first.substring(0, i).trim();
      final v = first.substring(i + 1).trim();
      if (v.isEmpty || v == 'deleted') {
        changed |= _cookies.remove(k) != null;
      } else if (_cookies[k] != v) {
        _cookies[k] = v;
        changed = true;
      }
    }
    if (changed) _saveCookies();
  }

  Future<void>? _anonymous;

  /// 保证请求带有身份（登录用户或匿名游客），并在遇到风控（-462）时重新注册游客重试一次。
  Future<Map<String, dynamic>> _withIdentity(Future<Map<String, dynamic>> Function() send) async {
    if (!_cookies.containsKey('MUSIC_U') && !_cookies.containsKey('MUSIC_A')) {
      try {
        await (_anonymous ??= ensureAnonymous().whenComplete(() => _anonymous = null));
      } catch (e) {
        // 游客注册失败时仍然尝试直接请求。
        debugPrint('netease anonymous failed: $e');
      }
    }
    try {
      return await send();
    } on NeteaseApiException catch (e) {
      if (e.code != -462 || _cookies.containsKey('MUSIC_U')) rethrow;
      await ensureAnonymous(force: true);
      return send();
    }
  }

  Future<Map<String, dynamic>> _weapi(String path, [Map<String, dynamic> data = const {}]) {
    if (path == '/register/anonimous') return _postWeapi(path, data);
    return _withIdentity(() => _postWeapi(path, data));
  }

  Future<Map<String, dynamic>> _postWeapi(String path, Map<String, dynamic> data) async {
    final body = {...data, 'csrf_token': _cookies['__csrf'] ?? ''};
    final res = await _dio.post<String>(
      'https://music.163.com/weapi$path',
      data: NeteaseCrypto.weapi(body),
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'User-Agent': _ua, 'Referer': 'https://music.163.com', 'Origin': 'https://music.163.com', 'Cookie': _cookieHeader},
      ),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> _eapi(String path, Map<String, dynamic> data) => _withIdentity(() => _postEapi(path, data));

  Future<Map<String, dynamic>> _postEapi(String path, Map<String, dynamic> data) async {
    final header = {
      'osver': '14',
      'deviceId': _cookies['_ntes_nuid'] ?? '',
      'appver': '8.20.20',
      'versioncode': '140',
      'mobilename': '',
      'buildver': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'resolution': '1920x1080',
      '__csrf': _cookies['__csrf'] ?? '',
      'os': 'android',
      'channel': '',
      'requestId': '${DateTime.now().millisecondsSinceEpoch}_0${DateTime.now().microsecond % 1000}',
      if (_cookies['MUSIC_U'] != null) 'MUSIC_U': _cookies['MUSIC_U']!,
      if (_cookies['MUSIC_U'] == null && _cookies['MUSIC_A'] != null) 'MUSIC_A': _cookies['MUSIC_A']!,
    };
    final res = await _dio.post<String>(
      'https://interface.music.163.com/eapi$path',
      data: NeteaseCrypto.eapi('/api$path', {...data, 'header': header, 'e_r': false}),
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'User-Agent': 'NeteaseMusic/8.20.20.231215173437(8020020);Dalvik/2.1.0 (Linux; U; Android 14)',
          'Cookie': header.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('; '),
        },
      ),
    );
    return _parse(res);
  }

  /// 未登录时注册匿名游客，获取 MUSIC_A 令牌；网易云对没有身份的请求会触发风控。
  Future<void> ensureAnonymous({bool force = false}) async {
    if (!force && (_cookies.containsKey('MUSIC_U') || _cookies.containsKey('MUSIC_A'))) return;
    final deviceId = NeteaseCrypto.randomHex(52).toUpperCase();
    final username = base64.encode(utf8.encode('$deviceId ${NeteaseCrypto.anonymousIdDigest(deviceId)}'));
    Map<String, dynamic> j;
    try {
      j = await _postWeapi('/register/anonimous', {'username': username});
    } on NeteaseApiException {
      // 偶发 400，稍后重试一次。
      await Future<void>.delayed(const Duration(milliseconds: 600));
      j = await _postWeapi('/register/anonimous', {'username': username});
    }
    _absorbCookieString(j['cookie']);
    final token = j['token'] ?? j['userId'];
    if (!_cookies.containsKey('MUSIC_A') && j['token'] is String) _cookies['MUSIC_A'] = j['token'] as String;
    await _saveCookies();
    debugPrint('netease anonymous: code=${j['code']} hasToken=${token != null} MUSIC_A=${_cookies.containsKey('MUSIC_A')}');
  }

  Map<String, dynamic> _parse(Response<String> res) {
    _absorbCookies(res.headers);
    final text = res.data ?? '';
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw NeteaseApiException(res.statusCode ?? -1, '服务返回了无法解析的内容（${res.statusCode}）');
    }
    final code = (j['code'] as num?)?.toInt() ?? 200;
    if (code != 200 && code != 800 && code != 801 && code != 802 && code != 803) {
      final msg = (j['message'] ?? j['msg'] ?? '请求失败（$code）').toString();
      if (code == 301) {
        _user = null;
        notifyListeners();
        throw NeteaseApiException(code, '请先登录网易云音乐账号');
      }
      throw NeteaseApiException(code, '$msg（$code）');
    }
    return j;
  }

  // ── 解析 ──────────────────────────────────────────

  static String? _img(Object? url) {
    if (url == null) return null;
    final s = url.toString();
    if (s.isEmpty) return null;
    return s.replaceFirst('http://', 'https://');
  }

  Song _song(Map<String, dynamic> s, {Map<String, dynamic>? privilege}) {
    final ar = (s['ar'] ?? s['artists']) as List? ?? const [];
    final al = (s['al'] ?? s['album']) as Map<String, dynamic>?;
    final priv = privilege ?? s['privilege'] as Map<String, dynamic>?;
    final st = (priv?['st'] as num?)?.toInt() ?? 0;
    final alia = (s['alia'] ?? s['alias']) as List?;
    return Song(
      id: '${s['id']}',
      sourceId: id,
      name: '${s['name'] ?? ''}',
      artists: [for (final a in ar) ArtistRef('${(a as Map)['id']}', '${a['name'] ?? ''}')],
      album: al == null ? null : AlbumRef('${al['id']}', '${al['name'] ?? ''}', cover: _img(al['picUrl'] ?? al['blurPicUrl'])),
      duration: Duration(milliseconds: ((s['dt'] ?? s['duration']) as num?)?.toInt() ?? 0),
      playable: st >= 0,
      alias: (alia != null && alia.isNotEmpty) ? '${alia.first}' : null,
    );
  }

  PlaylistInfo _playlist(Map<String, dynamic> p) {
    final creator = p['creator'] as Map<String, dynamic>?;
    return PlaylistInfo(
      id: '${p['id']}',
      sourceId: id,
      name: '${p['name'] ?? ''}',
      cover: _img(p['coverImgUrl'] ?? p['picUrl']),
      trackCount: (p['trackCount'] as num?)?.toInt() ?? 0,
      creator: creator?['nickname'] as String? ?? p['copywriter'] as String?,
      description: p['description'] as String?,
      tags: [for (final t in (p['tags'] as List? ?? const [])) '$t'],
      playCount: (p['playCount'] as num?)?.toInt() ?? 0,
      subscribed: p['subscribed'] == true,
      isLikedList: p['specialType'] == 5,
      ownedByMe: _user != null && '${creator?['userId']}' == _user!.id,
    );
  }

  AlbumInfo _album(Map<String, dynamic> a, {List<Song>? songs}) {
    final ar = a['artist'] as Map<String, dynamic>? ?? ((a['artists'] as List?)?.firstOrNull as Map<String, dynamic>?);
    final t = (a['publishTime'] as num?)?.toInt();
    return AlbumInfo(
      id: '${a['id']}',
      sourceId: id,
      name: '${a['name'] ?? ''}',
      cover: _img(a['picUrl'] ?? a['blurPicUrl']),
      artist: ar == null ? null : ArtistRef('${ar['id']}', '${ar['name'] ?? ''}'),
      publishTime: t == null || t <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(t),
      description: a['description'] as String?,
      songs: songs,
      size: (a['size'] as num?)?.toInt() ?? songs?.length ?? 0,
    );
  }

  ArtistInfo _artist(Map<String, dynamic> a, {List<Song> hot = const [], int? fans, bool followed = false}) => ArtistInfo(
    id: '${a['id']}',
    sourceId: id,
    name: '${a['name'] ?? ''}',
    avatar: _img(a['picUrl'] ?? a['img1v1Url'] ?? a['avatar']),
    fans: fans ?? (a['fansCount'] as num?)?.toInt(),
    description: a['briefDesc'] as String?,
    hotSongs: hot,
    followed: followed || a['followed'] == true,
  );

  // ── 账号 ──────────────────────────────────────────

  Future<void> _refreshAccount() async {
    final j = await _weapi('/w/nuser/account/get');
    final p = j['profile'] as Map<String, dynamic>?;
    if (p == null) {
      _user = null;
    } else {
      _user = UserProfile(
        id: '${p['userId']}',
        nickname: '${p['nickname']}',
        avatar: _img(p['avatarUrl']),
        signature: p['signature'] as String?,
        vip: ((p['vipType'] as num?)?.toInt() ?? 0) > 0,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsProfile,
        jsonEncode({'id': _user!.id, 'nickname': _user!.nickname, 'avatar': _user!.avatar, 'signature': _user!.signature, 'vip': _user!.vip}),
      );
    }
    notifyListeners();
  }

  void _absorbCookieString(Object? cookie) {
    if (cookie is! String) return;
    for (final part in cookie.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final k = part.substring(0, i).trim();
      if (k == 'MUSIC_U' || k == '__csrf' || k == 'MUSIC_A_T' || k == 'MUSIC_R_T') {
        _cookies[k] = part.substring(i + 1).trim();
      }
    }
    // 登录后不再携带匿名游客身份。
    if (_cookies.containsKey('MUSIC_U')) _cookies.remove('MUSIC_A');
    _saveCookies();
  }

  @override
  Future<QrTicket> createQrLogin() async {
    final j = await _weapi('/login/qrcode/unikey', {'type': 1});
    final key = '${j['unikey']}';
    return QrTicket(key, 'https://music.163.com/login?codekey=$key');
  }

  @override
  Future<QrState> checkQrLogin(QrTicket ticket) async {
    final j = await _weapi('/login/qrcode/client/login', {'key': ticket.key, 'type': 1});
    switch ((j['code'] as num).toInt()) {
      case 800:
        return QrState.expired;
      case 802:
        return QrState.scanned;
      case 803:
        _absorbCookieString(j['cookie']);
        await _refreshAccount();
        return QrState.confirmed;
      default:
        return QrState.waiting;
    }
  }

  @override
  Future<void> sendSmsCode(String phone, {String countryCode = '86'}) async {
    await _weapi('/sms/captcha/sent', {'cellphone': phone, 'ctcode': countryCode, 'secrete': 'music_middleuser_pclogin'});
  }

  /// 旧的 /login/cellphone 会被风控直接拒绝（-462），使用新版 /w/login/cellphone。
  @override
  Future<void> loginWithSms(String phone, String code, {String countryCode = '86'}) async {
    final data = {'type': '1', 'https': 'true', 'phone': phone, 'countrycode': countryCode, 'captcha': code, 'remember': 'true'};
    Map<String, dynamic> j;
    try {
      j = await _weapi('/w/login/cellphone', data);
    } on NeteaseApiException catch (e) {
      // 两种通道的风控策略不同，被拦截时换另一种再试一次。
      if (e.code != -462 && e.code != 8821) rethrow;
      j = await _eapi('/w/login/cellphone', data);
    }
    await _finishLogin(j);
  }

  @override
  Future<void> loginWithPassword(String account, String password, {String countryCode = '86'}) async {
    final pwd = NeteaseCrypto.md5(password);
    try {
      final Map<String, dynamic> j;
      if (account.contains('@')) {
        j = await _weapi('/w/login', {'type': '0', 'https': 'true', 'username': account, 'password': pwd, 'rememberLogin': 'true'});
      } else {
        j = await _eapi('/w/login/cellphone', {
          'type': '1',
          'https': 'true',
          'phone': account,
          'countrycode': countryCode,
          'password': pwd,
          'remember': 'true',
        });
      }
      await _finishLogin(j);
    } on NeteaseApiException catch (e) {
      // 网易云对第三方客户端的手机号 + 密码登录做了风控。
      if (e.code == -462 || e.code == 10004 || e.code == 8821) {
        throw NeteaseApiException(e.code, '网易云限制了密码登录，请改用验证码登录或扫码登录');
      }
      if (e.code == 501) throw NeteaseApiException(e.code, '账号不存在');
      if (e.code == 502) throw NeteaseApiException(e.code, '密码错误');
      rethrow;
    }
  }

  Future<void> _finishLogin(Map<String, dynamic> j) async {
    _absorbCookieString(j['cookie']);
    if (!_cookies.containsKey('MUSIC_U')) throw NeteaseApiException(-1, '登录失败，请稍后重试');
    await _refreshAccount();
  }

  @override
  Future<void> logout() async {
    try {
      await _weapi('/logout');
    } catch (_) {}
    _cookies.removeWhere((k, _) => k == 'MUSIC_U' || k == '__csrf' || k == 'MUSIC_A_T' || k == 'MUSIC_R_T');
    await _saveCookies();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsProfile);
    _user = null;
    notifyListeners();
  }

  // ── 发现 ──────────────────────────────────────────

  @override
  Future<HomeFeed> homeFeed() async {
    final playlists = recommendPlaylists(limit: 6);
    final daily = loggedIn ? _dailySongs() : soaringChart().then((p) => p.tracks ?? const <Song>[]);
    return HomeFeed(daily: await daily, playlists: await playlists);
  }

  Future<List<Song>> _dailySongs() async {
    final j = await _weapi('/v3/discovery/recommend/songs');
    final list = (j['data']?['dailySongs'] as List?) ?? const [];
    return [for (final s in list) _song(Map<String, dynamic>.from(s as Map))];
  }

  @override
  Future<List<PlaylistInfo>> recommendPlaylists({int limit = 12}) async {
    if (loggedIn) {
      try {
        final j = await _weapi('/v1/discovery/recommend/resource');
        final list = (j['recommend'] as List?) ?? const [];
        if (list.isNotEmpty) {
          return [for (final p in list.take(limit)) _playlist(Map<String, dynamic>.from(p as Map))];
        }
      } catch (_) {}
    }
    final j = await _weapi('/personalized/playlist', {'limit': limit, 'total': true, 'n': 1000});
    return [for (final p in (j['result'] as List? ?? const [])) _playlist(Map<String, dynamic>.from(p as Map))];
  }

  @override
  Future<List<ChartInfo>> charts() async {
    final j = await _weapi('/toplist');
    return [
      for (final t in (j['list'] as List? ?? const []))
        ChartInfo(
          id: '${t['id']}',
          name: '${t['name']}',
          cover: _img(t['coverImgUrl']),
          update: t['updateFrequency'] as String?,
          preview: [for (final x in (t['tracks'] as List? ?? const [])) '${x['first']} - ${x['second']}'],
        ),
    ];
  }

  @override
  Future<PlaylistInfo> soaringChart() => playlist('19723756');

  @override
  Future<List<AlbumInfo>> newAlbums({int limit = 12}) async {
    final j = await _weapi('/album/new', {'area': 'ALL', 'limit': limit, 'offset': 0, 'total': true});
    return [for (final a in (j['albums'] as List? ?? const [])) _album(Map<String, dynamic>.from(a as Map))];
  }

  @override
  Future<List<RadioInfo>> hotRadios({int limit = 12}) async {
    final j = await _weapi('/djradio/hot/v1', {'limit': limit, 'offset': 0});
    return [
      for (final r in (j['djRadios'] as List? ?? const []))
        RadioInfo(
          id: '${r['id']}',
          sourceId: id,
          name: '${r['name']}',
          cover: _img(r['picUrl']),
          host: r['dj']?['nickname'] as String?,
          programCount: (r['programCount'] as num?)?.toInt() ?? 0,
          category: r['category'] as String?,
        ),
    ];
  }

  @override
  Future<PlaylistInfo> radioPrograms(RadioInfo radio) async {
    final j = await _weapi('/dj/program/byradio', {'radioId': radio.id, 'limit': 100, 'offset': 0, 'asc': false});
    final songs = <Song>[];
    for (final p in (j['programs'] as List? ?? const [])) {
      final main = p['mainSong'] as Map<String, dynamic>?;
      if (main == null) continue;
      final s = _song(main);
      songs.add(s.copyWith(cover: _img(p['coverUrl']) ?? radio.cover));
    }
    return PlaylistInfo(
      id: radio.id,
      sourceId: id,
      name: radio.name,
      cover: radio.cover,
      creator: radio.host,
      trackCount: songs.length,
      kind: PlaylistKind.radio,
      tracks: songs,
    );
  }

  // ── 详情 ──────────────────────────────────────────

  @override
  Future<PlaylistInfo> playlist(String id) async {
    final j = await _weapi('/v6/playlist/detail', {'id': id, 'n': 100000, 's': 8});
    final p = Map<String, dynamic>.from(j['playlist'] as Map);
    final info = _playlist(p);
    final ids = [for (final t in (p['trackIds'] as List? ?? const [])) '${t['id']}'];
    final songs = await _songDetails(ids);
    return info.withTracks(songs);
  }

  Future<List<Song>> _songDetails(List<String> ids) async {
    final out = <Song>[];
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, (i + 500).clamp(0, ids.length));
      final j = await _weapi('/v3/song/detail', {
        'c': jsonEncode([
          for (final id in chunk) {'id': id},
        ]),
      });
      final privs = <String, Map<String, dynamic>>{
        for (final pr in (j['privileges'] as List? ?? const [])) '${pr['id']}': Map<String, dynamic>.from(pr as Map),
      };
      for (final s in (j['songs'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(s as Map);
        out.add(_song(m, privilege: privs['${m['id']}']));
      }
    }
    return out;
  }

  @override
  Future<AlbumInfo> album(String id) async {
    final j = await _weapi('/v1/album/$id');
    final songs = [for (final s in (j['songs'] as List? ?? const [])) _song(Map<String, dynamic>.from(s as Map))];
    return _album(Map<String, dynamic>.from(j['album'] as Map), songs: songs);
  }

  @override
  Future<ArtistInfo> artist(String id) async {
    final j = await _weapi('/v1/artist/$id');
    int? fans;
    var followed = false;
    try {
      final f = await _weapi('/artist/follow/count/get', {'id': id});
      fans = (f['data']?['fansCnt'] as num?)?.toInt();
      followed = f['data']?['isFollow'] == true;
    } catch (_) {}
    final hot = [for (final s in (j['hotSongs'] as List? ?? const [])) _song(Map<String, dynamic>.from(s as Map))];
    return _artist(Map<String, dynamic>.from(j['artist'] as Map), hot: hot, fans: fans, followed: followed);
  }

  @override
  Future<List<AlbumInfo>> artistAlbums(String id, {int limit = 30}) async {
    final j = await _weapi('/artist/albums/$id', {'limit': limit, 'offset': 0, 'total': true});
    return [for (final a in (j['hotAlbums'] as List? ?? const [])) _album(Map<String, dynamic>.from(a as Map))];
  }

  @override
  Future<List<ArtistInfo>> similarArtists(String id) async {
    final j = await _weapi('/discovery/simiArtist', {'artistid': id});
    return [for (final a in (j['artists'] as List? ?? const [])) _artist(Map<String, dynamic>.from(a as Map))];
  }

  @override
  Future<void> followArtist(String id, bool follow) async {
    await _weapi(follow ? '/artist/sub' : '/artist/unsub', {'artistId': id, 'artistIds': '[$id]'});
  }

  // ── 搜索 ──────────────────────────────────────────

  Future<Map<String, dynamic>> _search(String s, int type, int offset, int limit) async {
    final data = {'s': s, 'type': type, 'limit': limit, 'offset': offset, 'total': true};
    Map<String, dynamic>? j;
    Object? error;
    for (final attempt in <Future<Map<String, dynamic>> Function()>[
      () => _weapi('/cloudsearch/get/web', data),
      () => _eapi('/cloudsearch/pc', data),
      () => _weapi('/search/get', data),
    ]) {
      try {
        j = await attempt();
        break;
      } catch (e) {
        error = e;
      }
    }
    if (j == null) throw error!;
    return Map<String, dynamic>.from((j['result'] as Map?) ?? const {});
  }

  @override
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) async {
    List<Song> songs(Map<String, dynamic> r) => [for (final s in (r['songs'] as List? ?? const [])) _song(Map<String, dynamic>.from(s as Map))];
    List<ArtistInfo> artists(Map<String, dynamic> r) => [for (final a in (r['artists'] as List? ?? const [])) _artist(Map<String, dynamic>.from(a as Map))];
    List<AlbumInfo> albums(Map<String, dynamic> r) => [for (final a in (r['albums'] as List? ?? const [])) _album(Map<String, dynamic>.from(a as Map))];
    List<PlaylistInfo> playlists(Map<String, dynamic> r) => [
      for (final p in (r['playlists'] as List? ?? const [])) _playlist(Map<String, dynamic>.from(p as Map)),
    ];

    switch (type) {
      case SearchType.song:
        final r = await _search(keyword, 1, offset, limit);
        return SearchResult(songs: songs(r), songCount: (r['songCount'] as num?)?.toInt() ?? 0);
      case SearchType.artist:
        return SearchResult(artists: artists(await _search(keyword, 100, offset, limit)));
      case SearchType.album:
        return SearchResult(albums: albums(await _search(keyword, 10, offset, limit)));
      case SearchType.playlist:
        return SearchResult(playlists: playlists(await _search(keyword, 1000, offset, limit)));
      case SearchType.all:
        final rs = await Future.wait([
          _search(keyword, 1, 0, 20),
          _search(keyword, 100, 0, 6).catchError((_) => <String, dynamic>{}),
          _search(keyword, 10, 0, 6).catchError((_) => <String, dynamic>{}),
          _search(keyword, 1000, 0, 6).catchError((_) => <String, dynamic>{}),
        ]);
        final s = songs(rs[0]);
        final pl = playlists(rs[3]);
        return SearchResult(
          songs: s,
          artists: artists(rs[1]),
          albums: albums(rs[2]),
          playlists: pl,
          bestSong: s.firstOrNull,
          bestPlaylist: pl.firstOrNull,
          songCount: (rs[0]['songCount'] as num?)?.toInt() ?? s.length,
        );
    }
  }

  @override
  Future<List<HotSearch>> hotSearches() async {
    final j = await _weapi('/hotsearchlist/get');
    return [
      for (final h in (j['data'] as List? ?? const []))
        HotSearch(
          '${h['searchWord']}',
          score: (h['score'] as num?)?.toInt() ?? 0,
          tag: switch ((h['iconType'] as num?)?.toInt()) {
            1 => 'hot',
            5 => 'up',
            2 || 4 => 'new',
            _ => null,
          },
        ),
    ];
  }

  // ── 播放 ──────────────────────────────────────────

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async {
    Map<String, dynamic>? first(Map<String, dynamic> j) => ((j['data'] as List?)?.firstOrNull as Map?)?.cast<String, dynamic>();
    final v1 = {'ids': '[${song.id}]', 'level': quality.level, 'encodeType': 'flac'};
    Map<String, dynamic>? item;
    for (final attempt in <Future<Map<String, dynamic>> Function()>[
      () => _weapi('/song/enhance/player/url/v1', v1),
      () => _eapi('/song/enhance/player/url/v1', v1),
      () => _weapi('/song/enhance/player/url', {'ids': '[${song.id}]', 'br': quality.bitrate}),
    ]) {
      try {
        item = first(await attempt());
        if (item?['url'] != null) break;
      } catch (e) {
        debugPrint('netease stream: $e');
      }
    }
    final url = item?['url'] as String?;
    if (url == null || url.isEmpty) return const StreamInfo();
    final trial = item?['freeTrialInfo'] != null;
    return StreamInfo(
      url: url,
      trial: trial,
      quality: quality,
      gainDb: (item?['gain'] as num?)?.toDouble(),
      headers: const {'User-Agent': _ua, 'Referer': 'https://music.163.com/'},
    );
  }

  @override
  Future<Lyrics> lyrics(Song song) async {
    final res = await _dio.get<String>(
      'https://music.163.com/api/song/lyric',
      queryParameters: {'id': song.id, 'lv': -1, 'kv': -1, 'tv': -1},
      options: Options(headers: {'User-Agent': _ua, 'Referer': 'https://music.163.com', 'Cookie': _cookieHeader}),
    );
    final j = _parse(res);
    final lrc = j['lrc']?['lyric'] as String? ?? '';
    final tr = j['tlyric']?['lyric'] as String? ?? '';
    return parseLrc(lrc, translation: tr);
  }

  // ── 评论 ──────────────────────────────────────────

  Comment _comment(Map<String, dynamic> c) {
    final u = c['user'] as Map<String, dynamic>? ?? const {};
    final t = (c['time'] as num?)?.toInt();
    return Comment(
      id: '${c['commentId']}',
      userName: '${u['nickname'] ?? ''}',
      avatar: _img(u['avatarUrl']),
      content: '${c['content'] ?? ''}',
      time: t == null ? null : DateTime.fromMillisecondsSinceEpoch(t),
      location: c['ipLocation']?['location'] as String?,
      likedCount: (c['likedCount'] as num?)?.toInt() ?? 0,
      liked: c['liked'] == true,
      replyCount: (c['showFloorComment']?['replyCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<CommentPage> comments(Song song, {CommentSort sort = CommentSort.recommend, int offset = 0}) async {
    final rid = 'R_SO_4_${song.id}';
    if (sort == CommentSort.hot) {
      final j = await _weapi('/v1/resource/hotcomments/$rid', {'rid': song.id, 'limit': 20, 'offset': offset, 'beforeTime': 0});
      final list = [for (final c in (j['hotComments'] as List? ?? const [])) _comment(Map<String, dynamic>.from(c as Map))];
      return CommentPage(total: (j['total'] as num?)?.toInt() ?? list.length, comments: list, hasMore: j['hasMore'] == true);
    }
    final j = await _weapi('/v1/resource/comments/$rid', {'rid': song.id, 'limit': 20, 'offset': offset, 'beforeTime': 0});
    final latest = [for (final c in (j['comments'] as List? ?? const [])) _comment(Map<String, dynamic>.from(c as Map))];
    final hot = [for (final c in (j['hotComments'] as List? ?? const [])) _comment(Map<String, dynamic>.from(c as Map))];
    final list = sort == CommentSort.recommend && offset == 0 ? [...hot, ...latest.where((c) => !hot.any((h) => h.id == c.id))] : latest;
    return CommentPage(total: (j['total'] as num?)?.toInt() ?? list.length, comments: list, hasMore: j['more'] == true);
  }

  @override
  Future<void> postComment(Song song, String content) async {
    await _weapi('/resource/comments/add', {'threadId': 'R_SO_4_${song.id}', 'content': content});
  }

  @override
  Future<void> likeComment(Song song, Comment comment, bool like) async {
    await _weapi(like ? '/v1/comment/like' : '/v1/comment/unlike', {'threadId': 'R_SO_4_${song.id}', 'commentId': comment.id});
  }

  // ── 我的 ──────────────────────────────────────────

  @override
  Future<List<PlaylistInfo>> userPlaylists() async {
    final u = _user;
    if (u == null) throw NeteaseApiException(301, '请先登录网易云音乐账号');
    final j = await _weapi('/user/playlist', {'uid': u.id, 'limit': 1000, 'offset': 0, 'includeVideo': true});
    return [for (final p in (j['playlist'] as List? ?? const [])) _playlist(Map<String, dynamic>.from(p as Map))];
  }

  @override
  Future<List<Song>> recentSongs() async {
    final j = await _weapi('/play-record/song/list', {'limit': 200});
    return [
      for (final r in (j['data']?['list'] as List? ?? const []))
        if (r['data'] is Map) _song(Map<String, dynamic>.from(r['data'] as Map)),
    ];
  }

  @override
  Future<List<AlbumInfo>> subscribedAlbums() async {
    final j = await _weapi('/album/sublist', {'limit': 100, 'offset': 0, 'total': true});
    return [for (final a in (j['data'] as List? ?? const [])) _album(Map<String, dynamic>.from(a as Map))];
  }

  @override
  Future<List<ArtistInfo>> followedArtists() async {
    final j = await _weapi('/artist/sublist', {'limit': 100, 'offset': 0, 'total': true});
    return [for (final a in (j['data'] as List? ?? const [])) _artist(Map<String, dynamic>.from(a as Map), followed: true)];
  }

  @override
  Future<Set<String>> likedSongIds() async {
    final u = _user;
    if (u == null) return const {};
    final j = await _weapi('/song/like/get', {'uid': u.id});
    return {for (final x in (j['ids'] as List? ?? const [])) '$x'};
  }

  @override
  Future<void> likeSong(Song song, bool like) async {
    if (_user == null) throw NeteaseApiException(301, '请先登录网易云音乐账号');
    await _weapi('/radio/like', {'alg': 'itembased', 'trackId': song.id, 'like': like, 'time': '3'});
  }
}

final _lrcTime = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// 解析 LRC 歌词，可选合并翻译歌词。
Lyrics parseLrc(String lrc, {String translation = ''}) {
  Map<int, String> parse(String text) {
    final out = <int, String>{};
    for (final raw in const LineSplitter().convert(text)) {
      final matches = _lrcTime.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final content = raw.substring(matches.last.end).trim();
      for (final m in matches) {
        final frac = m.group(3) ?? '0';
        final ms =
            int.parse(m.group(1)!) * 60000 +
            int.parse(m.group(2)!) * 1000 +
            (frac.length == 3
                ? int.parse(frac)
                : frac.length == 2
                ? int.parse(frac) * 10
                : int.parse(frac) * 100);
        out[ms] = content;
      }
    }
    return out;
  }

  final main = parse(lrc);
  if (main.isEmpty) {
    final plain = const LineSplitter().convert(lrc).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return Lyrics([for (final l in plain) LyricLine(Duration.zero, l)], synced: false);
  }
  final tr = parse(translation);
  final keys = main.keys.toList()..sort();
  return Lyrics([
    for (final k in keys)
      if (main[k]!.isNotEmpty) LyricLine(Duration(milliseconds: k), main[k]!, translation: tr[k]),
  ]);
}
