import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/qishui/qishui_source.dart';

/// 按接口路径模拟汽水音乐的返回；路由返回字符串时原样作为响应内容（分享页 HTML、空内容）。
Dio _dio(Map<String, Object? Function(RequestOptions o)> routes, {List<RequestOptions>? log}) {
  final dio = Dio(BaseOptions(responseType: ResponseType.plain));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        log?.add(o);
        final route = routes[o.uri.path];
        final body = route == null ? {'status_code': 404} : route(o);
        h.resolve(Response(requestOptions: o, statusCode: 200, data: body is String ? body : jsonEncode(body)));
      },
    ),
  );
  return dio;
}

Map<String, Object?> _cover(String uri) => {
  'uri': uri,
  'urls': ['https://p3-luna.douyinpic.com/img/', 'https://p6-luna.douyinpic.com/img/'],
};

Map<String, Object?> _track(String id, {bool vip = false, int duration = 200000}) => {
  'id': id,
  'name': '歌$id',
  'duration': duration,
  'artists': [
    {'id': 'a1', 'name': '歌手甲'},
    {'id': 'a2', 'name': '歌手乙'},
  ],
  'album': {'id': 'al$id', 'name': '专辑$id', 'url_cover': _cover('tos-cn/c$id')},
  'label_info': {'only_vip_playable': vip},
};

Map<String, Object?> _video(String quality, {Map<String, Object?> extra = const {}}) => {
  'main_url': 'https://v3-luna.douyinvod.com/$quality.m4a',
  'backup_url': 'https://v11-luna.douyinvod.com/$quality.m4a',
  'video_meta': {'quality': quality, 'vtype': 'm4a'},
  ...extra,
};

Map<String, Object?> _seo(Map<String, Object?> track, List<Map<String, Object?>> videos, {double seconds = 200, Map<String, Object?> lyric = const {}, Map<String, Object?> model = const {}}) => {
  'status_info': {'log_id': 'x'},
  'seo_track': {'track': track},
  'lyric': lyric,
  'track_player': {
    'video_model': jsonEncode({
      'video_duration': seconds,
      'video_list': videos,
      'volume': {'loudness': -7.4, 'peak': 0.98},
      ...model,
    }),
  },
};

