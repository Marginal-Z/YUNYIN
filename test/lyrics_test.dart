import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';

void main() {
  test('解析带翻译的 LRC', () {
    final l = parseLrc(
      '[00:01.50]第一行\n[00:03.123]第二行\n[00:05][00:07.00]重复行',
      translation: '[00:01.50]Line one\n[00:03.123]Line two',
    );
    expect(l.synced, isTrue);
    expect(l.lines.map((e) => e.text), ['第一行', '第二行', '重复行', '重复行']);
    expect(l.lines[0].time, const Duration(milliseconds: 1500));
    expect(l.lines[1].time, const Duration(milliseconds: 3123));
    expect(l.lines[0].translation, 'Line one');
    expect(l.indexAt(const Duration(seconds: 4)), 1);
    expect(l.indexAt(Duration.zero), -1);
  });

  test('纯文本歌词不同步', () {
    final l = parseLrc('作词 : 某人\n没有时间轴');
    expect(l.synced, isFalse);
    expect(l.lines, hasLength(2));
  });
}
