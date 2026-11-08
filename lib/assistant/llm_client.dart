import 'dart:convert';

import 'package:dio/dio.dart';

import 'assistant_settings.dart';

/// 兼容 OpenAI 的对话接口（/chat/completions，支持函数调用）。DeepSeek、通义千问、Kimi、智谱与 OpenAI 都兼容。
class LlmClient {
  LlmClient(this.settings, {Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 60), responseType: ResponseType.plain));

  final AssistantSettings settings;
  final Dio _dio;

  String get _endpoint => '${settings.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/chat/completions';

  Options _options(ResponseType type) => Options(
    contentType: 'application/json',
    responseType: type,
    headers: {'Authorization': 'Bearer ${settings.apiKey}'},
    validateStatus: (_) => true,
  );

  /// 发送一轮对话，返回模型的回复消息（role 为 assistant，可能带 tool_calls）。
  Future<Map<String, dynamic>> complete(List<Map<String, dynamic>> messages, {List<Map<String, dynamic>> tools = const []}) async {
    final Response<String> res;
    try {
      res = await _dio.post<String>(
        _endpoint,
        data: jsonEncode({
          'model': settings.model,
          'messages': messages,
          if (tools.isNotEmpty) 'tools': tools,
          'temperature': 0.6,
        }),
        options: _options(ResponseType.plain),
      );
    } on DioException catch (e) {
      throw LlmException('连接不到大模型服务：${e.message ?? e.type.name}');
    }
    return _parseMessage(res.statusCode, res.data);
  }

  /// 流式对话（SSE）：边生成边把文字片段交给 [onText]，返回完整的回复消息（含拼好的 tool_calls）。
  /// 服务不支持流式、直接返回整段 JSON 时，同样能得到结果（文字一次性交给 [onText]）。
  Future<Map<String, dynamic>> stream(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>> tools = const [],
    void Function(String delta)? onText,
    CancelToken? cancel,
  }) async {
    final Response<ResponseBody> res;
    try {
      res = await _dio.post<ResponseBody>(
        _endpoint,
        data: jsonEncode({
          'model': settings.model,
          'messages': messages,
          if (tools.isNotEmpty) 'tools': tools,
          'temperature': 0.6,
          'stream': true,
        }),
        options: _options(ResponseType.stream),
        cancelToken: cancel,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw LlmException('连接不到大模型服务：${e.message ?? e.type.name}');
    }
    final body = res.data!;
    final type = body.headers['content-type']?.join(';') ?? '';
    if (res.statusCode != 200 || !type.contains('event-stream')) {
      final text = await utf8.decoder.bind(body.stream).join();
      final m = _parseMessage(res.statusCode, text);
      final content = '${m['content'] ?? ''}';
      if (content.isNotEmpty) onText?.call(content);
      return m;
    }
    final content = StringBuffer();
    final calls = <int, Map<String, dynamic>>{};
    try {
      await for (final line in utf8.decoder.bind(body.stream).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        Map<String, dynamic> j;
        try {
          j = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final delta = ((j['choices'] as List?)?.firstOrNull as Map?)?['delta'] as Map?;
        if (delta == null) continue;
        final piece = delta['content'];
        if (piece is String && piece.isNotEmpty) {
          content.write(piece);
          onText?.call(piece);
        }
        for (final c in (delta['tool_calls'] as List?)?.cast<Map>() ?? const <Map>[]) {
          final i = (c['index'] as num?)?.toInt() ?? calls.length;
          final call = calls.putIfAbsent(i, () => {'id': '', 'type': 'function', 'name': StringBuffer(), 'arguments': StringBuffer()});
          if (c['id'] is String && (c['id'] as String).isNotEmpty) call['id'] = c['id'];
          final f = c['function'] as Map?;
          if (f?['name'] is String) (call['name'] as StringBuffer).write(f!['name']);
          if (f?['arguments'] is String) (call['arguments'] as StringBuffer).write(f!['arguments']);
        }
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw LlmException('大模型服务的回答中断了：${e.message ?? e.type.name}');
    }
    final keys = calls.keys.toList()..sort();
    return {
      'role': 'assistant',
      'content': content.toString(),
      if (keys.isNotEmpty)
        'tool_calls': [
          for (final k in keys)
            {
              'id': '${calls[k]!['id']}'.isEmpty ? 'call_$k' : calls[k]!['id'],
              'type': 'function',
              'function': {'name': '${calls[k]!['name']}', 'arguments': '${calls[k]!['arguments']}'.ifEmpty('{}')},
            },
        ],
    };
  }

  Map<String, dynamic> _parseMessage(int? status, String? text) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(text ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      throw LlmException('大模型服务返回了无法解析的内容（$status）');
    }
    if (status != 200) {
      final err = j['error'];
      final msg = err is Map ? '${err['message'] ?? err['code'] ?? ''}' : '$err';
      throw LlmException(switch (status) {
        401 || 403 => '密钥无效或没有权限（$msg）',
        402 || 429 => '额度不足或请求太频繁（$msg）',
        404 => '接口地址或模型名称不正确（$msg）',
        _ => '大模型服务出错（$status：$msg）',
      });
    }
    final choice = ((j['choices'] as List?)?.firstOrNull as Map?)?['message'] as Map?;
    if (choice == null) throw LlmException('大模型服务没有返回回答');
    return Map<String, dynamic>.from(choice);
  }

  /// 测试连接：发一句很短的话，返回模型的回答。
  Future<String> ping() async {
    final m = await complete([
      {'role': 'user', 'content': '只回复“连接成功”四个字。'},
    ]);
    return '${m['content'] ?? ''}'.trim();
  }
}

class LlmException implements Exception {
  LlmException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 定义一个函数（工具）。
Map<String, dynamic> tool(String name, String description, Map<String, dynamic> properties, {List<String> required = const []}) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': {'type': 'object', 'properties': properties, 'required': required},
  },
};

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
