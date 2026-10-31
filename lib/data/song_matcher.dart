import 'models.dart';
import 'sources/music_source.dart';

/// 在某个播放源中找出“同一首歌”：按歌名主干、歌手与时长打分，排除翻唱、伴奏等版本。
/// 用于本地音乐与网盘歌曲联网补全封面歌词，以及酷狗无法播放时换源到网易云播放。
abstract final class SongMatcher {
  static String _norm(String x) => x.toLowerCase().replaceAll(RegExp(r'''[\s()（）\[\]【】《》\-_·.,，。!！?？'"“”‘’&/、]'''), '');

  static final _trackNo = RegExp(r'^\s*\d{1,3}\s*[.\-_、\s]\s*');
  static final _brackets = RegExp(r'[（(\[【《][^（()\[\]【】《》]*[）)\]】》]');
  static final _feat = RegExp(r'\s+(feat|ft)\.?\s.*$', caseSensitive: false);

  /// 歌名主干：去掉括号里的版本说明（Live、伴奏、Remastered…）与 feat. 部分。
  static String _core(String t) {
    final c = _norm(t.replaceAll(_brackets, ' ').replaceFirst(_feat, ''));
    return c.isEmpty ? _norm(t) : c;
  }

  /// 拆分多位歌手（“A/B”“A、B”“A & B”“A feat. B”）；括号里的别名（“冯沁苑(买辣椒也用券)”）也算一个名字。
  static List<String> _artistsOf(String a) => [
    for (final x
        in a
            .replaceAll(RegExp(r'[（(]'), '/')
            .replaceAll(RegExp(r'[）)]'), '')
            .split(RegExp(r'\s*(?:/|&|,|，|、|;|；|\sfeat\.?\s|\sft\.?\s|\sx\s)\s*', caseSensitive: false)))
      if (_norm(x).isNotEmpty && _norm(x) != _norm('未知歌手')) _norm(x),
  ];

  /// 本地歌曲可能的（歌名，歌手，是否为推测）解读。没有标签时歌名来自文件名，可能带音轨编号，
  /// 也可能是“歌名 - 歌手”而不是“歌手 - 歌名”的顺序。
  static List<(String, String, bool)> _readings(Song s) {
    final name = s.name.replaceFirst(_trackNo, '').trim();
    final artist = s.artistText == '未知歌手' ? '' : s.artistText;
    final out = <(String, String, bool)>[(name, artist, false)];
    final parts = name.split(RegExp(r'\s+[-–—]\s+'));
    if (parts.length == 2 && artist.isEmpty) {
      out
        ..add((parts[1], parts[0], true))
        ..add((parts[0], parts[1], true));
    }
    // 文件名按“歌手 - 歌名”解析，但实际可能是“歌名 - 歌手”：交换后再试（必须歌手吻合才接受）。
    if (artist.isNotEmpty && s.album == null) out.add((artist, name, true));
    return out;
  }

  /// 按歌名、歌手与时长打分，挑选最可能是同一首歌的结果。
  static Future<Song?> match(MusicSource src, Song s) async {
    for (final (name, artist, guessed) in _readings(s)) {
      final title = _core(name);
      if (title.isEmpty) continue;
      final artists = _artistsOf(artist);
      // 搜索词：去掉括号说明的歌名 + 第一位歌手。
      final plain = name.replaceAll(_brackets, ' ').replaceFirst(_feat, '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final q = plain.isEmpty ? name : plain;
      final first = artist.split(RegExp(r'\s*(?:/|&|,|，|、|;|；)\s*')).first.trim();
      final queries = ['$q ${artists.isEmpty ? '' : first}'.trim(), if (artists.isNotEmpty) q];
      for (var k = 0; k < queries.length; k++) {
        final r = await src.search(queries[k], type: SearchType.song, limit: 10);
        // 只用歌名补搜时结果里翻唱很多，必须歌手吻合。
        final best = _pick(s, r.songs, title, artists, guessed: guessed, needArtist: k > 0);
        if (best != null) return best;
      }
    }
    return null;
  }

  /// 翻唱、伴奏、混音等版本标记：本地歌名没有这些字样时，不接受带这些字样的结果。
  static final _variant = RegExp(r'翻自|翻唱|原唱|cover|伴奏|instrumental|纯音乐|karaoke|remix|dj版|beat', caseSensitive: false);

  static Song? _pick(Song s, List<Song> candidates, String title, List<String> artists, {required bool guessed, bool needArtist = false}) {
    Song? best;
    var bestScore = 0;
    final localVariant = _variant.hasMatch(s.name);
    for (final c in candidates) {
      if (!localVariant && _variant.hasMatch(c.name)) continue;
      final t = _core(c.name);
      // 结果带括号说明（女声版、深情版、Live…）而本地歌名没有时，只算部分吻合，必须歌手一致。
      final exact = t == title && (!_brackets.hasMatch(c.name) || _brackets.hasMatch(s.name));
      final partial = !exact && t.isNotEmpty && (t.contains(title) || title.contains(t));
      if (!exact && !partial) continue;
      var score = exact ? 4 : 2;
      final names = [for (final a in c.artists) ..._artistsOf(a.name)];
      final artistHit = artists.isNotEmpty && names.any((a) => artists.any((x) => a == x || a.contains(x) || x.contains(a)));
      if (artistHit) score += 3;
      final hasDuration = s.duration > Duration.zero && c.duration > Duration.zero;
      final diff = hasDuration ? (s.duration - c.duration).abs() : Duration.zero;
      final durationOk = hasDuration && diff <= const Duration(seconds: 3);
      if (durationOk) score += 2;
      if (hasDuration && diff > const Duration(seconds: 20)) score -= 3;
      // 推测出的解读证据较弱：歌名与某位歌手都必须完全相同。
      if (guessed && !(exact && names.any(artists.contains))) continue;
      if (needArtist && !artistHit) continue;
      if (artists.isNotEmpty) {
        // 知道歌手：歌手吻合；或歌名完全相同且时长几乎一致（翻唱、伴奏不会被当成原曲）。
        if (!artistHit && !(exact && durationOk)) continue;
      } else {
        // 不知道歌手：歌名完全相同，且时长吻合（或无法比较时长）。
        if (!exact || (hasDuration && !durationOk)) continue;
      }
      if (score > bestScore) {
        best = c;
        bestScore = score;
      }
    }
    return best;
  }
}
