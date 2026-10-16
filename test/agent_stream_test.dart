import 'package:flutter/material.dart';
import 'package:celechron/planner/chat_page.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/services/agent/deepseek_client.dart';
import 'package:celechron/planner/chat_controller.dart';
import 'package:celechron/planner/repository.dart';

String frame(Map<String, dynamic> delta, {String? finish}) =>
    'data: ${jsonEncode({
      'choices': [
        {'index': 0, 'delta': delta, 'finish_reason': finish},
      ],
    })}\r\n\r\n';
Stream<List<int>> bytes(String source) =>
    Stream.fromIterable(utf8.encode(source).map((b) => [b]));
void main() {
  testWidgets('聊天页在请求结束前显示增量，取消后可重试', (tester) async {
    final repo = PlannerRepository(scope: 'ui-stream', writer: (_) async {}),
        client = StreamingFake();
    final chat = PlannerChat(repo, client: client);
    await tester.pumpWidget(
      MaterialApp(
        home: PlannerChatPage(
          chat: chat,
          apiKey: 'test',
          model: 'test',
          beforeSend: () async {},
          onSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '安排时间');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await client.started.future;
    client.delta('正在逐段显示');
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('正在逐段显示'), findsOneWidget);
    expect(client.response.isCompleted, false);
    await tester.tap(find.text('取消本次请求'));
    await tester.pumpAndSettle();
    expect(find.text('正在逐段显示'), findsNothing);
    expect(find.text('重试上一条'), findsOneWidget);
    expect((repo.sessions.first['messages'] as List), hasLength(1));
    client.response.complete({'role': 'assistant', 'content': '迟到'});
    await tester.pumpWidget(const SizedBox());
    chat.dispose();
  });
  test('SSE 中文跨 UTF-8 字节分片，持续交付增量，忽略心跳', () async {
    final live = <String>[];
    final body =
        ': keepalive\r\n\r\n${frame({'role': 'assistant', 'content': '你好'})}${frame({'content': '，世界'})}${frame({}, finish: 'stop')}data: [DONE]\r\n\r\n';
    final response = await readDeepSeekStream(
      bytes(body),
      onTextDelta: live.add,
    );
    expect(live, ['你好', '，世界']);
    expect(response['content'], '你好，世界');
  });
  test('多个工具的参数交错分片，完整后按 index 组装', () async {
    final body =
        '${frame({
          'tool_calls': [
            {
              'index': 0,
              'id': 'call-a',
              'type': 'function',
              'function': {'name': 'get_schedule_context', 'arguments': '{'},
            },
            {
              'index': 1,
              'id': 'call-b',
              'type': 'function',
              'function': {'name': 'propose_schedule', 'arguments': '{"title":'},
            },
          ],
        })}${frame({
          'tool_calls': [
            {
              'index': 1,
              'function': {'arguments': '"学习"}'},
            },
            {
              'index': 0,
              'function': {'arguments': '}'},
            },
          ],
        })}${frame({}, finish: 'tool_calls')}data: [DONE]\n\n';
    final response = await readDeepSeekStream(bytes(body), onTextDelta: (_) {});
    final calls = response['tool_calls'] as List;
    expect(calls[0]['id'], 'call-a');
    expect(jsonDecode(calls[0]['function']['arguments']), {});
    expect(jsonDecode(calls[1]['function']['arguments']), {'title': '学习'});
  });
  test('断流、截断及未完成工具参数不作为完整响应', () async {
    final partial = frame({'content': '部分回复'});
    await expectLater(
      readDeepSeekStream(bytes(partial), onTextDelta: (_) {}),
      throwsA(isA<AgentApiException>()),
    );
    await expectLater(
      readDeepSeekStream(
        bytes('$partial${frame({}, finish: 'length')}data: [DONE]\n\n'),
        onTextDelta: (_) {},
      ),
      throwsA(isA<AgentApiException>()),
    );
    await expectLater(
      readDeepSeekStream(
        bytes(
          '${frame({
            'tool_calls': [
              {
                'index': 0,
                'function': {'arguments': '{no'},
              },
            ],
          }, finish: 'tool_calls')}data: [DONE]\n\n',
        ),
        onTextDelta: (_) {},
      ),
      throwsFormatException,
    );
  });
  test('在完整结束前即可看到文本；只在结束后持久化一条回复', () async {
    final repo = PlannerRepository(scope: 'stream-test', writer: (_) async {}),
        client = StreamingFake();
    final chat = PlannerChat(repo, client: client), id = await chat.create();
    final sending = chat.send(id, '你好', 'key', 'model');
    await client.started.future;
    client.delta('先显示');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(chat.streamedText, '先显示');
    expect(chat.session(id)!['messages'], hasLength(1));
    client.delta('，再完成');
    client.response.complete({'role': 'assistant', 'content': '先显示，再完成'});
    await sending;
    expect(chat.streamedText, isEmpty);
    expect(chat.session(id)!['messages'], hasLength(2));
    expect((chat.session(id)!['messages'] as List).last['content'], '先显示，再完成');
    chat.dispose();
  });
  test('取消后清除临时文本，忽略迟到增量和响应；可重试', () async {
    final repo = PlannerRepository(scope: 'stream-test', writer: (_) async {}),
        client = StreamingFake();
    final chat = PlannerChat(repo, client: client), id = await chat.create();
    final sending = chat.send(id, '你好', 'key', 'model');
    await client.started.future;
    client.delta('未完成');
    chat.cancel();
    await sending;
    expect(chat.streamedText, isEmpty);
    client.delta('迟到');
    client.response.complete({'role': 'assistant', 'content': '迟到回复'});
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(chat.session(id)!['messages'], hasLength(1));
    expect(chat.streamedText, isEmpty);
    client.immediate = true;
    await chat.retry(id, 'key', 'model');
    expect(chat.session(id)!['messages'], hasLength(2));
    chat.dispose();
  });
}

class StreamingFake implements AgentStreamingClient {
  final started = Completer<void>(),
      response = Completer<Map<String, dynamic>>();
  late void Function(String) delta;
  bool immediate = false;
  @override
  Future<Map<String, dynamic>> completeStreaming({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required void Function(String) onTextDelta,
  }) {
    delta = onTextDelta;
    if (!started.isCompleted) started.complete();
    return immediate
        ? Future.value({'role': 'assistant', 'content': '重试完成'})
        : response.future;
  }

  @override
  Future<Map<String, dynamic>> complete({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) => throw UnimplementedError();
  @override
  void cancel() {}
}
