import 'intents.dart';

/// 指令的读音纠错：语音识别偶尔把短指令认成读音相近的字（“上一首”认成“烧一首”）。
///
/// 本地指令匹配不上、而且这句话很短时，把它转成不带声调的拼音，与常用指令逐音节比较：
/// 音节数相同、字母差别很小，并且明显比第二接近的指令更像时，才换成那条指令；否则不改（交给大模型）。
class CommandFixer {
  CommandFixer(this._table);

  final Map<String, (String, String)> _table;

  /// 常用指令（都能被 [parseIntent] 识别）。
  static const commands = [
    '上一首', '下一首', '暂停', '继续播放', '单曲循环', '随机播放', '顺序播放', '收藏这首歌', '取消收藏',
    '打开歌词', '大声一点', '小声一点', '静音', '取消定时', '这是什么歌', '打开桌面歌词', '关闭桌面歌词',
    '下载这首歌', '播放每日推荐', '播放我喜欢的音乐', '打开设置', '打开深色模式', '打开浅色模式',
    '切换到深色模式', '切换到浅色模式', '关闭深色模式', '打开歌词翻译', '关闭歌词翻译', '打开状态栏歌词', '关闭状态栏歌词',
  ];

  late final _targets = [for (final c in commands) (c, _syllables(c))];

  /// 一个字的读音（不带声调），不认识的字返回 null。
  String? _pinyin(String ch) {
    final py = _table[ch];
    if (py == null) return null;
    return '${py.$1}${py.$2.replaceAll(RegExp(r'[0-9]'), '')}';
  }

  List<String>? _syllables(String text) {
    final out = <String>[];
    for (final r in text.runes) {
      final p = _pinyin(String.fromCharCode(r));
      if (p == null) return null;
      out.add(p);
    }
    return out;
  }

  static int _distance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// 纠正一句话：返回最像的常用指令，不像任何指令时返回 null。
  String? fix(String raw) {
    final text = raw.replaceAll(RegExp(r'[，。！？、,.!?\s]'), '');
    if (text.isEmpty || text.runes.length > 8 || parseIntent(text) != null) return null;
    final heard = _syllables(text);
    if (heard == null) return null;
    (String, int)? best;
    var second = 1 << 20;
    for (final (command, target) in _targets) {
      if (target == null || target.length != heard.length) continue;
      var d = 0;
      var changed = 0;
      for (var i = 0; i < heard.length; i++) {
        final x = _distance(heard[i], target[i]);
        d += x;
        if (x > 0) changed++;
      }
      // 两个字的指令不允许差别；三到五个字最多一个音节、两个字母不同；六个字以上最多两个音节、三个字母不同。
      final long = heard.length >= 6;
      if (changed > (long ? 2 : (heard.length >= 3 ? 1 : 0)) || d > (long ? 3 : 2)) continue;
      if (best == null || d < best.$2) {
        if (best != null) second = best.$2;
        best = (command, d);
      } else if (d < second) {
        second = d;
      }
    }
    if (best == null || second <= best.$2) return null;
    return best.$1;
  }
}
