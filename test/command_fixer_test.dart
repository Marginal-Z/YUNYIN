import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/assistant/command_fixer.dart';
import 'package:yunyin/assistant/wake_word.dart';

void main() {
  final fixer = CommandFixer(WakeWords.parseTable(File('assets/pinyin/hanzi.txt').readAsStringSync()));

  test('读音相近的短指令纠正为常用指令', () {
    expect(fixer.fix('烧一首'), '上一首');
    expect(fixer.fix('夏一首'), '下一首');
    expect(fixer.fix('单取循环'), '单曲循环');
    expect(fixer.fix('随即播放'), '随机播放');
    expect(fixer.fix('打开个词'), '打开歌词');
    // 真机上的识别结果：“切换到浅色模式”被认成“切换到检设模式”。
    expect(fixer.fix('切换到检设模式'), '切换到浅色模式');
  });

  test('已经能识别的指令、读音差别大的话、长句都不改', () {
    expect(fixer.fix('上一首'), isNull);
    expect(fixer.fix('今天天气怎么样'), isNull);
    expect(fixer.fix('来点适合跑步的歌'), isNull);
    expect(fixer.fix('你好'), isNull);
    expect(fixer.fix('伤心'), isNull);
  });
}
