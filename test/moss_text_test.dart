import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/voice/moss/moss_text.dart';

void main() {
  test('数字读法', () {
    expect(mossText('今年是2026年'), '今年是二零二六年。');
    expect(mossText('音量调到35%'), '音量调到百分之三十五。');
    expect(mossText('一共有10首歌'), '一共有十首歌。');
    expect(mossText('播放第105首'), '播放第一百零五首。');
    expect(mossText('播放量12000次'), '播放量一万二千次。');
    expect(mossText('评分3.5分'), '评分三点五分。');
    expect(mossText('现在是8:05'), '现在是八点零五分。');
    expect(mossText('明天9:00出发'), '明天九点整出发。');
    expect(mossText('时长3-4分钟'), '时长三到四分钟。');
    expect(mossText('云音 v1.1.25'), '云音 版本一点一点二十五。');
    expect(mossText('电话13800138000'), '电话一三八零零一三八零零零。');
    expect(mossText('2026-11-15'), '二零二六年十一月十五日。');
  });

  test('去掉标记与表情，补句末标点', () {
    expect(mossText('**好的**，已经为你播放 😀'), '好的，已经为你播放。');
    expect(mossText('真的吗？'), '真的吗？');
    expect(mossText('   '), '');
  });
}
