import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';

void main() {
  test('QQ 授权跳转拒绝外部服务器，不转发登录 Cookie', () async {
    for (final target in ['https://evil.example/collect', 'https://qq.com.evil.example/collect', 'file:///tmp/check']) {
      final requests = <String>[];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.host);
            handler.resolve(Response<String>(requestOptions: options, data: "ptuiCB('0','0','$target','0','ok')", statusCode: 200));
          },
        ),
      );
      final source = QQMusicSource(dio: dio);
      await expectLater(source.checkQrLogin(const QrTicket('ticket', '')), throwsFormatException);
      expect(requests, ['ssl.ptlogin2.qq.com']);
      dio.close();
    }
  });

  test('QQ 同域跳转链中夹带外部地址也会被拒绝', () async {
    final requests = <String>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options.uri.host);
          handler.resolve(
            Response<String>(
              requestOptions: options,
              data: requests.length == 1 ? "ptuiCB('0','0','https://ptlogin2.qq.com/check_sig?uin=123&ptsigx=test','0','ok')" : '',
              statusCode: requests.length == 1 ? 200 : 302,
              headers: Headers.fromMap(
                requests.length == 1
                    ? {}
                    : {
                        'location': ['https://evil.example/collect'],
                      },
              ),
            ),
          );
        },
      ),
    );
    final source = QQMusicSource(dio: dio);
    await expectLater(source.checkQrLogin(const QrTicket('ticket', '')), throwsFormatException);
    expect(requests, ['ssl.ptlogin2.qq.com', 'ssl.ptlogin2.graph.qq.com']);
    dio.close();
  });

  test('临时换取凭据失败后同一二维码可以再次尝试', () async {
    var handshakes = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path == '/check_sig') handshakes++;
          handler.resolve(
            Response<String>(
              requestOptions: options,
              data: options.uri.path == '/ptqrlogin' ? "ptuiCB('0','0','https://ptlogin2.qq.com/check_sig?uin=123&ptsigx=test','0','ok')" : '',
              statusCode: 200,
            ),
          );
        },
      ),
    );
    final source = QQMusicSource(dio: dio);
    await expectLater(source.checkQrLogin(const QrTicket('ticket', '')), throwsException);
    await expectLater(source.checkQrLogin(const QrTicket('ticket', '')), throwsException);
    expect(handshakes, 2);
    dio.close();
  });
}
