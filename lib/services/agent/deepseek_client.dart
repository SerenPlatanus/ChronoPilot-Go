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

/// Streaming is optional for injected/offline clients; production uses SSE.
abstract class AgentStreamingClient implements AgentCompletionClient {
  Future<Map<String, dynamic>> completeStreaming({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required void Function(String delta) onTextDelta,
  });
}

class AgentApiException implements Exception {
  final String message;
  const AgentApiException(this.message);
  @override
  String toString() => message;
}

class DeepSeekClient implements AgentStreamingClient {
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
  }) => completeStreaming(
    apiKey: apiKey,
    model: model,
    messages: messages,
    tools: tools,
    onTextDelta: (_) {},
  );

  @override
  Future<Map<String, dynamic>> completeStreaming({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required void Function(String delta) onTextDelta,
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
            'stream': true,
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
        return readDeepSeekStream(response, onTextDelta: onTextDelta);
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

/// Consumes SSE frames across arbitrary UTF-8/network boundaries. Tool argument
/// fragments are assembled before returning; no partial tool is executable.
Future<Map<String, dynamic>> readDeepSeekStream(
  Stream<List<int>> source, {
  required void Function(String delta) onTextDelta,
}) async {
  final text = StringBuffer(), calls = <int, Map<String, dynamic>>{};
  final data = <String>[];
  var bytes = 0, done = false;
  String? finish;
  final bounded = source.map((chunk) {
    bytes += chunk.length;
    if (bytes > 2 * 1024 * 1024) {
      throw const AgentApiException('模型响应过大，请缩小规划范围。');
    }
    return chunk;
  });
  void event() {
    if (data.isEmpty) return;
    final payload = data.join('\n');
    data.clear();
    if (payload == '[DONE]') {
      done = true;
      return;
    }
    final body = jsonDecode(payload) as Map<String, dynamic>;
    if (body.containsKey('error')) throw const AgentApiException('模型响应中断，请重试。');
    final choices = body['choices'] as List? ?? [];
    if (choices.isEmpty) return;
    final choice = choices.first as Map;
    final delta = choice['delta'] as Map? ?? {};
    if (delta['role'] != null && delta['role'] != 'assistant') {
      throw const FormatException();
    }
    final content = delta['content'] as String?;
    if (content != null && content.isNotEmpty) {
      text.write(content);
      onTextDelta(content);
    }
    for (final raw in delta['tool_calls'] as List? ?? []) {
      final part = raw as Map, index = part['index'];
      if (index is! int || index < 0 || index >= 8) {
        throw const AgentApiException('模型工具调用过多或格式异常。');
      }
      final call = calls.putIfAbsent(
        index,
        () => {
          'id': '',
          'type': 'function',
          'function': {'name': '', 'arguments': ''},
        },
      );
      if (part['id'] != null) {
        call['id'] = '${call['id']}${part['id'] as String}';
      }
      if (part['type'] != null && part['type'] != 'function') {
        throw const FormatException();
      }
      final fn = part['function'] as Map? ?? {};
      final assembled = call['function'] as Map;
      for (final key in ['name', 'arguments']) {
        if (fn[key] != null) {
          assembled[key] = '${assembled[key]}${fn[key] as String}';
        }
      }
    }
    if (choice['finish_reason'] != null) {
      finish = choice['finish_reason'] as String;
    }
  }

  await for (final line
      in bounded.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      event();
      if (done) break;
    } else if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
    }
  }
  if (!done) event();
  if (!done || finish == null) {
    throw const AgentApiException('回复连接中断，请重试；未写入日程。');
  }
  if (finish == 'length') throw const AgentApiException('方案过长被截断，请缩小规划范围后重试。');
  if (finish != 'stop' && finish != 'tool_calls') {
    throw const AgentApiException('模型未完整返回回复，请重试。');
  }
  final ordered = calls.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  if ((finish == 'tool_calls') != ordered.isNotEmpty) {
    throw const FormatException();
  }
  for (final entry in ordered) {
    final call = entry.value;
    if ((call['id'] as String).isEmpty ||
        ((call['function'] as Map)['name'] as String).isEmpty) {
      throw const FormatException();
    }
  }
  return {
    'role': 'assistant',
    'content': text.toString(),
    if (ordered.isNotEmpty) 'tool_calls': ordered.map((e) => e.value).toList(),
  };
}
