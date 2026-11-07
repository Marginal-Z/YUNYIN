import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/sources/net_retry.dart';

/// 前 [failures] 次请求连接失败，之后正常返回。
class _Flaky implements HttpClientAdapter {
  _Flaky(this.failures);

  int failures;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    if (failures-- > 0) throw const SocketException('Failed host lookup');
    return ResponseBody.fromString('ok', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('连接失败时重试一次', () async {
    final adapter = _Flaky(1);
    final dio = withRetry(Dio(BaseOptions(responseType: ResponseType.plain))..httpClientAdapter = adapter);
    final res = await dio.get<String>('https://example.com/a');
    expect(res.data, 'ok');
    expect(adapter.calls, 2);
  });

  test('只重试一次：连续失败时给出错误', () async {
    final adapter = _Flaky(5);
    final dio = withRetry(Dio(BaseOptions(responseType: ResponseType.plain))..httpClientAdapter = adapter);
    await expectLater(dio.get<String>('https://example.com/a'), throwsA(isA<DioException>()));
    expect(adapter.calls, 2);
  });
}
