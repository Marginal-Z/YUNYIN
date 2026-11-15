import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/voice/moss/sentencepiece.dart';

/// MOSS-TTS-Nano 的分词结果与官方 SentencePiece（Python）逐个 ID 一致。
/// tokenizer_cases.json 由官方库对 1500 多段随机中英文、空白、全角字符、表情与控制符号生成。
void main() {
  final tokenizer = SentencePieceBpe.fromBytes(File('test/fixtures/moss/tokenizer.model').readAsBytesSync());
  final cases = (jsonDecode(File('test/fixtures/moss/tokenizer_cases.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

  test('与官方 SentencePiece 一致', () {
    final wrong = <String>[];
    for (final c in cases) {
      final want = (c['ids'] as List).cast<int>();
      final got = tokenizer.encode(c['text'] as String);
      if (got.join(',') != want.join(',')) wrong.add('${jsonEncode(c['text'])}\n  want $want\n  got  $got');
    }
    expect(wrong.take(5).join('\n'), isEmpty, reason: '${wrong.length} / ${cases.length} 不一致');
  });

  test('官方示例的中文句子', () {
    expect(tokenizer.encode('欢迎关注模思智能、上海创智学院与复旦大学自然语言处理实验室。'), [
      8651, 2691, 11099, 10670, 7669, 10508, 4627, 11074, 11315, 6439, 10617, 10859, 11643, 2957, 1531, 4139, 2305, 4146, 11255, 10382, //
    ]);
  });
}
