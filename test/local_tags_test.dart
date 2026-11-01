import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/local_library.dart';

/// 生成一段静音 WAV（没有标签）。
Uint8List _wav(int seconds) {
  const rate = 8000;
  final data = rate * seconds;
  final b = BytesBuilder();
  void u32(int v) => b.add([v & 255, v >> 8 & 255, v >> 16 & 255, v >> 24 & 255]);
  void u16(int v) => b.add([v & 255, v >> 8 & 255]);
  b.add('RIFF'.codeUnits);
  u32(36 + data);
  b.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1);
  u16(1);
  u32(rate);
  u32(rate);
  u16(1);
  u16(8);
  b.add('data'.codeUnits);
  u32(data);
  b.add(Uint8List(data));
  return b.toBytes();
}

void main() {
  test('后台 isolate 中读取标签：没有标签时按文件名拆出歌手与歌名，使用同目录封面，跳过过短的音频', () async {
    final dir = await Directory.systemTemp.createTemp('yunyin_tags');
    addTearDown(() => dir.delete(recursive: true));
    final song = File('${dir.path}/03. 周杰伦 - 晴天.wav')..writeAsBytesSync(_wav(2));
    File('${dir.path}/cover.jpg').writeAsBytesSync([0xFF, 0xD8, 0xFF]);
    final paths = [song.path];
    final tags = await Isolate.run(() => [for (final p in paths) readLocalTags(p, null)]);
    final t = tags.single!;
    expect(t.title, '晴天');
    expect(t.artist, '周杰伦');
    expect(t.folderCover, '${dir.path}/cover.jpg');
    expect(readLocalTags(song.path, 30000), isNull, reason: '短于 30 秒的音频不导入');
  });

  test('没有标签时解析文件名：歌手 - 歌名，以及下载站的“歌名 - 歌手[专辑]”', () {
    final a = parseFileName('03. 周杰伦 - 晴天');
    expect((a.title, a.artist, a.album), ('晴天', '周杰伦', null));
    final b = parseFileName("富士山下 - 陈奕迅[What's Going On…_]");
    expect((b.title, b.artist, b.album), ('富士山下', '陈奕迅', "What's Going On…"));
    final c = parseFileName('海阔天空 - Beyond【华纳廿三周年纪念精选系列】');
    expect((c.title, c.artist, c.album), ('海阔天空', 'Beyond', '华纳廿三周年纪念精选系列'));
    final d = parseFileName('小姐免惊Live');
    expect((d.title, d.artist), ('小姐免惊Live', null));
  });
}

