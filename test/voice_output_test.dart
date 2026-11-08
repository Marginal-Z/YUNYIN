import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/voice/engines/cloud_engines.dart';
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

  test('引擎失败时自动降级到下一个，并在冷却期内跳过它；所有音色都使用各自独立的声音 ID', () async {
    final a = _FakeEngine('cosyvoice', fail: true);
    final b = _FakeEngine('local', offline: true);
    final engines = VoiceEngines(settings, engines: [a, b]);
    final sink = _Sink();
    final out = SpeechOutput(settings, engines: engines, sink: sink);
    await out.say('第一句。第二句。');
    expect(sink.played, ['local:第一句。', 'local:第二句。']);
    expect(a.requests, hasLength(1), reason: '失败后进入冷却，第二句直接用下一个引擎');
    expect(out.lastEngine, 'local');
    // 五个预设音色在本地引擎上使用互不相同的中文声音模型。
    final ids = {for (final v in VoicePresets.all) v.binding('local')!.voices[VoiceLanguage.zh]};
    expect(ids, hasLength(5));
    for (final engine in ['cosyvoice', 'elevenlabs']) {
      expect({for (final v in VoicePresets.all) v.binding(engine)!.voices[VoiceLanguage.zh]}, hasLength(5), reason: '$engine 的五个音色是不同的音色 ID');
    }
  });

  test('按顺序播放；打断后清空队列、停止合成并恢复音乐', () async {
    final engine = _FakeEngine('local', offline: true, delay: const Duration(milliseconds: 20));
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
    expect(sink.played.first, 'local:一。');
    expect(ducks, [true, false]);
  });

  test('相同的句子命中缓存，不再请求引擎', () async {
    final engine = _FakeEngine('local', offline: true);
    final sink = _Sink();
    final out = SpeechOutput(settings, engines: VoiceEngines(settings, engines: [engine]), sink: sink);
    await out.say('你好，我是云汐。');
    await out.say('你好，我是云汐。');
    expect(engine.requests, hasLength(1));
    expect(sink.played, hasLength(2));
  });

  test('情绪变化时同一个音色的声音 ID 保持不变', () async {
    final engine = _FakeEngine('local', offline: true);
    final out = SpeechOutput(settings, engines: VoiceEngines(settings, engines: [engine]), sink: _Sink());
    await out.say('[开心] 太好了！');
    await out.say('[难过] 有点遗憾。');
    expect(engine.requests.map((r) => r.$1).toSet(), {LocalVoiceIds.huayan});
    expect(engine.requests.map((r) => r.$2.prosody.emotion).toList(), [Emotion.happy, Emotion.sad]);
  });

  test('用户在音色中心填写的声音 ID 覆盖默认值', () async {
    final engine = _FakeEngine('fish');
    final out = SpeechOutput(settings, engines: VoiceEngines(settings, engines: [engine]), sink: _Sink());
    settings.setOverride('yunxi', 'fish', VoiceLanguage.zh, 'abc123');
    await out.say('测试。');
    expect(engine.requests.single.$1, 'abc123');
  });

  test('适配层：不支持的参数被换算或丢弃，数值在各引擎允许的范围内', () {
    for (final e in Emotion.values) {
      final s = ElevenLabsEngine.voiceSettings(Prosody(rate: 2, emotion: e, intensity: 1));
      expect(s['speed'] as double, lessThanOrEqualTo(1.2));
      expect(s['stability'] as double, inInclusiveRange(0.2, 0.85));
      expect(s['style'] as double, inInclusiveRange(0, 0.8));
      expect(CosyVoiceEngine.rateFor(Prosody(rate: 3, emotion: e, intensity: 1)), lessThanOrEqualTo(2));
    }
    expect(ElevenLabsEngine.modelFor(VoiceLanguage.th, 'eleven_multilingual_v2'), 'eleven_v3');
    expect(FishAudioEngine.withEmotion('你好', const Prosody(emotion: Emotion.happy, intensity: 0.8), 's1'), '(happy) 你好');
    expect(FishAudioEngine.withEmotion('你好', const Prosody(emotion: Emotion.happy, intensity: 0.8), 'speech-1.5'), '你好');
  });

  test('ElevenLabs：请求路径、密钥头与模型；密钥错误时不重试', () async {
    settings.setEngine('elevenlabs', const EngineConfig(apiKey: 'k'));
    final seen = <RequestOptions>[];
    var status = 200;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            seen.add(o);
            if (status != 200) {
              h.reject(DioException(requestOptions: o, response: Response(requestOptions: o, statusCode: status, data: utf8.encode('bad key')), type: DioExceptionType.badResponse));
              return;
            }
            h.resolve(Response(requestOptions: o, statusCode: 200, data: ResponseBody.fromBytes(utf8.encode('mp3'), 200)));
          },
        ),
      );
    final engine = ElevenLabsEngine(settings, dio: dio);
    final b = VoicePresets.muyan.binding('elevenlabs')!;
    final audio = await engine.synthesize(b, const TtsRequest('hi', language: VoiceLanguage.en)).toList();
    expect(audio.single.format, 'mp3');
    expect(seen.single.path, contains('/v1/text-to-speech/${b.voices[VoiceLanguage.en]}/stream'));
    expect(seen.single.headers['xi-api-key'], 'k');
    expect((jsonDecode(seen.single.data as String) as Map)['model_id'], 'eleven_multilingual_v2');
    status = 401;
    await expectLater(engine.synthesize(b, const TtsRequest('hi', language: VoiceLanguage.en)).toList(), throwsA(isA<TtsException>().having((e) => e.retryable, 'retryable', false)));
  });
}
