import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';

void main() {
  test('QQ 音乐分类歌单使用网页分类页接口，按页请求并读出封面、播放量与歌曲数', () async {
    SharedPreferences.setMockInitialValues({});
    final params = <Map>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            final req = (jsonDecode(o.data as String) as Map)['req'] as Map;
            params.add({'method': req['method'], ...req['param'] as Map});
            final data = {
              'content': {
                'total_cnt': 988,
                'v_item': [
                  {
                    'basic': {
                      'tid': 7534578257,
                      'title': '粤语女声',
                      'cover': {'big_url': 'http://qpic.y.qq.com/music_cover/abc/600?n=1'},
                      'play_cnt': 10093539,
                      'song_cnt': 77,
                      'creator': {'nick': '蓝莓 Cake'},
                      'desc': '轻柔',
                    },
                  },
                ],
              },
            };
            h.resolve(Response(requestOptions: o, statusCode: 200, data: jsonEncode({'code': 0, 'req': {'code': 0, 'data': data}})));
          },
        ),
      );
    final qq = QQMusicSource(dio: dio);
    final lists = await qq.categoryPlaylists('146', offset: 30, limit: 30);
    expect(params.single, containsPair('method', 'get_category_content'));
    expect(params.single, containsPair('category_id', 146));
    expect(params.single, containsPair('page', 1));
    final l = lists.single;
    expect(l.id, 'diss:7534578257');
    expect(l.name, '粤语女声');
    expect(l.cover, 'https://qpic.y.qq.com/music_cover/abc/600?n=1');
    expect(l.playCount, 10093539);
    expect(l.trackCount, 77);
    expect(l.creator, '蓝莓 Cake');
    dio.close();
  });
}
