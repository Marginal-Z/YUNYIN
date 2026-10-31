import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';

/// 文本文件（歌词）解码：按 BOM 识别 UTF-8 / UTF-16，否则先按 UTF-8 严格解码，失败时按 GBK（GB2312 超集）解码。
/// 国内很多 .lrc 文件与旧版播放器写入的标签是 GBK 编码，直接当作 UTF-8 读取会出现乱码。
String decodeText(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) return _utf16(bytes.sublist(2), little: true);
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) return _utf16(bytes.sublist(2), little: false);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    try {
      return gbk.decode(bytes);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}

String _utf16(List<int> b, {required bool little}) {
  final units = <int>[
    for (var i = 0; i + 1 < b.length; i += 2) little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1],
  ];
  return String.fromCharCodes(units);
}

/// 修复被当作 Latin-1 读取的 GBK / UTF-8 文本（例如“ÄãºÃ”应为“你好”）：
/// 文本里只有 0x00–0xFF 的字符且含有高位字符时，按原始字节重新解码。
String repairMojibake(String s) {
  if (s.isEmpty) return s;
  var high = 0;
  for (final c in s.codeUnits) {
    if (c > 0xFF) return s;
    if (c >= 0x80) high++;
  }
  if (high == 0) return s;
  final fixed = decodeText(s.codeUnits);
  // 重新解码后出现中日韩文字才采用，避免误伤真正的西文字符（如 é、ü）。
  return RegExp(r'[぀-ヿ㐀-鿿가-힯]').hasMatch(fixed) && !fixed.contains('�') ? fixed : s;
}

/// 歌词文本清理：去掉 BOM，还原常见的 HTML 实体（部分平台的歌词里带有 &apos; &amp; 等）。
String cleanLyricText(String s) {
  var t = s.replaceAll('﻿', '');
  if (!t.contains('&')) return t;
  t = t
      .replaceAll('&apos;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
        final code = int.tryParse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16);
        return code == null ? m[0]! : String.fromCharCode(code);
      })
      .replaceAll('&amp;', '&');
  return t;
}
