import '../../local_library.dart';
import '../../models.dart';
import '../music_source.dart';
import '../netease/netease_source.dart' show parseLrc;

/// 本地音乐播放源：播放导入的本地文件。不出现在“切换播放源”列表中。
class LocalSource extends MusicSource {
  LocalSource(this.library);

  static const sourceId = 'local';

  final LocalLibrary library;

  @override
  String get id => sourceId;

  @override
  String get name => '本地音乐';

  @override
  String get description => '导入到云音的本地文件';

  @override
  bool get selectable => false;

  @override
  Set<SourceFeature> get features => const {SourceFeature.lyrics};

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async => StreamInfo(url: song.localPath);

  @override
  Future<Lyrics> lyrics(Song song) async {
    final text = await library.lyricsFor(song);
    if (text == null) return Lyrics.empty;
    return parseLrc(text, translation: await library.translationFor(song) ?? '');
  }
}
