import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/assistant/intents.dart';

void main() {
  test('中文数字', () {
    expect(parseChineseNumber('二十五'), 25);
    expect(parseChineseNumber('十'), 10);
    expect(parseChineseNumber('一百'), 100);
    expect(parseChineseNumber('30'), 30);
    expect(parseChineseNumber('两'), 2);
    expect(parseChineseNumber('一个半'), 1.5);
    expect(parseChineseNumber('很多'), isNull);
  });

  test('播放控制', () {
    expect((parseIntent('暂停') as PlaybackIntent).action, PlaybackAction.pause);
    expect((parseIntent('你好云音，下一首。') as PlaybackIntent).action, PlaybackAction.next);
    expect((parseIntent('帮我切歌') as PlaybackIntent).action, PlaybackAction.next);
    expect((parseIntent('上一首') as PlaybackIntent).action, PlaybackAction.previous);
    expect((parseIntent('继续播放') as PlaybackIntent).action, PlaybackAction.play);
    expect((parseIntent('单曲循环') as ModeIntent).mode, ModeChoice.repeatOne);
  });

  test('点歌与歌手', () {
    final a = parseIntent('播放晴天') as PlayQueryIntent;
    expect(a.query, '晴天');
    expect(a.artist, isFalse);
    final b = parseIntent('我想听周杰伦的歌') as PlayQueryIntent;
    expect(b.query, '周杰伦');
    expect(b.artist, isTrue);
    expect((parseIntent('来一首七里香') as PlayQueryIntent).query, '七里香');
    // 描述性的需求交给大模型。
    expect(parseIntent('播放适合跑步的歌'), isNull);
    expect(parseIntent('来点好听的'), isNull);
    expect(parseIntent('这首歌讲了什么故事'), isNull);
  });

  test('音量、定时与音效', () {
    expect((parseIntent('音量调到五十') as VolumeIntent).level, 0.5);
    expect((parseIntent('音量百分之三十') as VolumeIntent).level, closeTo(0.3, 1e-9));
    expect((parseIntent('大声一点') as VolumeIntent).delta, greaterThan(0));
    expect((parseIntent('声音小一点') as VolumeIntent).delta, lessThan(0));
    expect((parseIntent('三十分钟后停止播放') as SleepIntent).minutes, 30);
    expect((parseIntent('一个小时后关闭') as SleepIntent).minutes, 60);
    expect((parseIntent('定时关闭二十分钟') as SleepIntent).minutes, 20);
    expect((parseIntent('取消定时') as SleepIntent).minutes, 0);
    expect((parseIntent('切换到摇滚音效') as EqIntent).preset, '摇滚');
    expect((parseIntent('关闭均衡器') as EqIntent).preset, isNull);
    expect((parseIntent('打开重低音') as EffectIntent).bass, isTrue);
    expect(parseIntent('收藏这首歌'), isA<LikeIntent>());
    expect(parseIntent('这是什么歌'), isA<NowPlayingIntent>());
  });
}
