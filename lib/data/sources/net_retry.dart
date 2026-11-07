import 'dart:io';

import 'package:dio/dio.dart';

/// 连接本身失败（域名暂时解析不了、连接被拒绝或被重置）时稍等片刻重试一次。
///
/// 手机切换网络、Wi-Fi 漫游或网络短暂抖动时这类错误很常见，重试一次通常就能成功；
/// 此前一次失败就让整页显示“网络开小差了”（例如 QQ 音乐首页的榜单与歌单同时请求，其中一个失败整页都失败）。
/// 超时不重试：已经等了很久，再等一轮只会更慢。
class RetryOnConnectionError extends Interceptor {
  RetryOnConnectionError(this._dio);

  final Dio _dio;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    final transient = err.type == DioExceptionType.connectionError || err.error is SocketException;
    if (!transient || o.extra['retried'] == true) return handler.next(err);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    o.extra['retried'] = true;
    try {
      handler.resolve(await _dio.fetch<dynamic>(o));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// 给平台接口使用的 Dio 加上连接失败重试。
Dio withRetry(Dio dio) => dio..interceptors.add(RetryOnConnectionError(dio));
