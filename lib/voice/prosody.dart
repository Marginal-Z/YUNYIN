import 'tts_types.dart';

/// 按聊天内容推断情绪、语速与停顿。只改变语气，不改变音色。
///
/// 大模型可以在回答开头加情绪标记（例如“[开心]”），有标记时以标记为准；否则按关键词与标点判断。
abstract final class ProsodyPlanner {
  static const _tags = {
    '开心': Emotion.happy,
    '高兴': Emotion.happy,
    '兴奋': Emotion.excited,
    '激动': Emotion.excited,
    '温柔': Emotion.gentle,
    '平静': Emotion.calm,
    '安静': Emotion.calm,
    '难过': Emotion.sad,
    '伤感': Emotion.sad,
    '认真': Emotion.serious,
    '严肃': Emotion.serious,
    'happy': Emotion.happy,
    'excited': Emotion.excited,
    'gentle': Emotion.gentle,
    'calm': Emotion.calm,
    'sad': Emotion.sad,
    'serious': Emotion.serious,
  };

  static final _tagPattern = RegExp(r'^\s*[\[【(（]\s*([^\]】)）]{1,8})\s*[\]】)）]\s*');

  static final _anyTag = RegExp(r'[\[【]\s*([^\]】]{1,8})\s*[\]】]\s*');

  /// 显示用的文字：去掉文中所有的情绪标记（大模型偶尔在段落中间也加）。
  static String displayText(String text) => text.replaceAllMapped(_anyTag, (m) => _tags.containsKey(m.group(1)!.trim().toLowerCase()) ? '' : m.group(0)!);

  /// 去掉开头的情绪标记，返回（文字，标记出的情绪）。
  static (String, Emotion?) stripTag(String text) {
    final m = _tagPattern.firstMatch(text);
    if (m == null) return (text, null);
    final e = _tags[m.group(1)!.trim().toLowerCase()];
    return e == null ? (text, null) : (text.substring(m.end), e);
  }

  static final _cues = <Emotion, RegExp>{
    Emotion.excited: RegExp(r'太棒|超级|燃|嗨起来|冲|太好了|哇|amazing|awesome|let.?s go|!{2,}|！{2,}', caseSensitive: false),
    Emotion.happy: RegExp(r'哈哈|开心|好呀|好哒|不错|喜欢|恭喜|欢迎|嘻嘻|great|nice|glad|happy', caseSensitive: false),
    Emotion.sad: RegExp(r'难过|伤感|遗憾|抱歉|对不起|失恋|想念|孤单|眼泪|sorry|sad|miss you', caseSensitive: false),
    Emotion.calm: RegExp(r'晚安|睡前|放松|安静|慢慢|深夜|助眠|冥想|轻柔|relax|sleep|calm', caseSensitive: false),
    Emotion.gentle: RegExp(r'别担心|没关系|陪你|抱抱|辛苦了|温柔|take care|don.?t worry', caseSensitive: false),
    Emotion.serious: RegExp(r'注意|警告|失败|错误|无法|不能|请先|需要先|error|failed|warning', caseSensitive: false),
  };

  /// 为一句话规划韵律。[base] 为用户设置的基础语速，[carry] 为上一句的情绪（同一段回答情绪连贯）。
  static Prosody plan(String sentence, {double base = 1, Emotion? tagged, Emotion? carry, bool expressive = true}) {
    if (!expressive) return Prosody(rate: base);
    var emotion = tagged ?? Emotion.neutral;
    var hits = 0;
    if (tagged == null) {
      for (final e in _cues.entries) {
        final n = e.value.allMatches(sentence).length;
        if (n > hits) {
          hits = n;
          emotion = e.key;
        }
      }
      if (hits == 0 && carry != null) emotion = carry;
    }
    final intensity = tagged != null ? 0.7 : (hits == 0 ? 0.35 : (0.45 + 0.15 * hits).clamp(0, 0.9).toDouble());
    // 句末停顿：问句、感叹略短，省略号与段落结尾更长；平静与伤感的语气停顿更从容。
    var pause = sentence.endsWith('…') || sentence.endsWith('……') ? 420 : (RegExp(r'[？?！!]$').hasMatch(sentence) ? 200 : 260);
    if (emotion == Emotion.calm || emotion == Emotion.sad) pause += 120;
    if (emotion == Emotion.excited) pause -= 60;
    return Prosody(rate: base, emotion: emotion, intensity: intensity, pauseMs: pause);
  }
}

/// 把流式到来的文字切成适合合成的句子：句号、问号、感叹号、分号与换行处断开；
/// 很长的句子在逗号处提前断开，让第一句尽快开始朗读。
class SentenceSplitter {
  final StringBuffer _buffer = StringBuffer();

  static final _end = RegExp(r'[。！？!?；;\n]|[.](?=\s)|……');
  static final _soft = RegExp(r'[，,、：:]');

  /// 加入一段文字，返回其中已经完整的句子。
  List<String> add(String delta) {
    _buffer.write(delta);
    final out = <String>[];
    var text = _buffer.toString();
    while (true) {
      final m = _end.firstMatch(text);
      var cut = m?.end;
      if (cut == null && text.length > 36) {
        // 太长还没有句号：在最后一个逗号处断开。
        final soft = _soft.allMatches(text).where((s) => s.end >= 12).lastOrNull;
        cut = soft?.end;
      }
      if (cut == null) break;
      final s = clean(text.substring(0, cut));
      if (s.isNotEmpty) out.add(s);
      text = text.substring(cut);
    }
    _buffer
      ..clear()
      ..write(text);
    return out;
  }

  /// 结束：返回剩余的文字。
  List<String> close() {
    final s = clean(_buffer.toString());
    _buffer.clear();
    return s.isEmpty ? const [] : [s];
  }

  /// 去掉不适合朗读的符号（Markdown、表情、链接）。
  static String clean(String s) => s
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceAll(RegExp(r'[*#`>|_~]'), '')
      .replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
