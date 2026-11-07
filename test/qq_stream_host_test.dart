import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';

/// 模拟 QQ 音乐：取地址接口只给出试听片段，各播放服务器按 [hosts] 中的状态码与延迟回应。
QQMusicSource fake(Map<String, (int, int)> hosts, List<String> probed) {
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          if (o.method == 'POST') {
            final names = ((jsonDecode(o.data as String) as Map)['req_0']['param']['filename'] as List).cast<String>();
            final data = {
              'sip': ['http://ws.stream.qqmusic.qq.com/'],
              'midurlinfo': [for (final n in names) {'purl': n.startsWith('RS02') ? '$n?vkey=1' : ''}],
            };
            h.resolve(Response(requestOptions: o, statusCode: 200, data: jsonEncode({'req_0': {'code': 0, 'data': data}})));
            return;
          }
          final host = '${o.uri.scheme}://${o.uri.host}/';
          probed.add(host);
          final (code, ms) = hosts[host] ?? (403, 0);
          await Future<void>.delayed(Duration(milliseconds: ms));
          h.resolve(Response(requestOptions: o, statusCode: code, data: <int>[]));
        },
      ),
    );
  return QQMusicSource(dio: dio);
}

const song = Song(id: 'mid1:media1', sourceId: 'qq', name: '晴天');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('同时确认各个播放服务器，取最先可用的（http 优先），不等前面较慢的服务器', () async {
    final probed = <String>[];
    final qq = fake({
      'http://ws.stream.qqmusic.qq.com/': (403, 600),
      'http://sjy6.stream.qqmusic.qq.com/': (206, 20),
      'https://sjy6.stream.qqmusic.qq.com/': (206, 150),
    }, probed);
    final sw = Stopwatch()..start();
    final info = await qq.stream(song, AudioQuality.exhigh);
    expect(info.url, 'http://sjy6.stream.qqmusic.qq.com/RS02media1.mp3?vkey=1');
    expect(info.trial, isTrue);
    expect(sw.elapsedMilliseconds, lessThan(500));
  });

  test('所有服务器都没有这个文件时很快给出原因，而不是逐个等完', () async {
    final probed = <String>[];
    final qq = fake({for (final h in ['ws', 'sjy6', 'isure']) for (final s in ['http', 'https']) '$s://$h.stream.qqmusic.qq.com/': (404, 200)}, probed);
    final sw = Stopwatch()..start();
    await expectLater(qq.stream(song, AudioQuality.exhigh), throwsA(isA<Exception>()));
    // 安卓与网页两种方式各确认一轮，每轮所有服务器同时请求。
    expect(sw.elapsedMilliseconds, lessThan(1500));
    expect(probed.toSet(), containsAll(['http://sjy6.stream.qqmusic.qq.com/', 'https://sjy6.stream.qqmusic.qq.com/']));
  });
}
