import 'package:media_kit/media_kit.dart';

/// 设置 libmpv 属性，返回是否已设置。网页版的播放器不是 mpv，使用 mpv_property_web.dart 中的空实现
/// （media_kit 网页版的 NativePlayer 没有 setProperty，直接调用会让网页版编译失败）。
Future<bool> setMpvProperty(Player player, String key, String value) async {
  final native = player.platform;
  if (native is! NativePlayer) return false;
  await native.setProperty(key, value);
  return true;
}
