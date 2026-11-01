import '../models.dart';
import 'music_source.dart';

/// 取播放地址：只使用歌曲所属平台自己的接口（网易云、QQ 音乐、酷狗与洛雪曲库彼此独立，不再互相兜底）。
/// 平台只给出试听片段时照常播放并标记为试听；取不到地址时给出平台的原因。
Future<StreamInfo> resolveStream(MusicSource source, Song song, AudioQuality quality) async {
  final info = await source.stream(song, quality);
  if (info.url == null) throw Exception(song.vip ? '这首歌是会员歌曲，需要登录有会员的${source.name}账号' : '${source.name}暂时没有这首歌的播放地址');
  return info;
}
