import 'dart:io';

import 'package:flutter/services.dart';

/// 自定义唤醒词：把汉字转换成唤醒模型使用的拼音标记（声母 + 带声调的韵母，例如“你好云音” → “n ǐ h ǎo y ún y īn”）。
///
/// 汉字读音来自 assets/pinyin/hanzi.txt（每行：汉字 + 声母（无声母为 -）+ 空格 + 韵母与声调数字）。
/// 转换结果中的每个标记都必须在唤醒模型的 tokens.txt 中，否则说明这个词无法检测。
abstract final class WakeWords {
  static Map<String, (String, String)>? _table;

  static Future<Map<String, (String, String)>> _load() async {
    if (_table != null) return _table!;
    final text = await rootBundle.loadString('assets/pinyin/hanzi.txt');
    return _table = parseTable(text);
  }

  static Map<String, (String, String)> parseTable(String text) {
    final out = <String, (String, String)>{};
    for (final line in text.split('\n')) {
      if (line.length < 3) continue;
      final ch = String.fromCharCode(line.runes.first);
      final rest = line.substring(ch.length);
      final sp = rest.indexOf(' ');
      if (sp < 0) continue;
      final initial = rest.substring(0, sp);
      out.putIfAbsent(ch, () => (initial == '-' ? '' : initial, rest.substring(sp + 1).trim()));
    }
    return out;
  }

  static const _marks = {'a': 'āáǎà', 'e': 'ēéěè', 'i': 'īíǐì', 'o': 'ōóǒò', 'u': 'ūúǔù', 'ü': 'ǖǘǚǜ'};

  /// 给韵母标声调（a、e 优先，ou 标在 o 上，其余标在最后一个元音上）。[initial] 用于 j/q/x/y 后的 ü 写作 u。
  static String markTone(String finalWithTone, {String initial = ''}) {
    final m = RegExp(r'^([a-zü]+?)([1-5])?$').firstMatch(finalWithTone.trim());
    if (m == null) return finalWithTone;
    var fin = m.group(1)!.replaceAll('v', 'ü');
    if (const {'j', 'q', 'x', 'y'}.contains(initial)) fin = fin.replaceAll('ü', 'u');
    final tone = int.tryParse(m.group(2) ?? '5') ?? 5;
    if (tone < 1 || tone > 4) return fin;
    int idx;
    if (fin.contains('a')) {
      idx = fin.indexOf('a');
    } else if (fin.contains('e')) {
      idx = fin.indexOf('e');
    } else if (fin.contains('ou')) {
      idx = fin.indexOf('o');
    } else {
      idx = -1;
      for (var i = fin.length - 1; i >= 0; i--) {
        if (_marks.containsKey(fin[i])) {
          idx = i;
          break;
        }
      }
      if (idx < 0) return fin;
    }
    return fin.substring(0, idx) + _marks[fin[idx]]![tone - 1] + fin.substring(idx + 1);
  }

  /// 转换为唤醒模型的一行关键词（“标记 … @原词”）。[tokens] 为唤醒模型支持的标记集合（用于校验）。
  /// 返回 null 并给出原因：含有非汉字、太短 / 太长，或者有读音不在模型中的字。
  static (String?, String?) convert(String word, Map<String, (String, String)> table, Set<String> tokens) {
    final w = word.trim().replaceAll(RegExp(r'\s'), '');
    if (w.runes.length < 3 || w.runes.length > 6) return (null, '唤醒词请用 3–6 个汉字（太短容易误触发）');
    final parts = <String>[];
    for (final r in w.runes) {
      final ch = String.fromCharCode(r);
      final py = table[ch];
      if (py == null) return (null, '“$ch”不是常用汉字，请只用汉字');
      final (initial, fin) = py;
      if (initial.isNotEmpty) parts.add(initial);
      parts.add(markTone(fin, initial: initial));
    }
    final missing = parts.where((t) => !tokens.contains(t)).toSet();
    if (missing.isNotEmpty) return (null, '唤醒模型无法识别这些读音：${missing.join('、')}，请换一个词');
    return ('${parts.join(' ')} @$w', null);
  }

  /// 读取唤醒模型的标记表。
  static Set<String> readTokens(String tokensFile) => {
    for (final line in File(tokensFile).readAsLinesSync())
      if (line.trim().isNotEmpty) line.split(' ').first,
  };

  /// 把唤醒词转换为模型标记（使用内置读音表）。
  static Future<(String?, String?)> toTokens(String word, String tokensFile) async {
    final table = await _load();
    return convert(word, table, readTokens(tokensFile));
  }
}
