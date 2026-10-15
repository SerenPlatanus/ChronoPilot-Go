import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract class AgentCompletionClient {
  Future<Map<String, dynamic>> complete({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  });
  void cancel();
}

class AgentApiException implements Exception {
  final String message;
  const AgentApiException(this.message);
  @override
  String toString() => message;
}

class DeepSeekClient implements AgentCompletionClient {
  HttpClient? _active;
  final HttpClient Function() _factory;
  DeepSeekClient({HttpClient Function()? clientFactory})
    : _factory = clientFactory ?? HttpClient.new;
  // Fixed official endpoint: credentials cannot be redirected to a custom host.
  static final endpoint = Uri.https('api.deepseek.com', '/chat/completions');

  @override
  Future<Map<String, dynamic>> complete({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async {
    final client = _factory()..connectionTimeout = const Duration(seconds: 15);
    _active = client;
    try {
      return await (() async {
        final request = await client.postUrl(endpoint);
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
        request.write(
          jsonEncode({
            'model': model,
            'messages': messages,
            'tools': tools,
            'tool_choice': 'auto',
            'stream': false,
            'thinking': {'type': 'disabled'},
            'max_tokens': 4096,
          }),
        );
        final response = await request.close();
        if (response.statusCode != 200) {
          // Do not surface raw response bodies, which may echo submitted data.
          throw AgentApiException(switch (response.statusCode) {
            401 => 'API Key 无效或已过期，请在 Agent 设置中更换。',
            402 => 'DeepSeek 账户余额不足。',
            429 => '请求过于频繁，请稍后再试。',
            400 => 'DeepSeek 请求不被接受，请检查模型设置。',
            _ => 'DeepSeek 服务暂不可用（HTTP ${response.statusCode}）。',
          });
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 2 * 1024 * 1024) {
            throw const AgentApiException('模型响应过大，请缩小规划范围。');
          }
        }
        final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final choice = (body['choices'] as List).first as Map<String, dynamic>;
        if (choice['finish_reason'] == 'length') {
          throw const AgentApiException('方案过长被截断，请缩小规划范围后重试。');
        }
        final message = Map<String, dynamic>.from(choice['message'] as Map);
        if (message['role'] != 'assistant') throw const FormatException();
        return message;
      })().timeout(const Duration(seconds: 90));
    } on AgentApiException {
      rethrow;
    } on TimeoutException {
      throw const AgentApiException('DeepSeek 响应超时，请重试。');
    } on SocketException {
      throw const AgentApiException('无法连接 DeepSeek，请检查网络。');
    } on Object {
      throw const AgentApiException('请求已中断或模型返回格式异常，请重试。');
    } finally {
      client.close(force: true);
      if (identical(_active, client)) _active = null;
    }
  }

  @override
  void cancel() {
    _active?.close(force: true);
    _active = null;
  }
}
