import 'dart:convert';
import 'dart:isolate';

/// 解析接口返回的 JSON：较大的响应（大歌单、长评论列表，可达 1 MB）在后台 isolate 中解析，
/// 结果直接转交回来不复制。此前在界面线程中同步解析，打开大歌单时页面切换动画会卡顿掉帧，配置较低的手机尤其明显。
Future<dynamic> decodeJson(String? text) {
  final s = text == null || text.isEmpty ? '{}' : text;
  if (s.length < 64 * 1024) return Future.value(jsonDecode(s));
  return Isolate.run(() => jsonDecode(s));
}