void main() {
  const free = Song(id: '101', sourceId: 'qishui', name: '歌101');

  test('搜索歌曲：网页端参数、不带设备标识，每页最多 20 条；会员歌曲标为 VIP', () async {
    final log = <RequestOptions>[];
    final dio = _dio({
      '/luna/search/track': (_) => {
        'result_groups': [
          {
            'id': 'tracks',
            'data': [
              {'entity': {'track': _track('101')}},
              {'entity': {'track': _track('102', vip: true)}},
            ],
          },
        ],
      },
    }, log: log);
    final r = await QishuiSource(dio: dio).search('晴天', type: SearchType.song, offset: 20, limit: 50);
    expect(r.songs.map((s) => s.id), ['101', '102']);
    final s = r.songs.first;
    expect(s.sourceId, 'qishui');
    expect(s.artistText, '歌手甲 / 歌手乙');
    expect(s.album?.name, '专辑101');
    expect(s.duration, const Duration(milliseconds: 200000));
    expect(s.coverUrl, 'https://p3-luna.douyinpic.com/img/tos-cn/c101~c5_500x500.jpg');
    expect(s.fee, SongFee.free);
    expect(r.songs.last.fee, SongFee.vip);
    final q = log.single.queryParameters;
    expect(log.single.uri.host, 'api.qishui.com');
    expect(q, {'q': '晴天', 'cursor': '20', 'count': '20', 'aid': '386088', 'device_platform': 'web'});
    expect(log.single.headers['User-Agent'], contains('Mozilla/5.0'));
    dio.close();
  });

  test('歌曲搜索返回空内容：稍等重试一次；仍为空时提示稍后再试，不再重试', () async {
    var calls = 0;
    var dio = _dio({
      '/luna/search/track': (_) => ++calls == 1
          ? ''
          : {
              'result_groups': [
                {
                  'data': [
                    {'entity': {'track': _track('101')}},
                  ],
                },
              ],
            },
    });
    final r = await QishuiSource(dio: dio, retryDelay: Duration.zero).search('晴天', type: SearchType.song);
    expect(r.songs, hasLength(1));
    expect(calls, 2);
    dio.close();

    calls = 0;
    dio = _dio({
      '/luna/search/track': (_) {
        calls++;
        return '';
      },
    });
    await expectLater(QishuiSource(dio: dio, retryDelay: Duration.zero).search('晴天', type: SearchType.song), throwsA(isA<QishuiThrottled>()));
    expect(calls, 2);
    dio.close();

    // 真正没有结果时 result_groups 存在而 data 为空：不重试。
    calls = 0;
    dio = _dio({
      '/luna/search/track': (_) {
        calls++;
        return {
          'result_groups': [
            {'data': []},
          ],
        };
      },
    });
    expect((await QishuiSource(dio: dio, retryDelay: Duration.zero).search('不存在的歌', type: SearchType.song)).songs, isEmpty);
    expect(calls, 1);
    dio.close();
  });

  test('综合搜索：歌曲、专辑、歌单；不支持歌手分类', () async {
    final dio = _dio({
      '/luna/search/track': (_) => {
        'result_groups': [
          {
            'data': [
              {'entity': {'track': _track('101')}},
            ],
          },
        ],
      },
      '/luna/search/album': (_) => {
        'result_groups': [
          {
            'data': [
              {
                'entity': {
                  'album': {
                    'id': 'al9',
                    'name': '卡农',
                    'count_tracks': 3,
                    'release_date': 1490198400,
                    'url_cover': _cover('tos-cn/al9'),
                    'artists': [
                      {'id': 'a1', 'name': 'dylanf'},
                    ],
                  },
                },
              },
            ],
          },
        ],
      },
      '/luna/search/playlist': (_) => {
        'result_groups': [
          {
            'data': [
              {
                'entity': {
                  'playlist': {
                    'id': 'p1',
                    'title': '卡农合集',
                    'count_tracks': 10,
                    'url_cover': _cover('tos-cn/p1'),
                    'owner': {'nickname': '慢点'},
                  },
                },
              },
            ],
          },
        ],
      },
    });
    final qs = QishuiSource(dio: dio);
    expect(qs.searchTypes, isNot(contains(SearchType.artist)));
    final r = await qs.search('卡农');
    expect(r.bestSong?.id, '101');
    expect(r.albums.single.artist?.name, 'dylanf');
    expect(r.albums.single.size, 3);
    expect(r.albums.single.publishTime?.year, 2017);
    expect(r.playlists.single.creator, '慢点');
    expect(r.bestPlaylist?.id, 'p1');
    dio.close();
  });

  test('播放：选不高于所选音质的最高一档，都更高时用最低一档；歌曲信息缓存，歌词不再请求', () async {
    var calls = 0;
    final log = <RequestOptions>[];
    final dio = _dio({
      '/luna/h5/seo_track': (_) {
        calls++;
        return _seo(_track('101'), [_video('higher'), _video('highest'), _video('medium')], lyric: {'type': 'lrc', 'content': '[00:01.00]第一句\n[00:03.50]第二句'});
      },
    }, log: log);
    final qs = QishuiSource(dio: dio);
    final best = await qs.stream(free, AudioQuality.lossless);
    expect(best.url, 'https://v3-luna.douyinvod.com/highest.m4a');
    expect(best.quality, AudioQuality.exhigh);
    expect(best.trial, isFalse);
    expect(best.note, isNull);
    expect(best.peak, 0.98);
    expect(best.cover, 'https://p3-luna.douyinpic.com/img/tos-cn/c101~c5_500x500.jpg');
    expect((await qs.stream(free, AudioQuality.higher)).url, 'https://v3-luna.douyinvod.com/higher.m4a');
    expect((await qs.stream(free, AudioQuality.standard)).quality, AudioQuality.standard);
    final ly = await qs.lyrics(free);
    expect(ly.lines.map((l) => l.text), ['第一句', '第二句']);
    expect(calls, 1);
    expect(log.single.uri.host, 'beta-luna.douyin.com');
    expect(log.single.queryParameters, {'track_id': '101', 'device_platform': 'web'});
    dio.close();

    // 只有高档位时用最低一档；主地址为空时用备用地址。
    final dio2 = _dio({
      '/luna/h5/seo_track': (_) => _seo(_track('101'), [
        _video('highest'),
        _video('higher', extra: {'main_url': ''}),
      ]),
    });
    final low = await QishuiSource(dio: dio2).stream(free, AudioQuality.standard);
    expect(low.url, 'https://v11-luna.douyinvod.com/higher.m4a');
    expect(low.quality, AudioQuality.higher);
    dio2.close();
  });

  test('会员歌曲只有官方试听片段：标为试听并说明原因', () async {
    final dio = _dio({'/luna/h5/seo_track': (_) => _seo(_track('102', vip: true), [_video('higher')], seconds: 60)});
    final info = await QishuiSource(dio: dio).stream(const Song(id: '102', sourceId: 'qishui', name: '歌102', fee: SongFee.vip), AudioQuality.exhigh);
    expect(info.url, isNotNull);
    expect(info.trial, isTrue);
    expect(info.note, contains('试听'));
    dio.close();

    // 平台没标会员、但给出的音频明显比整首短：同样按试听处理。
    final dio2 = _dio({'/luna/h5/seo_track': (_) => _seo(_track('103'), [_video('higher')], seconds: 30)});
    expect((await QishuiSource(dio: dio2).stream(const Song(id: '103', sourceId: 'qishui', name: '歌103'), AudioQuality.exhigh)).trial, isTrue);
    dio2.close();
  });

  test('带加密信息的音频一律不播放（云音不解密）', () async {
    final dio = _dio({
      '/luna/h5/seo_track': (_) => _seo(_track('101'), [
        _video('highest', extra: {'encrypt_info': {'spade_a': 'x'}}),
        _video('higher'),
      ]),
    });
    final info = await QishuiSource(dio: dio).stream(free, AudioQuality.exhigh);
    expect(info.url, 'https://v3-luna.douyinvod.com/higher.m4a');
    dio.close();

    final dio2 = _dio({'/luna/h5/seo_track': (_) => _seo(_track('101'), [_video('higher')], model: {'kid': 'abc'})});
    final none = await QishuiSource(dio: dio2).stream(free, AudioQuality.exhigh);
    expect(none.url, isNull);
    expect(none.note, isNotNull);
    dio2.close();
  });

  test('逐字歌词：字的时间相对于行开始，换算为绝对时间；翻译按行开始时间匹配', () {
    final ly = parseQishuiKrc(
      '[3150,5330]<0,410,0>隐<1160,410,0>去<1570,400,0>了\n[9670,4130]<0,390,0>如<390,380,0>霜\n不是歌词的一行',
      translation: '[00:03.15]译一\n[00:09.70]译二',
    );
    expect(ly.lines, hasLength(2));
    expect(ly.wordSynced, isTrue);
    final first = ly.lines.first;
    expect(first.text, '隐去了');
    expect(first.time, const Duration(milliseconds: 3150));
    expect(first.duration, const Duration(milliseconds: 5330));
    expect(first.words!.map((w) => w.start.inMilliseconds), [3150, 4310, 4720]);
    expect(first.words!.last.duration, const Duration(milliseconds: 400));
    expect(first.translation, '译一');
    expect(ly.lines.last.translation, '译二');
  });

  test('歌词接口：krc 按逐字解析，lrc 带中文翻译', () async {
    final dio = _dio({
      '/luna/h5/seo_track': (o) => o.queryParameters['track_id'] == '101'
          ? _seo(_track('101'), [], lyric: {'type': 'krc', 'content': '[1000,800]<0,400,0>你<400,400,0>好'})
          : _seo(_track('102'), [], lyric: {
              'type': 'lrc',
              'content': '[00:01.00]Hello',
              'translations': {'cn': '[00:01.00]你好'},
            }),
    });
    final qs = QishuiSource(dio: dio);
    expect((await qs.lyrics(free)).lines.single.words, hasLength(2));
    final lrc = await qs.lyrics(const Song(id: '102', sourceId: 'qishui', name: '歌102'));
    expect(lrc.lines.single.text, 'Hello');
    expect(lrc.lines.single.translation, '你好');
    dio.close();
  });

  test('歌单：按 next_cursor 翻页、去重，直到取满歌单', () async {
    final log = <RequestOptions>[];
    final dio = _dio({
      '/luna/pc/playlist/detail': (o) {
        final first = o.queryParameters['cursor'] == '0';
        return {
          'playlist': {'id': 'p1', 'title': '热歌', 'count_tracks': 3, 'desc': ' 简介 ', 'owner': {'nickname': '慢点'}, 'url_cover': _cover('tos-cn/p1')},
          'next_cursor': first ? '2' : '4',
          'media_resources': [
            for (final id in first ? ['1', '2'] : ['2', '3'])
              {
                'entity': {
                  'track_wrapper': {'track': _track(id)},
                },
              },
          ],
        };
      },
    }, log: log);
    final pl = await QishuiSource(dio: dio).playlist('p1');
    expect(pl.tracks!.map((s) => s.id), ['1', '2', '3']);
    expect(pl.name, '热歌');
    expect(pl.description, '简介');
    expect(pl.creator, '慢点');
    expect(log.map((o) => o.queryParameters['cursor']), ['0', '2']);
    expect(log.first.queryParameters['channel'], 'pc_web');
    expect(log.first.queryParameters['device_platform'], 'web');
    dio.close();

    final dio2 = _dio({'/luna/pc/playlist/detail': (_) => {'status_code': 1, 'status_info': {'status_msg': 'ERR_RESOURCE_NOT_FOUND'}}});
    await expectLater(QishuiSource(dio: dio2).playlist('nope'), throwsA(isA<StateError>()));
    dio2.close();
  });

  test('专辑：解析官方分享页中的页面数据', () async {
    final data = {
      'loaderData': {
        'album_page': {
          'albumInfo': {
            'id': 'al9',
            'name': '卡农 "钢琴版" {经典}',
            'release_date': 1490198400,
            'url_cover': _cover('tos-cn/al9'),
            'artists': [
              {'id': 'a1', 'name': 'dylanf'},
            ],
          },
          'trackList': [_track('1'), _track('2')],
        },
      },
    };
    final html = '<html><script>window._ROUTER_DATA = ${jsonEncode(data)};</script><script>var x = {"a":1};</script></html>';
    final log = <RequestOptions>[];
    final dio = _dio({'/qishui/share/album': (_) => html}, log: log);
    final album = await QishuiSource(dio: dio).album('al9');
    expect(album.name, '卡农 "钢琴版" {经典}');
    expect(album.artist?.name, 'dylanf');
    expect(album.songs!.map((s) => s.id), ['1', '2']);
    expect(album.size, 2);
    expect(log.single.uri.host, 'music.douyin.com');
    expect(log.single.queryParameters, {'album_id': 'al9'});
    dio.close();

    final dio2 = _dio({'/qishui/share/album': (_) => '<html>出错了</html>'});
    await expectLater(QishuiSource(dio: dio2).album('x'), throwsA(isA<FormatException>()));
    dio2.close();
  });

  test('首页：热门歌单与第一个歌单的歌曲，免费歌曲排在前面', () async {
    final dio = _dio({
      '/luna/search/playlist': (o) => {
        'result_groups': [
          {
            'data': [
              for (final id in ['p1', 'p2'])
                {
                  'entity': {
                    'playlist': {'id': id, 'title': '歌单$id', 'count_tracks': 3},
                  },
                },
            ],
          },
        ],
      },
      '/luna/pc/playlist/detail': (o) => {
        'playlist': {'id': o.queryParameters['playlist_id'], 'title': '歌单', 'count_tracks': 3},
        'media_resources': [
          for (final t in [_track('1', vip: true), _track('2'), _track('3')])
            {
              'entity': {
                'track_wrapper': {'track': t},
              },
            },
        ],
      },
    });
    final feed = await QishuiSource(dio: dio).homeFeed();
    expect(feed.playlists.map((p) => p.id), ['p1', 'p2']);
    expect(feed.daily.map((s) => s.id), ['2', '3', '1']);
    dio.close();
  });
}
