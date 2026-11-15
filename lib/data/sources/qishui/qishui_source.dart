import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models.dart';
import '../json_decode.dart';
import '../music_source.dart';
import '../net_retry.dart';
import '../netease/netease_source.dart' show parseLrc;

/// 汽水音乐的歌曲搜索没有返回内容（网关降级时返回 200 与空内容，响应头带 tt_stable）。
class QishuiThrottled implements Exception {
  const QishuiThrottled();

  @override
  String toString() => '汽水音乐暂时没有返回搜索结果，请稍等十几秒再试';
}

/// 汽水音乐播放源：只使用官方分享页与网页端的公开接口，不带设备标识，也不登录。
///
/// - 搜索：`api.qishui.com/luna/search/{track,album,playlist}`，以网页端（device_platform=web）请求；
///   歌曲搜索的网关有时降级、返回空内容（中国大陆以外的网络更常见），稍等后重试一次，仍为空时提示稍后再试。
/// - 歌单：`api.qishui.com/luna/pc/playlist/detail`（网页端参数）；专辑：官方分享页 `music.douyin.com/qishui/share/album`。
/// - 播放与歌词：分享页使用的 `beta-luna.douyin.com/luna/h5/seo_track`。免费歌曲给出未加密的整曲 m4a（约 64k / 128k / 256k AAC），
///   会员歌曲只给 30～60 秒的官方试听片段。
///
/// 不提供（只能通过绕过平台保护实现）：登录与“我的”（扫码登录要伪装成官方客户端的登录组件、处理风控验证），
/// 会员整曲与无损（要官方原生组件生成的 X-Helios / X-Medusa 签名，音频还要按 PlayAuth 解密），
/// 排行榜与首页推荐接口（要伪造客户端设备参数）。首页与发现改用热门歌单。
class QishuiSource extends MusicSource {
  QishuiSource({Dio? dio, this.retryDelay = const Duration(milliseconds: 1500)})
    : _dio =
          dio ?? withRetry(Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15), responseType: ResponseType.plain)));

  static const sourceId = 'qishui';
  static const _api = 'https://api.qishui.com/luna';
  static const _seo = 'https://beta-luna.douyin.com/luna/h5/seo_track';
  static const _share = 'https://music.douyin.com/qishui/share';
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

  /// 网页端的公共参数（与官方分享页相同），不含任何设备标识。
  static const _web = {'aid': '386088', 'device_platform': 'web'};

  static const _trialNote = '汽水音乐的会员歌曲只能试听：完整播放需要官方客户端的签名，云音不接入';

  final Dio _dio;

  /// 歌曲搜索返回空内容时，等待多久再重试一次。
  final Duration retryDelay;

  /// 歌曲详情（播放地址与歌词来自同一个接口）缓存 10 分钟，播放与显示歌词只请求一次。
  final _tracks = <String, (DateTime, Map<String, dynamic>)>{};

  @override
  String get id => sourceId;

  @override
  String get name => '汽水音乐';

  @override
  String get description => '汽水音乐的搜索、歌单、专辑与歌词，免费歌曲完整播放；不支持登录，会员歌曲只能试听';

  @override
  Set<SourceFeature> get features => const {SourceFeature.search, SourceFeature.album, SourceFeature.lyrics, SourceFeature.dailyRecommend};

  @override
  List<SearchType> get searchTypes => const [SearchType.all, SearchType.song, SearchType.album, SearchType.playlist];

  Future<String> _text(String url, [Map<String, String>? params]) async {
    final res = await _dio.get<String>(url, queryParameters: params, options: Options(headers: const {'User-Agent': _ua}));
    return res.data ?? '';
  }

  Future<Map<String, dynamic>> _json(String url, [Map<String, String>? params]) async {
    final j = await decodeJson(await _text(url, params));
    return j is Map<String, dynamic> ? j : const {};
  }

  /// 官方分享页把页面数据写在 `_ROUTER_DATA = {...}` 中。
  static Map<String, dynamic> _routerData(String html) {
    final marker = html.indexOf('_ROUTER_DATA = ');
    final start = marker < 0 ? -1 : html.indexOf('{', marker);
    if (start < 0) throw const FormatException('汽水音乐分享页没有页面数据');
    var depth = 0;
    var inString = false;
    for (var i = start; i < html.length; i++) {
      final c = html.codeUnitAt(i);
      if (inString) {
        if (c == 0x5C) {
          i++;
        } else if (c == 0x22) {
          inString = false;
        }
      } else if (c == 0x22) {
        inString = true;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D && --depth == 0) {
        return Map<String, dynamic>.from(jsonDecode(html.substring(start, i + 1)) as Map);
      }
    }
    throw const FormatException('汽水音乐分享页的数据不完整');
  }

  /// 图片地址：`urls[0] + uri`，加上与分享页相同的缩放后缀。
  static String? _image(Object? img, {int size = 500}) {
    if (img is! Map) return null;
    final urls = img['urls'];
    final uri = '${img['uri'] ?? ''}';
    if (urls is! List || urls.isEmpty || uri.isEmpty) return null;
    final base = '${urls.first}';
    // 头像等给出的是完整地址。
    if (base.contains(uri) || !base.endsWith('/')) return base;
    return '$base$uri~c5_${size}x$size.jpg';
  }

  static List<ArtistRef> _artists(Object? list) => [
    for (final a in (list is List ? list : const []).whereType<Map>()) ArtistRef('${a['id']}', '${a['name'] ?? ''}'),
  ];

  /// 平台标记为只有会员能完整播放的歌曲。
  static bool _vipOnly(Map t) => (t['label_info'] is Map) && (t['label_info'] as Map)['only_vip_playable'] == true;

  Song _song(Map t) {
    final album = t['album'] is Map ? t['album'] as Map : const {};
    final cover = _image(album['url_cover']);
    return Song(
      id: '${t['id']}',
      sourceId: sourceId,
      name: '${t['name'] ?? ''}',
      artists: _artists(t['artists']),
      album: album['id'] == null ? null : AlbumRef('${album['id']}', '${album['name'] ?? ''}', cover: cover),
      duration: Duration(milliseconds: (t['duration'] as num?)?.toInt() ?? 0),
      cover: cover,
      fee: _vipOnly(t) ? SongFee.vip : SongFee.free,
    );
  }

  AlbumInfo _album(Map a) {
    final artists = _artists(a['artists']);
    final release = (a['release_date'] as num?)?.toInt();
    return AlbumInfo(
      id: '${a['id']}',
      sourceId: sourceId,
      name: '${a['name'] ?? ''}',
      cover: _image(a['url_cover']),
      artist: artists.firstOrNull,
      publishTime: release == null || release <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(release * 1000),
      size: (a['count_tracks'] as num?)?.toInt() ?? 0,
    );
  }

  PlaylistInfo _playlist(Map p, {List<Song>? tracks}) {
    final owner = p['owner'] is Map ? p['owner'] as Map : const {};
    final desc = '${p['desc'] ?? ''}'.trim();
    return PlaylistInfo(
      id: '${p['id']}',
      sourceId: sourceId,
      name: '${p['title'] ?? ''}',
      cover: _image(p['url_cover']),
      creator: owner['nickname'] as String?,
      description: desc.isEmpty ? null : desc,
      trackCount: (p['count_tracks'] as num?)?.toInt() ?? tracks?.length ?? 0,
      tracks: tracks,
    );
  }

  // ── 搜索 ──────────────────────────────────────────

  /// 某一类的搜索结果（每项的 entity 中按类型给出 track / album / playlist）。
  Future<List<Map>> _search(String kind, String keyword, int offset, int count) async {
    final params = {'q': keyword, 'cursor': '$offset', 'count': '$count', ..._web};
    var j = await _json('$_api/search/$kind', params);
    // 网关降级时返回空内容（没有 result_groups）；真正没有结果时 result_groups 存在而 data 为空。
    if (j['result_groups'] is! List && kind == 'track') {
      await Future<void>.delayed(retryDelay);
      j = await _json('$_api/search/$kind', params);
      if (j['result_groups'] is! List) throw const QishuiThrottled();
    }
    final groups = j['result_groups'];
    if (groups is! List) return const [];
    return [
      for (final g in groups.whereType<Map>())
        for (final item in (g['data'] is List ? g['data'] as List : const []).whereType<Map>())
          if (item['entity'] is Map && (item['entity'] as Map)[kind] is Map) (item['entity'] as Map)[kind] as Map,
    ];
  }

  @override
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) async {
    // 平台每页最多 20 条。
    final count = limit.clamp(1, 20);
    Future<List<Song>> songs() async => [for (final t in await _search('track', keyword, offset, count)) _song(t)];
    Future<List<AlbumInfo>> albums(int n) async => [for (final a in await _search('album', keyword, offset, n)) _album(a)];
    Future<List<PlaylistInfo>> playlists(int n) async => [for (final p in await _search('playlist', keyword, offset, n)) _playlist(p)];
    switch (type) {
      case SearchType.song:
        final s = await songs();
        return SearchResult(songs: s, bestSong: s.firstOrNull);
      case SearchType.album:
        return SearchResult(albums: await albums(count));
      case SearchType.playlist:
        return SearchResult(playlists: await playlists(count));
      case SearchType.artist:
        // 汽水音乐没有公开的歌手页。
        return const SearchResult();
      case SearchType.all:
        final r = await Future.wait([
          songs(),
          albums(6).catchError((Object _) => <AlbumInfo>[]),
          playlists(6).catchError((Object _) => <PlaylistInfo>[]),
        ]);
        final s = r[0] as List<Song>;
        final pls = r[2] as List<PlaylistInfo>;
        return SearchResult(songs: s, albums: r[1] as List<AlbumInfo>, playlists: pls, bestSong: s.firstOrNull, bestPlaylist: pls.firstOrNull);
    }
  }

  // ── 首页与发现 ────────────────────────────────────
  //
  // 汽水音乐的排行榜与推荐接口只对官方客户端开放，这里用搜索“汽水热歌”排在前面的歌单代替。

  static const _hotKeyword = '汽水热歌';

  @override
  Future<List<PlaylistInfo>> recommendPlaylists({int limit = 12}) async {
    return [for (final p in await _search('playlist', _hotKeyword, 0, limit.clamp(1, 20))) _playlist(p)];
  }

  @override
  Future<HomeFeed> homeFeed() async {
    final playlists = await recommendPlaylists();
    if (playlists.isEmpty) return const HomeFeed(daily: [], playlists: []);
    final top = await playlist(playlists.first.id);
    // 会员歌曲只能试听，免费歌曲排在前面。
    final tracks = top.tracks ?? const <Song>[];
    final daily = [...tracks.where((s) => !s.vip), ...tracks.where((s) => s.vip)].take(30).toList();
    return HomeFeed(daily: daily, playlists: playlists);
  }

  // ── 详情 ──────────────────────────────────────────

  @override
  Future<PlaylistInfo> playlist(String id) async {
    const page = 100;
    Map? info;
    final songs = <Song>[];
    final seen = <String>{};
    var cursor = '0';
    // 最多取 1000 首，避免超大歌单一直翻页。
    for (var i = 0; i < 10; i++) {
      final j = await _json('$_api/pc/playlist/detail', {'playlist_id': id, 'cursor': cursor, 'cnt': '$page', ..._web, 'channel': 'pc_web'});
      if (j['playlist'] is! Map) {
        if (info == null) throw StateError('汽水音乐歌单不存在或已被删除');
        break;
      }
      info ??= j['playlist'] as Map;
      final items = j['media_resources'] is List ? j['media_resources'] as List : const [];
      for (final m in items.whereType<Map>()) {
        final entity = m['entity'] is Map ? m['entity'] as Map : const {};
        final wrapper = entity['track_wrapper'] is Map ? entity['track_wrapper'] as Map : const {};
        final t = wrapper['track'] ?? entity['track'];
        if (t is Map && seen.add('${t['id']}')) songs.add(_song(t));
      }
      final next = '${j['next_cursor'] ?? ''}';
      final total = (info['count_tracks'] as num?)?.toInt() ?? 0;
      if (items.isEmpty || next.isEmpty || next == cursor || next == '0' || (total > 0 && songs.length >= total)) break;
      cursor = next;
    }
    return _playlist(info!, tracks: songs);
  }

  @override
  Future<AlbumInfo> album(String id) async {
    final data = _routerData(await _text('$_share/album', {'album_id': id}));
    final page = ((data['loaderData'] as Map?)?['album_page'] as Map?) ?? const {};
    final info = page['albumInfo'];
    if (info is! Map) throw StateError('汽水音乐专辑不存在或已下架');
    final a = _album(info);
    final songs = [for (final t in (page['trackList'] is List ? page['trackList'] as List : const []).whereType<Map>()) _song(t)];
    return AlbumInfo(id: a.id, sourceId: sourceId, name: a.name, cover: a.cover, artist: a.artist, publishTime: a.publishTime, songs: songs, size: a.size == 0 ? songs.length : a.size);
  }

  // ── 播放 ──────────────────────────────────────────

  Future<Map<String, dynamic>> _track(String id) async {
    final cached = _tracks[id];
    if (cached != null && DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) return cached.$2;
    final j = await _json(_seo, {'track_id': id, 'device_platform': 'web'});
    if (j['seo_track'] is! Map && j['track_player'] is! Map) throw StateError('汽水音乐没有返回这首歌的信息');
    if (_tracks.length > 50) _tracks.remove(_tracks.keys.first);
    _tracks[id] = (DateTime.now(), j);
    return j;
  }

  /// 平台的音质档位：medium 约 64k、higher 约 128k、highest 约 256k AAC。
  static const _qualities = {'medium': AudioQuality.standard, 'higher': AudioQuality.higher, 'highest': AudioQuality.exhigh};

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async {
    final j = await _track(song.id);
    final player = j['track_player'] is Map ? j['track_player'] as Map : const {};
    final raw = player['video_model'];
    final model = raw is String && raw.isNotEmpty ? jsonDecode(raw) as Map : (raw is Map ? raw : const {});
    final track = ((j['seo_track'] as Map?)?['track'] as Map?) ?? const {};
    // 云音不解密：带加密信息的音频（官方客户端的会员整曲）一律跳过。
    final encrypted = '${model['kid'] ?? ''}'.isNotEmpty || model['encrypt_info'] != null || model['encrypt'] == true;
    final candidates = <(AudioQuality, String)>[];
    if (!encrypted) {
      for (final v in (model['video_list'] is List ? model['video_list'] as List : const []).whereType<Map>()) {
        if (v['encrypt_info'] != null || v['play_auth'] != null) continue;
        final meta = v['video_meta'] is Map ? v['video_meta'] as Map : const {};
        final q = _qualities['${meta['quality']}'];
        final url = '${v['main_url'] ?? ''}'.isNotEmpty ? '${v['main_url']}' : '${v['backup_url'] ?? ''}';
        if (q != null && url.startsWith('http')) candidates.add((q, url));
      }
    }
    if (candidates.isEmpty) return const StreamInfo(note: '汽水音乐没有提供这首歌的播放地址');
    // 选不高于所选音质的最高一档；都更高时用最低一档。
    candidates.sort((a, b) => b.$1.index.compareTo(a.$1.index));
    final pick = candidates.firstWhere((c) => c.$1.index <= quality.index, orElse: () => candidates.last);
    final full = (track['duration'] as num?)?.toDouble() ?? song.duration.inMilliseconds.toDouble();
    final got = ((model['video_duration'] as num?)?.toDouble() ?? 0) * 1000;
    final trial = _vipOnly(track) || (full > 0 && got > 0 && got < full - 5000);
    final volume = model['volume'] is Map ? model['volume'] as Map : const {};
    return StreamInfo(
      url: pick.$2,
      quality: pick.$1,
      trial: trial,
      note: trial ? _trialNote : null,
      headers: const {'User-Agent': _ua},
      peak: (volume['peak'] as num?)?.toDouble(),
      cover: _image((track['album'] as Map?)?['url_cover']),
    );
  }

  @override
  Future<String?> songCover(Song song) async {
    final track = ((await _track(song.id))['seo_track'] as Map?)?['track'] as Map?;
    return _image((track?['album'] as Map?)?['url_cover']);
  }

  @override
  Future<Lyrics> lyrics(Song song) async {
    final j = await _track(song.id);
    final l = j['lyric'] is Map ? j['lyric'] as Map : const {};
    final content = '${l['content'] ?? ''}';
    if (content.trim().isEmpty) return Lyrics.empty;
    final tr = l['translations'] is Map ? '${(l['translations'] as Map)['cn'] ?? ''}' : '';
    return l['type'] == 'krc' || _krcLine.hasMatch(content.trimLeft()) ? parseQishuiKrc(content, translation: tr) : parseLrc(content, translation: tr);
  }
}

