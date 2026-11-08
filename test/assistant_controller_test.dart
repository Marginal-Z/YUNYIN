import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/assistant/assistant_controller.dart';
import 'package:yunyin/assistant/assistant_settings.dart';
import 'package:yunyin/assistant/llm_client.dart';
import 'package:yunyin/core/settings.dart';
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
            final message = replies.removeAt(0);
            h.resolve(Response(requestOptions: o, statusCode: 200, data: jsonEncode({'choices': [{'message': message}]})));
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
  });

  test('大模型出错时给出原因', () async {
    settings.setLlm(apiKey: 'sk-test');
    final dio = Dio(BaseOptions(responseType: ResponseType.plain))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response(requestOptions: o, statusCode: 401, data: jsonEncode({'error': {'message': 'invalid key'}}))),
        ),
      );
    final a = AssistantController(settings: settings, app: app, player: player, sources: SourceManager([source]), stats: ListenStats(), llm: LlmClient(settings, dio: dio));
    await a.submit('这首歌讲了什么');
    expect(a.messages.last.text, contains('密钥无效'));
  });
}
