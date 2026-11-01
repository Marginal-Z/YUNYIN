import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../lx/lx_sources.dart';
import '../../models.dart';
import '../music_source.dart';
import '../netease/netease_source.dart' show parseLrc;

/// 洛雪曲库：独立于网易云、QQ 音乐、酷狗的第四个平台模式。
///
/// 与洛雪音乐相同，曲库（搜索、排行榜、歌词）来自酷我音乐的公开接口，播放地址只通过用户导入的
/// 洛雪音源脚本获取（脚本中的酷我 kw 平台）。没有导入或启用音源时可以浏览，但无法播放。
class LxLibrarySource extends MusicSource {
  LxLibrarySource(this.lx, {Dio? dio}) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15)));

  static const sourceId = 'lx';

  final LxSources lx;
  final Dio _dio;

  @override
  String get id => sourceId;

  @override
  String get name => '洛雪曲库';

  @override
  String get description => '酷我曲库，通过导入的洛雪音源播放';

  @override
  Set<SourceFeature> get features => const {SourceFeature.search, SourceFeature.hotSearch, SourceFeature.charts, SourceFeature.dailyRecommend, SourceFeature.lyrics};

  Future<Map<String, dynamic>> _get(String url) async {
    final res = await _dio.get<String>(url, options: Options(responseType: ResponseType.plain, headers: {'User-Agent': 'Mozilla/5.0'}));
    return jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
  }

  static String? _cover(String? short, {int size = 500}) {
    if (short == null || short.isEmpty) return null;
    // 酷我的图片服务器（kwcdn）不支持 https，保持 http（macOS / iOS 在 Info.plist 中为 kuwo.cn 放行）。
    if (short.startsWith('http')) return short;
    // 搜索结果给出“120/s3s94/93/xxx.jpg”这样的相对路径。
    return 'http://img1.kwcdn.kuwo.cn/star/albumcover/$size/${short.replaceFirst(RegExp(r'^\d+/'), '')}';
  }

  Song _song({required String rid, required String name, required String artist, String album = '', String albumId = '', int seconds = 0, String? cover}) => Song(
    id: rid,
    sourceId: sourceId,
    name: name,
    artists: [
      for (final a in artist.split(RegExp(r'[&、/]')))
        if (a.trim().isNotEmpty) ArtistRef('kw:${a.trim()}', a.trim()),
    ],
    album: album.isEmpty ? null : AlbumRef(albumId, album, cover: cover),
    duration: Duration(seconds: seconds),
    cover: cover,
  );

  /// 酷我接口中的文字会把 &、空格等写成 HTML 实体。
  static String _text(Object? v) => '${v ?? ''}'.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&apos;', "'").trim();

  // ── 搜索 ──────────────────────────────────────────

  @override
  List<SearchType> get searchTypes => const [SearchType.all, SearchType.song];

  @override
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) async {
    if (type != SearchType.all && type != SearchType.song) return const SearchResult();
    final j = await _get(
      'http://search.kuwo.cn/r.s?client=kt&all=${Uri.encodeQueryComponent(keyword)}&pn=${offset ~/ limit}&rn=$limit'
      '&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1&show_copyright_off=1&newver=1&ft=music&cluster=0&strategy=2012'
      '&encoding=utf8&rformat=json&vermerge=1&mobi=1&issubtitle=1',
    );
    final songs = [
      for (final x in (j['abslist'] as List? ?? const []).cast<Map>())
        _song(
          rid: '${x['MUSICRID'] ?? x['DC_TARGETID'] ?? ''}'.replaceFirst('MUSIC_', ''),
          name: _text(x['SONGNAME']),
          artist: _text(x['ARTIST']),
          album: _text(x['ALBUM']),
          albumId: '${x['ALBUMID'] ?? ''}',
          seconds: int.tryParse('${x['DURATION'] ?? 0}') ?? 0,
          cover: _cover(x['web_albumpic_short'] as String?),
        ),
    ];
    return SearchResult(songs: songs, bestSong: songs.firstOrNull, songCount: int.tryParse('${j['TOTAL'] ?? ''}') ?? songs.length);
  }

  @override
  Future<List<HotSearch>> hotSearches() async {
    try {
      final j = await _get('http://hotword.kuwo.cn/hotword.s?prod=kwplayer_ar_9.3.0.1&corp=kuwo&newver=2&vipver=9.3.0.1&source=kwplayer_ar_9.3.0.1_40.apk&p2p=1&notrace=0&uid=0&plat=ar&rformat=json&encoding=utf8&tabid=1');
      return [for (final t in (j['tagvalue'] as List? ?? const []).cast<Map>()) HotSearch('${t['key']}')];
    } catch (e) {
      debugPrint('kuwo hot: $e');
      return const [];
    }
  }

  // ── 排行榜与首页 ──────────────────────────────────────

  final _boardNames = <String, String>{};

  @override
  Future<List<ChartInfo>> charts() async {
    final j = await _get('http://qukudata.kuwo.cn/q.k?op=query&cont=tree&node=2&pn=0&rn=1000&fmt=json&level=2');
    return [
      for (final c in (j['child'] as List? ?? const []).cast<Map>())
        if ('${c['sourceid'] ?? ''}'.isNotEmpty)
          () {
            final id = '${c['sourceid']}';
            _boardNames[id] = _text(c['name']);
            return ChartInfo(
              id: 'bang:$id',
              name: _text(c['name']),
              cover: _cover(c['pic'] as String?),
              group: '酷我榜单',
            );
          }(),
    ];
  }

  /// 榜单歌曲不带封面：按歌曲查询封面地址（前 [count] 首并行，查不到时显示占位图）。
  Future<Map<String, String>> _covers(Iterable<String> rids, {int count = 40}) async {
    final out = <String, String>{};
    await Future.wait([
      for (final rid in rids.take(count))
        _dio
            .get<String>(
              'http://artistpicserver.kuwo.cn/pic.web?corp=kuwo&type=rid_pic&pictype=500&size=500&rid=$rid',
              options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 3)),
            )
            .then((r) {
              final url = (r.data ?? '').trim();
              if (url.startsWith('http')) out[rid] = url;
            })
            .catchError((Object _) {}),
    ]);
    return out;
  }

  Future<List<Song>> _board(String id, {int limit = 100}) async {
    final j = await _get('http://kbangserver.kuwo.cn/ksong.s?from=pc&fmt=json&pn=0&rn=$limit&type=bang&data=content&id=$id&show_copyright_off=0&pcmp4=1&isbang=1');
    final list = (j['musiclist'] as List? ?? const []).cast<Map>();
    final covers = await _covers([for (final x in list) '${x['id']}']);
    return [
      for (final x in list)
        _song(
          rid: '${x['id']}',
          name: _text(x['name']),
          artist: _text(x['artist']),
          album: _text(x['album']),
          albumId: '${x['albumid'] ?? ''}',
          seconds: int.tryParse('${x['song_duration'] ?? x['duration'] ?? 0}') ?? 0,
          cover: covers['${x['id']}'],
        ),
    ];
  }

  @override
  Future<PlaylistInfo> playlist(String id) async {
    final board = id.startsWith('bang:') ? id.substring(5) : id;
    if (!_boardNames.containsKey(board)) await charts().catchError((Object _) => <ChartInfo>[]);
    final songs = await _board(board);
    return PlaylistInfo(
      id: 'bang:$board',
      sourceId: sourceId,
      name: _boardNames[board] ?? '酷我榜单',
      cover: songs.firstOrNull?.coverUrl,
      creator: '酷我音乐',
      trackCount: songs.length,
      kind: PlaylistKind.chart,
      tracks: songs,
    );
  }

  @override
  Future<PlaylistInfo> soaringChart() => playlist('bang:93');

  @override
  Future<HomeFeed> homeFeed() async => HomeFeed(daily: await _board('93', limit: 30), playlists: const []);

  // ── 播放与歌词 ──────────────────────────────────────

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async {
    if (lx.enabled.isEmpty) throw Exception('洛雪曲库通过洛雪音源播放：请先在“设置 → 洛雪音源”中导入并启用音源');
    final info = await lx.resolve(song, quality);
    if (info?.url == null) throw Exception('已启用的洛雪音源都不支持酷我（kw）平台');
    return info!;
  }

  @override
  Future<Lyrics> lyrics(Song song) async {
    try {
      final j = await _get('http://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=${song.id}');
      final lines = ((j['data'] as Map?)?['lrclist'] as List? ?? const []).cast<Map>();
      if (lines.length < 3) return Lyrics.empty;
      final buf = StringBuffer();
      for (final l in lines) {
        final t = double.tryParse('${l['time']}') ?? 0;
        final m = t ~/ 60;
        final s = t - m * 60;
        buf.writeln('[${m.toString().padLeft(2, '0')}:${s.toStringAsFixed(2).padLeft(5, '0')}]${_text(l['lineLyric'])}');
      }
      return parseLrc(buf.toString());
    } catch (e) {
      debugPrint('kuwo lyrics: $e');
      return Lyrics.empty;
    }
  }
}