final _krcLine = RegExp(r'^\[(\d+),(\d+)\]');
final _krcWord = RegExp(r'<(\d+),(\d+),-?\d+>([^<]*)');

/// 解析汽水音乐的逐字歌词：`[行开始,行时长]<字偏移,字时长,0>字…`，时间为毫秒，字的时间相对于行开始。
/// 翻译以 LRC 给出，按最接近的行开始时间（1.5 秒内）匹配。
Lyrics parseQishuiKrc(String krc, {String translation = ''}) {
  final lines = <LyricLine>[];
  for (final raw in const LineSplitter().convert(krc)) {
    final m = _krcLine.firstMatch(raw.trim());
    if (m == null) continue;
    final start = int.parse(m.group(1)!);
    final words = [
      for (final w in _krcWord.allMatches(raw))
        if (w.group(3)!.isNotEmpty) LyricWord(Duration(milliseconds: start + int.parse(w.group(1)!)), Duration(milliseconds: int.parse(w.group(2)!)), w.group(3)!),
    ];
    final text = words.map((w) => w.text).join().trim();
    if (text.isEmpty) continue;
    lines.add(LyricLine(Duration(milliseconds: start), text, words: words, duration: Duration(milliseconds: int.parse(m.group(2)!))));
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  if (lines.isEmpty) return Lyrics.empty;
  final tr = parseLrc(translation).lines.where((l) => l.text.isNotEmpty);
  final best = <int, (Duration, String)>{};
  for (final t in tr) {
    var k = 0;
    for (var i = 1; i < lines.length; i++) {
      if ((lines[i].time - t.time).abs() < (lines[k].time - t.time).abs()) k = i;
    }
    final d = (lines[k].time - t.time).abs();
    if (d <= const Duration(milliseconds: 1500) && (best[k] == null || d < best[k]!.$1)) best[k] = (d, t.text);
  }
  return Lyrics([
    for (var i = 0; i < lines.length; i++)
      best[i] == null ? lines[i] : LyricLine(lines[i].time, lines[i].text, translation: best[i]!.$2, words: lines[i].words, duration: lines[i].duration),
  ]);
}
