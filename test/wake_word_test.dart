import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/assistant/voice_engine.dart';
import 'package:yunyin/assistant/wake_word.dart';

void main() {
  final table = WakeWords.parseTable(File('assets/pinyin/hanzi.txt').readAsStringSync());
  final tokens = WakeWords.readTokens('test/fixtures_kws_tokens.txt');

  test('声调标注：a、e 优先，ou 标在 o 上，j/q/x/y 后的 ü 写作 u', () {
    expect(WakeWords.markTone('ao3'), 'ǎo');
    expect(WakeWords.markTone('iu2'), 'iú');
    expect(WakeWords.markTone('ui4'), 'uì');
    expect(WakeWords.markTone('ou1'), 'ōu');
    expect(WakeWords.markTone('ve4', initial: 'l'), 'üè');
    expect(WakeWords.markTone('ve2', initial: 'x'), 'ué');
    expect(WakeWords.markTone('v3', initial: 'n'), 'ǚ');
    expect(WakeWords.markTone('e5'), 'e');
  });

  test('“你好云音”转换结果与内置唤醒词完全一致；自定义唤醒词经过模型标记表校验', () {
    final (line, error) = WakeWords.convert('你好云音', table, tokens);
    expect(error, isNull);
    expect(line, kWakeWords.first);
    expect(WakeWords.convert('小云小云', table, tokens).$1, 'x iǎo y ún x iǎo y ún @小云小云');
    expect(WakeWords.convert('嗨', table, tokens).$2, contains('3–6'));
    expect(WakeWords.convert('hello云音', table, tokens).$2, isNotNull);
    final (lx, _) = WakeWords.convert('绿色音乐', table, tokens);
    expect(lx, startsWith('l ǜ s'));
  });

  test('去掉一句话开头的唤醒词，正常的话不受影响', () {
    expect(WakeWords.strip('你好语音'), '');
    expect(WakeWords.strip('你好云音，下一首'), '下一首');
    expect(WakeWords.strip('嗨云英播放晴天'), '播放晴天');
    expect(WakeWords.strip('小美同学放首歌', custom: '小美同学'), '放首歌');
    expect(WakeWords.strip('语音助手能做什么'), '语音助手能做什么');
    expect(WakeWords.strip('运营商是哪家'), '运营商是哪家');
  });
}
