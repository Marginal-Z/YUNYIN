import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/voice/prosody.dart';
import 'package:yunyin/voice/speech_output.dart';
import 'package:yunyin/voice/tts_types.dart';
import 'package:yunyin/voice/voice_library.dart';
import 'package:yunyin/voice/voice_settings.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

/// 假引擎：记录收到的请求，可以设置为失败。
class _FakeEngine extends TtsEngine {
  _FakeEngine(this.id, {this.fail = false, this.offline = false, this.delay = Duration.zero});

  @override
  final String id;
  bool fail;
  @override
  final bool offline;
  final Duration delay;
  final requests = <(String, TtsRequest)>[];

  @override
  String get name => id;
  @override
  bool get configured => true;
  @override
  Set<VoiceLanguage> get languages => VoiceLanguage.values.toSet();
  @override
  Future<bool> ready(EngineVoice voice, VoiceLanguage lang) async => true;

  @override
  Stream<TtsAudio> synthesize(EngineVoice voice, TtsRequest request, {CancelToken? cancel}) async* {
    requests.add((voice.voices[request.language] ?? '', request));
    await Future<void>.delayed(delay);
    if (fail) throw TtsException('故障', engine: id);
    yield TtsAudio(Uint8List.fromList(utf8.encode('$id:${request.text}')), format: 'mp3');
  }
}

/// 假播放器：记录播放的文件内容，每段播放 [ms] 毫秒。
class _Sink extends SpeechSink {
  _Sink({this.ms = 5});
  final int ms;
  final played = <String>[];
  Completer<void>? _c;

  @override
  Future<void> play(String path) async {
    played.add(File(path).readAsStringSync());
    final c = _c = Completer<void>();
    Timer(Duration(milliseconds: ms), () => c.isCompleted ? null : c.complete());
    await c.future;
  }

  @override
  Future<void> stop() async {
    if (!(_c?.isCompleted ?? true)) _c!.complete();
  }
}

