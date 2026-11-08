import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/assistant/assistant_controller.dart';
import 'package:yunyin/assistant/assistant_settings.dart';
import 'package:yunyin/assistant/llm_client.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/listen_stats.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/music_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/player/player_controller.dart';

class _Streams implements PlayerStream {
  @override
  dynamic noSuchMethod(Invocation invocation) => const Stream<Never>.empty();
}

class _Engine implements Player {
  @override
  PlayerStream get stream => _Streams();
  @override
  PlayerState get state => const PlayerState();
  @override
  PlatformPlayer? get platform => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// 搜索返回以关键词命名的歌曲。
class _Source extends MusicSource {
  final searches = <String>[];
  @override
  String get id => 'a';
  @override
  String get name => '测试平台';
  @override
  String get description => '';
  @override
  Set<SourceFeature> get features => const {};
  @override
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) async {
    searches.add(keyword);
    return SearchResult(songs: [Song(id: keyword, sourceId: 'a', name: keyword.split(' ').first)]);
  }

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async => const StreamInfo(url: 'https://example.com/a.mp3');
}

/// 按请求的方式回复：流式请求（responseType 为 stream）时回复数据流。[sse] 为 true 时把 [message]
/// 拆成多段 SSE 事件（文字逐字、函数参数分两段），否则回复整段 JSON（不支持流式的服务）。
Response<dynamic> _reply(RequestOptions o, Map<String, dynamic> message, {int status = 200, bool sse = true, Map<String, dynamic>? body}) {
  final json = jsonEncode(body ?? {'choices': [{'message': message}]});
  if (o.responseType != ResponseType.stream) return Response(requestOptions: o, statusCode: status, data: json);
  if (!sse || status != 200) {
    return Response(requestOptions: o, statusCode: status, data: ResponseBody.fromString(json, status, headers: {'content-type': ['application/json']}));
  }
  final events = <Map<String, dynamic>>[];
  for (final ch in '${message['content'] ?? ''}'.split('')) {
    events.add({'content': ch});
  }
  final calls = (message['tool_calls'] as List?) ?? const [];
  for (var i = 0; i < calls.length; i++) {
    final c = calls[i] as Map;
    final args = '${c['function']['arguments']}';
    final half = args.length ~/ 2;
    events.add({'tool_calls': [{'index': i, 'id': c['id'], 'type': 'function', 'function': {'name': c['function']['name'], 'arguments': args.substring(0, half)}}]});
    events.add({'tool_calls': [{'index': i, 'function': {'arguments': args.substring(half)}}]});
  }
  final text = [for (final d in events) 'data: ${jsonEncode({'choices': [{'index': 0, 'delta': d}]})}\n\n', 'data: [DONE]\n\n'].join();
  return Response(requestOptions: o, statusCode: 200, data: ResponseBody.fromString(text, 200, headers: {'content-type': ['text/event-stream; charset=utf-8']}));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppSettings app;
  late AssistantSettings settings;
  late _Source source;
  late PlayerController player;
  late List<Map<String, dynamic>> requests;
  late List<Map<String, dynamic>> replies;
  late AssistantController assistant;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app = AppSettings();
    await app.init();
    settings = AssistantSettings();
    await settings.init();
    source = _Source();
    final sources = SourceManager([source]);
    await sources.init();
    player = PlayerController(sources, app, engine: _Engine());
    await player.init();
    requests = [];
    replies = [];
    final dio = Dio(BaseOptions(responseType: ResponseType.plain))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            requests.add(jsonDecode(o.data as String) as Map<String, dynamic>);
            h.resolve(_reply(o, replies.removeAt(0)));
          },
        ),
      );
    assistant = AssistantController(settings: settings, app: app, player: player, sources: sources, stats: ListenStats(), llm: LlmClient(settings, dio: dio));
  });

  tearDown(() => player.dispose());

  test('常用指令在本机完成，不需要大模型：点歌、暂停、定时', () async {
    await assistant.submit('播放晴天');
    expect(source.searches, ['晴天']);
    expect(player.current?.name, '晴天');
    expect(assistant.messages.last.text, contains('晴天'));
    await assistant.submit('三十分钟后停止播放');
    expect(assistant.messages.last.text, contains('30 分钟'));
    expect(requests, isEmpty);
  });

  test('没有配置大模型时，描述性的需求提示去设置', () async {
    await assistant.submit('来点适合跑步的歌');
    expect(assistant.messages.last.text, contains('设置'));
    expect(requests, isEmpty);
  });

  test('大模型通过函数调用生成并播放歌单，再给出回答', () async {
    settings.setLlm(apiKey: 'sk-test');
    replies.addAll([
      {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {
              'name': 'play_songs',
              'arguments': jsonEncode({
                'songs': ['夜曲 周杰伦', '倔强 五月天'],
                'title': '跑步歌单',
              }),
            },
          },
        ],
      },
      {'role': 'assistant', 'content': '已为你播放跑步歌单，加油！'},
    ]);
    await assistant.submit('来点适合跑步的歌');
    expect(requests, hasLength(2));
    expect((requests.first['tools'] as List).map((t) => t['function']['name']), contains('play_songs'));
    // 第二轮带上了函数的执行结果。
    final toolResult = (requests[1]['messages'] as List).lastWhere((m) => m['role'] == 'tool');
    expect(toolResult['tool_call_id'], 'call_1');
    expect(toolResult['content'], contains('夜曲'));
    expect(player.queue.map((s) => s.name), ['夜曲', '倔强']);
    expect(assistant.messages.last.text, '已为你播放跑步歌单，加油！');
    expect(assistant.messages.last.songs, hasLength(2));
    expect(assistant.messages.last.streaming, isFalse);
    expect(requests.first['stream'], isTrue);
  });

  test('流式回答：情绪标记不显示；不支持流式的服务直接返回整段回答也能用', () async {
    settings.setLlm(apiKey: 'sk-test');
    replies.add({'role': 'assistant', 'content': '[开心] 好呀，这首歌讲的是青春。'});
    await assistant.submit('这首歌讲了什么');
    expect(assistant.messages.last.text, '好呀，这首歌讲的是青春。');
    final dio = Dio(BaseOptions(responseType: ResponseType.plain))
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.resolve(_reply(o, {'role': 'assistant', 'content': '[平静] 晚安。'}, sse: false))));
    final a = AssistantController(settings: settings, app: app, player: player, sources: SourceManager([source]), stats: ListenStats(), llm: LlmClient(settings, dio: dio));
    await a.submit('说晚安');
    expect(a.messages.last.text, '晚安。');
  });

  test('大模型出错时给出原因', () async {
    settings.setLlm(apiKey: 'sk-test');
    final dio = Dio(BaseOptions(responseType: ResponseType.plain))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(_reply(o, const {}, status: 401, body: {'error': {'message': 'invalid key'}})),
        ),
      );
    final a = AssistantController(settings: settings, app: app, player: player, sources: SourceManager([source]), stats: ListenStats(), llm: LlmClient(settings, dio: dio));
    await a.submit('这首歌讲了什么');
    expect(a.messages.last.text, contains('密钥无效'));
  });

  test('语音控制云音本身：本地指令与大模型的 control_app 都会改变设置', () async {
    await assistant.submit('打开深色模式');
    expect(app.themeMode, ThemeMode.dark);
    await assistant.submit('主题色换成青绿');
    expect(app.accent, AccentColor.teal);
    await assistant.submit('显示歌词翻译');
    expect(app.showTranslation, isTrue);
    expect(requests, isEmpty);
    settings.setLlm(apiKey: 'sk-test');
    replies.addAll([
      {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'c1',
            'type': 'function',
            'function': {'name': 'control_app', 'arguments': jsonEncode({'action': 'playerStyle', 'value': '黑胶'})},
          },
        ],
      },
      {'role': 'assistant', 'content': '[开心] 换好啦！'},
    ]);
    await assistant.submit('播放页弄成那种唱片的样子');
    expect(app.playerStyle, PlayerStyle.vinyl);
    expect(assistant.messages.last.text, '换好啦！');
  });
}
