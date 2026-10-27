import 'package:media_kit/media_kit.dart';

/// 网页版没有 libmpv，见 mpv_property.dart。
Future<bool> setMpvProperty(Player player, String key, String value) async => false;