void main() {
  late Directory tmp;
  late VoiceSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('voice');
    PathProviderPlatform.instance = _Paths(tmp.path);
    settings = VoiceSettings();
    await settings.init();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('分句：句号、问号与换行断句，很长的句子在逗号处提前断开，去掉 Markdown 与表情', () {
    final s = SentenceSplitter();
    expect(s.add('你好呀'), isEmpty);
    expect(s.add('！今天想听什么？我'), ['你好呀！', '今天想听什么？']);
    expect(s.add('来推荐**三首**歌🎵\n'), ['我来推荐三首歌']);
    final long = s.add('这是一句非常非常长的话，它一直没有句号，但是已经超过了三十六个字，所以应该在逗号这里断开');
    expect(long, isNotEmpty);
    expect(long.first.endsWith('，'), isTrue);
  });

  test('情绪：开头的标记优先，其次按关键词；只改变语速与停顿，不改变音色', () {
    final (text, tag) = ProsodyPlanner.stripTag('[开心] 太好了，找到啦！');
    expect(text, '太好了，找到啦！');
    expect(tag, Emotion.happy);
    expect(ProsodyPlanner.plan('晚安，放松一下，慢慢睡吧。').emotion, Emotion.calm);
    expect(ProsodyPlanner.plan('抱歉，这首歌暂时无法播放。').emotion, isNot(Emotion.happy));
    final calm = ProsodyPlanner.plan('晚安……');
    expect(calm.pauseMs, greaterThan(ProsodyPlanner.plan('好的！').pauseMs));
    expect(ProsodyPlanner.plan('好的', expressive: false).emotion, Emotion.neutral);
  });

  test('引擎失败时自动降级到下一个，并在冷却期内跳过它；女声与男声是不同的系统声音，旧音色按性别对应', () async {
    final a = _FakeEngine('cosyvoice', fail: true);
    final b = _FakeEngine('system', offline: true);
    final engines = VoiceEngines(settings, engines: [a, b]);
    final sink = _Sink();
    final out = SpeechOutput(settings, engines: engines, sink: sink);
    await out.say('第一句。第二句。');
    expect(sink.played, ['system:第一句。', 'system:第二句。']);
    expect(a.requests, hasLength(1), reason: '失败后进入冷却，第二句直接用下一个引擎');
    expect(out.lastEngine, 'system');
    // 女声与男声在系统朗读上是不同的声音。
    expect({for (final v in VoicePresets.all) v.binding('system')!.voices[VoiceLanguage.zh]}, {'female', 'male'});
    // 旧版本的五个音色按性别换成女声或男声。
    for (final id in ['yunxi', 'xiaoyou', 'wanxing']) {
      expect(VoicePresets.byId(id), VoicePresets.female);
    }
    for (final id in ['qingchuan', 'muyan']) {
      expect(VoicePresets.byId(id), VoicePresets.male);
    }
    expect(VoicePresets.byName('男生'), VoicePresets.male);
    expect(VoicePresets.byName('晚星'), VoicePresets.female);
  });

  test('按顺序播放；打断后清空队列、停止合成并恢复音乐', () async {
    final engine = _FakeEngine('system', offline: true, delay: const Duration(milliseconds: 20));
    final sink = _Sink(ms: 60);
    final ducks = <bool>[];
    final out = SpeechOutput(settings, engines: VoiceEngines(settings, engines: [engine]), sink: sink, onDuck: (d) async => ducks.add(d));
    final turn = out.begin();
    turn.add('一。二。三。四。');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(out.speaking, isTrue);
    await out.stop();
    expect(out.speaking, isFalse);
    final played = sink.played.length;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(sink.played.length, played, reason: '打断后不再播放剩余的句子');
    expect(sink.played.first, 'system:一。');
    expect(ducks, [true, false]);
  });

  test('相同的句子命中缓存，不再请求引擎', () async {
    final engine = _FakeEngine('cosyvoice');
    final sink = _Sink();
    final out = SpeechOutput(settings, engines: VoiceEngines(settings, engines: [engine]), sink: sink);
    await out.say('你好，我是云汐。');
    await out.say('你好，我是云汐。');
    expect(engine.requests, hasLength(1));
    expect(sink.played, hasLength(2));
  });

  test('情绪变化时同一个音色的声音 ID 保持不变', () async {
    final engine = _FakeEngine('system', offline: true);
    final out = SpeechOutput(settings, engines: VoiceEngines(settings, engines: [engine]), sink: _Sink());
    await out.say('[开心] 太好了！');
    await out.say('[难过] 有点遗憾。');
    expect(engine.requests.map((r) => r.$1).toSet(), {'female'});
    expect(engine.requests.map((r) => r.$2.prosody.emotion).toList(), [Emotion.happy, Emotion.sad]);
  });

  test('指定系统声音：ID 带上系统声音名称，合成时直接用这个声音', () async {
    final engine = _FakeEngine('system', offline: true);
    final out = SpeechOutput(settings, engines: VoiceEngines(settings, engines: [engine]), sink: _Sink());
    final v = VoicePresets.byId('sys:zh-cn-x-test');
    expect(v.id, 'sys:zh-cn-x-test');
    await out.say('你好。', voice: v);
    expect(engine.requests.single.$1, 'voice:zh-cn-x-test');
  });

  test('等待合成时不算发声，开始播放后才算（打断检测只在发声时打开）', () async {
    final engine = _FakeEngine('system', offline: true, delay: const Duration(milliseconds: 120));
    final sink = _Sink(ms: 120);
    final out = SpeechOutput(settings, engines: VoiceEngines(settings, engines: [engine]), sink: sink);
    final turn = out.begin();
    turn.add('第一句。');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(out.speaking, isTrue);
    expect(out.audible, isFalse, reason: '还在合成，没有声音');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(out.audible, isTrue);
    await turn.end();
    expect(out.audible, isFalse);
  });
}
