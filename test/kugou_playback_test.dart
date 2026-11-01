import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/music_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const song = Song(id: 'hash:123:456', sourceId: 'kugou', name: '测试歌曲');

  test('酷狗播放使用登录时的设备标识，保留可用备用地址和试听状态', () async {
    RequestOptions? request;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: jsonEncode({
                'status': 1,
                'data': {'play_url': '', 'play_backup_url': 'http://audio.example/track.mp3', 'is_free_part': 1, 'bitrate': 320},
              }),
            ),
          );
        },
      ),
    );
    final source = KugouSource(dio: dio);
    await source.loginWithCookie('kg_mid=device-mid; kg_dfid=device-dfid; KuGoo=KugooID=123&t=token-test');
    final info = await source.stream(song, AudioQuality.exhigh);
    expect(request!.queryParameters['mid'], 'device-mid');
    expect(request!.queryParameters['dfid'], 'device-dfid');
    expect(request!.headers['Cookie'], contains('kg_dfid=device-dfid'));
    expect(info.url, 'http://audio.example/track.mp3');
    expect(info.trial, isTrue);
    expect(info.quality, AudioQuality.exhigh);
    expect(info.headers, isNot(contains('Cookie')));
    dio.close();
  });

  test('酷狗接口失败保留错误码，不把所有已登录失败都归因为缺少会员', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response<String>(requestOptions: options, statusCode: 200, data: '{"status":0,"err_code":30020,"error":"设备校验失败"}'));
        },
      ),
    );
    final source = KugouSource(dio: dio);
    await source.loginWithCookie('KuGoo=KugooID=123&t=token-test');
    await expectLater(
      source.stream(const Song(id: 'h:1:2', sourceId: 'kugou', name: 'VIP', vip: true), AudioQuality.lossless),
      throwsA(predicate((error) => '$error'.contains('30020') && '$error'.contains('设备校验失败') && !'$error'.contains('需要酷狗会员'))),
    );
    dio.close();
  });

  test('酷狗 30020 挑战打开官方验证页，重试和重启保留同一设备', () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: jsonEncode({
                'status': 0,
                'err_code': 30020,
                'data': {'SSA-CODE': 'event/+?test', 'SSA-HMID': 'challenge-mid', 'is_publish': 1, 'privilege': 0},
              }),
            ),
          );
        },
      ),
    );
    var source = KugouSource(dio: dio);
    await source.init();
    await expectLater(
      source.stream(song, AudioQuality.standard),
      throwsA(
        isA<SourceVerificationRequired>().having(
          (error) {
            expect(error.url.host, 'h5.kugou.com');
            expect(error.url.path, '/apps/verify-h5/dist/');
            final route = error.url.fragment.split('/');
            expect(Uri.decodeComponent(route[2]), 'event/+?test');
            expect(route[3], '1014');
            expect(Uri.parse(Uri.decodeComponent(route[4])).host, 'www.kugou.com');
            expect(route[5], 'challenge-mid');
            return error.message;
          },
          '提示',
          contains('返回后重新点播放'),
        ),
      ),
    );
    source = KugouSource(dio: dio);
    await source.init();
    await expectLater(source.stream(song, AudioQuality.standard), throwsA(isA<SourceVerificationRequired>()));
    expect(requests[0].queryParameters['mid'], requests[1].queryParameters['mid']);
    dio.close();
  });

  test('酷狗 30020 下架或受限歌曲不误导用户进行人机验证', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: '{"status":0,"err_code":30020,"data":{"is_publish":0,"privilege":5,"SSA-CODE":"challenge"}}',
            ),
          );
        },
      ),
    );
    await expectLater(
      KugouSource(dio: dio).stream(song, AudioQuality.standard),
      throwsA(predicate((error) => error is! SourceVerificationRequired && '$error'.contains('暂不允许播放'))),
    );
    dio.close();
  });

  test('酷狗只使用成功响应中的合法播放地址', () async {
    var success = true;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: jsonEncode({
                'status': success ? 1 : 0,
                'err_code': success ? 0 : 12345,
                'data': {
                  'play_url': 'https://name:secret@audio.example/invalid.mp3',
                  'play_backup_url': ['javascript:alert(1)', 'https://audio.example/valid.mp3'],
                },
              }),
            ),
          );
        },
      ),
    );
    final source = KugouSource(dio: dio);
    expect((await source.stream(song, AudioQuality.standard)).url, 'https://audio.example/valid.mp3');
    success = false;
    await expectLater(source.stream(song, AudioQuality.standard), throwsA(predicate((error) => '$error'.contains('12345'))));
    dio.close();
  });
}
