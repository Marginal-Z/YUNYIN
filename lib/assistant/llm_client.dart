import 'dart:convert';

import 'package:dio/dio.dart';

import 'assistant_settings.dart';

/// 兼容 OpenAI 的对话接口（/chat/completions，支持函数调用）。DeepSeek、通义千问、Kimi、智谱与 OpenAI 都兼容。
class LlmClient {
  LlmClient(this.settings, {Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 60), responseType: ResponseType.plain));

  final AssistantSettings settings;
  final Dio _dio;

  /// 发送一轮对话，返回模型的回复消息（role 为 assistant，可能带 tool_calls）。
  Future<Map<String, dynamic>> complete(List<Map<String, dynamic>> messages, {List<Map<String, dynamic>> tools = const []}) async {
    final base = settings.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final Response<String> res;
    try {
      res = await _dio.post<String>(
        '$base/chat/completions',
        data: jsonEncode({
          'model': settings.model,
          'messages': messages,
          if (tools.isNotEmpty) 'tools': tools,
          'temperature': 0.6,
        }),
        options: Options(
          contentType: 'application/json',
          headers: {'Authorization': 'Bearer ${settings.apiKey}'},
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw LlmException('连接不到大模型服务：${e.message ?? e.type.name}');
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      throw LlmException('大模型服务返回了无法解析的内容（${res.statusCode}）');
    }
    if (res.statusCode != 200) {
      final err = j['error'];
      final msg = err is Map ? '${err['message'] ?? err['code'] ?? ''}' : '$err';
      throw LlmException(switch (res.statusCode) {
        401 || 403 => '密钥无效或没有权限（$msg）',
        402 || 429 => '额度不足或请求太频繁（$msg）',
        404 => '接口地址或模型名称不正确（$msg）',
        _ => '大模型服务出错（${res.statusCode}：$msg）',
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
