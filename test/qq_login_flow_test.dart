import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('QQ 扫码确认后完整交换凭据，携带正确登录类型并保存账号', () async {
    final dio = Dio();
    Map<String, dynamic>? authorization;
    Map<String, dynamic>? exchange;
    String? pollingCookie;
    String? exchangeCookie;
    Uri? checkSig;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          Object body = '';
          var status = 200;
          final headers = <String, List<String>>{};
          switch (options.uri.path) {
            case '/ptqrshow':
              body = [0x89, 0x50, 0x4e, 0x47];
              headers['set-cookie'] = ['qrsig=qr-test; Path=/; Secure'];
            case '/ptqrlogin':
              pollingCookie = options.headers['Cookie'] as String?;
              body = "ptuiCB('0','0','https://ssl.ptlogin2.qq.com/check_sig?uin=12345&ptsigx=a%2Bb','0','登录成功')";
            case '/check_sig':
              checkSig = options.uri;
              headers['set-cookie'] = ['p_skey=oauth-test; Domain=graph.qq.com; Path=/; Secure, skey=session-test; Domain=.qq.com; Expires=Wed, 09 Jun 2027 10:18:14 GMT; Path=/'];
            case '/oauth2.0/authorize':
              authorization = Map<String, dynamic>.from(options.data as Map);
              headers['location'] = ['https://y.qq.com/portal/wx_redirect.html?code=code%2Btest&state=state'];
              status = 302;
            case '/cgi-bin/musicu.fcg':
              final request = jsonDecode(options.data as String) as Map<String, dynamic>;
              if ((request['req'] as Map)['method'] == 'QQLogin') {
                exchange = request;
                exchangeCookie = options.headers['Cookie'] as String?;
                body = jsonEncode({
                  'req': {
                    'code': 0,
                    'data': {'musicid': 12345, 'musickey': 'music-test'},
                  },
                });
              } else {
                body = '{"req":{"code":0,"data":{}}}';
              }
            default:
              body = '{"code":0,"data":{"creator":{"nick":"测试用户"}}}';
          }
          handler.resolve(Response<dynamic>(requestOptions: options, statusCode: status, data: body, headers: Headers.fromMap(headers)));
        },
      ),
    );
    final source = QQMusicSource(dio: dio);
    final ticket = await source.createQrLogin();
    expect(await source.checkQrLogin(ticket), QrState.confirmed);
    expect(pollingCookie, contains('qrsig=qr-test'));
    expect(checkSig!.host, 'ssl.ptlogin2.graph.qq.com');
    expect(checkSig!.queryParameters['ptsigx'], 'a+b');
    expect(checkSig!.queryParameters['ptredirect'], '100');
    expect(checkSig!.queryParameters['pt_3rd_aid'], '100497308');
    expect(authorization!['scope'], 'get_user_info,get_app_friends');
    expect(authorization!['openapi'], '1010_1030');
    expect((exchange!['comm'] as Map)['tmeLoginType'], 2);
    expect(((exchange!['req'] as Map)['param'] as Map)['code'], 'code+test');
    // 与浏览器一样按域名发送 Cookie：qq.com 的 skey 发给 QQ 音乐，graph.qq.com 的 p_skey 与 ptlogin 的 qrsig 不发。
    expect(exchangeCookie, contains('skey=session-test'));
    expect(exchangeCookie, isNot(contains('p_skey')));
    expect(exchangeCookie, isNot(contains('qrsig')));
    expect(source.user?.id, '12345');
    final restored = QQMusicSource();
    await restored.init();
    expect(restored.user?.id, '12345');
    dio.close();
  });

  test('QQ 退出账号后未完成的扫码请求不会重新登录', () async {
    final waiting = Completer<Response<dynamic>>();
    final dio = Dio();
    var exchangeCalled = false;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.uri.path == '/ptqrlogin') {
            final response = await waiting.future;
            handler.resolve(Response<dynamic>(requestOptions: options, data: response.data, headers: response.headers, statusCode: 200));
          } else {
            exchangeCalled = true;
            handler.resolve(Response<String>(requestOptions: options, data: '', statusCode: 200));
          }
        },
      ),
    );
    final source = QQMusicSource(dio: dio);
    final checking = source.checkQrLogin(const QrTicket('old', ''));
    final result = expectLater(checking, throwsA(isA<StateError>()));
    await Future<void>.delayed(Duration.zero);
    await source.logout();
    waiting.complete(Response<String>(requestOptions: RequestOptions(), data: "ptuiCB('0','0','https://ssl.ptlogin2.qq.com/check_sig','0','ok')"));
    await result;
    expect(exchangeCalled, isFalse);
    expect(source.user, isNull);
    dio.close();
  });

  test('QQ 凭据交换返回 20252 时不接受错误响应中的 Cookie，不覆盖已有账号', () async {
    final saved = jsonEncode({'uin': '42', 'key': 'existing-key', 'nickname': '已有账号'});
    SharedPreferences.setMockInitialValues({'qq.account': saved});
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          var body = '';
          final headers = <String, List<String>>{};
          switch (options.uri.path) {
            case '/ptqrlogin':
              body = "ptuiCB('0','0','https://ssl.ptlogin2.qq.com/check_sig?uin=12345&ptsigx=signature','0','登录成功')";
            case '/check_sig':
              headers['set-cookie'] = ['p_skey=oauth-test; Path=/'];
            case '/oauth2.0/authorize':
              headers['location'] = ['https://y.qq.com/portal/wx_redirect.html?code=expired'];
            default:
              body = '{"req":{"code":20252,"data":{"musicid":12345,"musickey":"invalid"}}}';
              headers['set-cookie'] = ['qqmusic_key=invalid; Path=/'];
          }
          handler.resolve(Response<String>(requestOptions: options, statusCode: 200, data: body, headers: Headers.fromMap(headers)));
        },
      ),
    );
    final source = QQMusicSource(dio: dio);
    await source.init();
    await expectLater(source.checkQrLogin(const QrTicket('test', '')), throwsA(predicate((error) => '$error'.contains('20252'))));
    expect(source.user?.id, '42');
    expect((await SharedPreferences.getInstance()).getString('qq.account'), saved);
    dio.close();
  });
}
