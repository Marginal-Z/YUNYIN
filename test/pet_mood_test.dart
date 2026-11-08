import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/assistant/assistant_controller.dart';
import 'package:yunyin/pet/pet_rig.dart';
import 'package:yunyin/pet/pet_host.dart';

void main() {
  test('桌宠表情跟随助手状态：倾听、思考、说话、开心、摇摆、打瞌睡、委屈', () {
    var now = DateTime(2026, 11, 8, 12);
    final r = PetMoodRules(now: () => now);
    (PetMood, String) step({AssistantStatus status = AssistantStatus.idle, String partial = '', bool speaking = false, bool playing = false, String? reply, String? error}) =>
        r.compute(status: status, partial: partial, speaking: speaking, playing: playing, lastReply: reply, error: error);

    expect(step(), (PetMood.idle, ''));
    expect(step(status: AssistantStatus.listening), (PetMood.listening, '我在听…'));
    expect(step(status: AssistantStatus.listening, partial: '播放晴天'), (PetMood.listening, '播放晴天'));
    expect(step(status: AssistantStatus.thinking).$1, PetMood.thinking);
    // 思考结束开始朗读：说话，气泡显示回答。
    expect(step(speaking: true, reply: '好的，为你播放晴天'), (PetMood.speaking, '好的，为你播放晴天'));
    // 朗读结束：开心一下，然后跟着音乐摇摆。
    expect(step(playing: true, reply: '好的，为你播放晴天').$1, PetMood.happy);
    now = now.add(const Duration(seconds: 3));
    expect(step(playing: true, reply: '好的，为你播放晴天').$1, PetMood.dancing);
    // 没放歌、很久没人理：打瞌睡；点一下就醒。
    now = now.add(const Duration(minutes: 2));
    expect(step(reply: '好的，为你播放晴天').$1, PetMood.sleepy);
    r.touch();
    expect(step(reply: '好的，为你播放晴天').$1, PetMood.idle);
    // 出错：委屈几秒，气泡显示原因。
    expect(step(error: '没有麦克风权限'), (PetMood.sad, '没有麦克风权限'));
    now = now.add(const Duration(seconds: 5));
    expect(step(error: '没有麦克风权限').$1, PetMood.idle);
  });

  test('很长的回答在气泡中截短，去掉 Markdown 符号', () {
    final r = PetMoodRules();
    final (_, text) = r.compute(status: AssistantStatus.idle, partial: '', speaking: true, playing: false, lastReply: '**推荐**：${'很好听的歌' * 20}', error: null);
    expect(text.length, lessThanOrEqualTo(42));
    expect(text, isNot(contains('*')));
    expect(text.endsWith('…'), isTrue);
  });

  test('窗口大小：有气泡时加高，宽度不变', () {
    for (final k in PetKind.values) {
      final a = petWindowSize(k, 132, bubble: false);
      final b = petWindowSize(k, 132, bubble: true);
      expect(b.width, a.width);
      expect(b.height, greaterThan(a.height));
      expect(a.height, greaterThan(132));
    }
  });
}
