import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';

void main() {
  test('综合搜索的歌曲接口失败时保留歌手和歌单，全部失败才报错', () async {
    var partial = true;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final Object response;
          if (options.uri.host == 'u.y.qq.com') {
            response = {
              'req': {'code': 2001},
            };
          } else if (options.uri.path.contains('smartbox')) {
            response = {
              'data': {
                'singer': {
                  'itemlist': partial
                      ? [
                          {'mid': 'artist', 'name': '周杰伦'},
                        ]
                      : [],
                },
              },
            };
          } else {
            response = {
              'data': {
                'list': partial
                    ? [
                        {'dissid': 'playlist', 'dissname': '歌单'},
                      ]
                    : [],
              },
            };
          }
          handler.resolve(Response<String>(requestOptions: options, statusCode: 200, data: jsonEncode(response)));
        },
      ),
    );
    final source = QQMusicSource(dio: dio);
    final result = await source.search('周杰伦');
    expect(result.songs, isEmpty);
    expect(result.artists.single.name, '周杰伦');
    expect(result.playlists.single.name, '歌单');
    partial = false;
    await expectLater(source.search('周杰伦'), throwsA(isA<QQApiException>()));
    dio.close();
  });

  for (final rejected in [false, true]) {
    test('QQ 搜索${rejected ? '遇到 2001 后使用同平台备用接口' : '正常返回歌曲'}', () async {
      final methods = <String>[];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final sent = jsonDecode(options.data as String) as Map<String, dynamic>;
            final method = (sent['req'] as Map)['method'] as String;
            methods.add(method);
            final desktop = method == 'DoSearchForQQMusicDesktop';
            final songs = [
              {
                'mid': 'song',
                'name': '晴天',
                'singer': [
                  {'mid': 'artist', 'name': '周杰伦'},
                ],
              },
            ];
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data: jsonEncode({
                  'req': {
                    'code': rejected && !desktop ? 2001 : 0,
                    'data': {
                      'body': desktop
                          ? {
                              'song': {'list': songs},
                            }
                          : {'item_song': songs},
                    },
                  },
                }),
              ),
            );
          },
        ),
      );
      final result = await QQMusicSource(dio: dio).search('晴天', type: SearchType.song);
      expect(methods, ['DoSearchForQQMusicMobile', if (rejected) 'DoSearchForQQMusicDesktop']);
      expect(result.songs.single.sourceId, 'qq');
      expect(result.songs.single.name, '晴天');
      dio.close();
    });
  }
}
