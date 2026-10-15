import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/services/agent/deepseek_client.dart';

/// Only the transport is redirected in tests; production endpoint stays fixed.
class RedirectClient implements HttpClient {
  final HttpClient inner = HttpClient();
  final Uri testUri;
  RedirectClient(this.testUri);
  @override
  set connectionTimeout(Duration? value) {
    inner.connectionTimeout = value;
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    expect(url, DeepSeekClient.endpoint);
    return inner.postUrl(testUri);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('真实 HTTP 格式携带工具与 Bearer，读取 assistant 回复', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.headers.value('authorization'), 'Bearer local-test-key');
      final data = jsonDecode(await utf8.decoder.bind(request).join());
      expect(data['thinking']['type'], 'disabled');
      expect(data['model'], 'deepseek-flash');
      expect(data['tools'], hasLength(1));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {'role': 'assistant', 'content': '测试回复'},
            },
          ],
        }),
      );
      await request.response.close();
    });
    final client = DeepSeekClient(
      clientFactory: () =>
          RedirectClient(Uri.parse('http://127.0.0.1:${server.port}/chat')),
    );
    final result = await client.complete(
      apiKey: 'local-test-key',
      model: 'deepseek-flash',
      messages: [
        {'role': 'user', 'content': '测试'},
      ],
      tools: [
        {
          'type': 'function',
          'function': {
            'name': 'test',
            'parameters': {'type': 'object'},
          },
        },
      ],
    );
    expect(result['content'], '测试回复');
  });
  for (final code in [401, 402, 429, 500]) {
    test('HTTP $code 使用安全错误，不回显服务端正文', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((r) async {
        await r.drain<void>();
        r.response.statusCode = code;
        r.response.write('sensitive-response');
        await r.response.close();
      });
      final client = DeepSeekClient(
        clientFactory: () =>
            RedirectClient(Uri.parse('http://127.0.0.1:${server.port}')),
      );
      try {
        await client.complete(
          apiKey: 'test',
          model: 'test',
          messages: [],
          tools: [],
        );
        fail('should fail');
      } on AgentApiException catch (e) {
        expect(e.message, isNot(contains('sensitive-response')));
        expect(e.message, isNotEmpty);
      }
    });
  }
}
