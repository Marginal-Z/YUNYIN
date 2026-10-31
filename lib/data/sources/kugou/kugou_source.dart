import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/text_decode.dart';
import '../../models.dart';
import '../../song_matcher.dart';
import '../music_source.dart';
import '../netease/netease_source.dart' show parseLrc;

/// 酷狗音乐播放源：搜索、热搜、排行榜、封面与歌词来自酷狗公开接口。
///
/// 酷狗的播放地址接口现在要求设备验证（游客请求返回“本次请求需要验证”），且多数歌曲需要会员。
/// 因此播放时先尝试酷狗网页播放接口，取不到地址时自动在 [fallback]（网易云音乐）中匹配同一首歌
/// （歌名、歌手、时长，排除翻唱与伴奏）并播放其音频；都找不到时提示无法播放。
class KugouSource extends MusicSource {
  KugouSource(this.fallback, {Dio? dio})
    : _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15), responseType: ResponseType.plain));

  static const sourceId = 'kugou';
  static const _api = 'https://mobiles.kugou.com/api/v3';

  /// 换源播放用的播放源（网易云音乐）。
  final MusicSource? fallback;
  final Dio _dio;
  final Map<String, Song?> _matches = {};

  @override
  String get id => sourceId;

  @override
  String get name => '酷狗音乐';

  @override
  String get description => '酷狗的搜索、排行榜与歌词；无法直接播放的歌曲自动换用网易云的同一首歌播放';

  @override
  Set<SourceFeature> get features => const {
    SourceFeature.search,
    SourceFeature.hotSearch,
    SourceFeature.charts,
    SourceFeature.lyrics,
    SourceFeature.dailyRecommend,
  };

  /// 主要榜单（酷狗榜单 ID 与名称）。
  static const charts_ = [
    ('6666', '酷狗飙升榜'),
    ('23784', '网络红歌榜'),
    ('52144', '抖音热歌榜'),
    ('31308', '华语新歌榜'),
    ('31310', '欧美新歌榜'),
    ('33160', '电音热歌榜'),
    ('21335', '繁星音乐榜'),
  ];

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
    );
  }

  ({String hash, String audio, String album}) _ids(Song s) {
    final p = s.id.split(':');
    return (hash: p.first, audio: p.length > 1 ? p[1] : '', album: p.length > 2 ? p[2] : '');
  }

  // ── 搜索 ──────────────────────────────────────────

  @override
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) async {
    if (type != SearchType.all && type != SearchType.song) return const SearchResult();
    final page = offset ~/ limit + 1;
    final j = await _get('$_api/search/song?format=json&keyword=${Uri.encodeQueryComponent(keyword)}&page=$page&pagesize=$limit&showtype=1');
    final info = ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>();
    final songs = [for (final x in info) _song(x)];
    return SearchResult(songs: songs, bestSong: songs.firstOrNull);
  }

  @override
  Future<List<HotSearch>> hotSearches() async {
    final j = await _get('$_api/search/hot?format=json&plat=0&count=20');
    final info = ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>();
    return [for (final x in info) HotSearch('${x['keyword']}')];
  }

  // ── 排行榜与首页 ──────────────────────────────────────

  Future<List<Song>> _rank(String rankId, {int size = 100}) async {
    final j = await _get('$_api/rank/song?rankid=$rankId&page=1&pagesize=$size&area_code=1&plat=2&version=9108');
    final info = ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>();
    return [for (final x in info) _song(x)];
  }

  @override
  Future<PlaylistInfo> playlist(String id) async {
    final rankId = id.startsWith('rank:') ? id.substring(5) : id;
    final name = charts_.where((c) => c.$1 == rankId).firstOrNull?.$2 ?? '酷狗榜单';
    final songs = await _rank(rankId);
    return PlaylistInfo(
      id: 'rank:$rankId',
      sourceId: sourceId,
      name: name,
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
    final previews = await Future.wait([for (final c in charts_) _rank(c.$1, size: 3).catchError((Object _) => <Song>[])]);
    return [
      for (var i = 0; i < charts_.length; i++)
        ChartInfo(
          id: 'rank:${charts_[i].$1}',
          name: charts_[i].$2,
          cover: previews[i].firstOrNull?.coverUrl,
          preview: [for (final s in previews[i]) '${s.name} - ${s.artistText}'],
        ),
    ];
  }

  @override
  Future<List<PlaylistInfo>> recommendPlaylists({int limit = 12}) async {
    final list = await charts();
    return [
      for (final c in list.take(limit)) PlaylistInfo(id: c.id, sourceId: sourceId, name: c.name, cover: c.cover, creator: '酷狗音乐', kind: PlaylistKind.chart),
    ];
  }

  @override
  Future<HomeFeed> homeFeed() async {
    final results = await Future.wait([_rank('6666', size: 30), recommendPlaylists(limit: 6)]);
    return HomeFeed(daily: results[0] as List<Song>, playlists: results[1] as List<PlaylistInfo>);
  }

  // ── 播放 ──────────────────────────────────────────

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async {
    final direct = await _webPlayUrl(song);
    if (direct != null) return StreamInfo(url: direct, quality: AudioQuality.standard);
    final match = await _match(song);
    if (match == null || fallback == null) {
      throw Exception('酷狗暂时无法播放这首歌（需要验证或会员），网易云音乐中也没有找到同一首歌');
    }
    return fallback!.stream(match, quality);
  }

  /// 酷狗网页播放接口（签名参数）。目前游客请求通常返回需要验证，取不到时返回 null。
  Future<String?> _webPlayUrl(Song song) async {
    const key = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
    final ids = _ids(song);
    if (ids.hash.isEmpty) return null;
    try {
      final mid = md5.convert(utf8.encode('yunyin-${DateTime.now().millisecondsSinceEpoch ~/ 86400000}')).toString();
      final params = <String, String>{
        'srcappid': '2919',
        'clientver': '20000',
        'clienttime': '${DateTime.now().millisecondsSinceEpoch}',
        'mid': mid,
        'uuid': mid,
        'dfid': '-',
        'appid': '1014',
        'platid': '4',
        'hash': ids.hash,
        'album_id': ids.album.isEmpty ? '0' : ids.album,
        'album_audio_id': ids.audio,
        'token': '',
        'userid': '0',
      };
      final keys = params.keys.toList()..sort();
      params['signature'] = md5.convert(utf8.encode('$key${keys.map((k) => '$k=${params[k]}').join()}$key')).toString();
      final res = await _dio.get<String>(
        'https://wwwapi.kugou.com/play/songinfo',
        queryParameters: params,
        options: Options(headers: {'Cookie': 'kg_mid=$mid', 'User-Agent': 'Mozilla/5.0'}, receiveTimeout: const Duration(seconds: 6)),
      );
      final j = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
      final data = j['data'];
      if (data is! Map) return null;
      final url = '${data['play_url'] ?? data['play_backup_url'] ?? ''}';
      return url.startsWith('http') ? url.replaceFirst('http://', 'https://') : null;
    } catch (e) {
      debugPrint('kugou play url: $e');
      return null;
    }
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
    final m = await _match(song);
    return m == null || fallback == null ? Lyrics.empty : fallback!.lyrics(m);
  }
}
