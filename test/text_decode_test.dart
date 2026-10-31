import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/core/text_decode.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart' show parseLrc;

void main() {
  const lrc = '[00:01.00]刮风这天 我试过握着你手\n[00:05.00]但偏偏 雨渐渐';

  test('GBK、UTF-8（含 BOM）与 UTF-16 编码的歌词都能正确解码', () {
    expect(decodeText(gbk.encode(lrc)), lrc);
    expect(decodeText([0xEF, 0xBB, 0xBF, ...utf8.encode(lrc)]), lrc);
    expect(decodeText(utf8.encode(lrc)), lrc);
    final le = <int>[0xFF, 0xFE];
    for (final u in lrc.codeUnits) {
      le
        ..add(u & 0xFF)
        ..add(u >> 8);
    }
    expect(decodeText(le), lrc);
  });

  test('修复被当作 Latin-1 读取的标签，不误伤西文', () {
    expect(repairMojibake(String.fromCharCodes(gbk.encode('晴天'))), '晴天');
    expect(repairMojibake(String.fromCharCodes(utf8.encode('周杰伦'))), '周杰伦');
    expect(repairMojibake('Café Beyoncé'), 'Café Beyoncé');
    expect(repairMojibake('晴天'), '晴天');
  });

  test('歌词中的 BOM 与 HTML 实体', () {
    final ly = parseLrc('﻿[00:01.00]Don&apos;t stop &amp; go\n[00:02.00]&#20320;&#22909;');
    expect(ly.lines.first.time, const Duration(seconds: 1));
    expect(ly.lines.first.text, "Don't stop & go");
    expect(ly.lines[1].text, '你好');
  });
}
