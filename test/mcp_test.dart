import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/planner/repository.dart';
import 'package:celechron/planner/agent_tools.dart';
import 'package:celechron/planner/mcp_server.dart';
import 'package:celechron/planner/item.dart';

void main() {
  test('MCP 授权、协议初始化、工具发现和草稿确认隔离', () async {
    final r = PlannerRepository(scope: 'test', writer: (_) async {});
    final server = PlannerMcpServer(PlannerTools(r));
    await server.start(port: 0);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.stop();
    });
    Future<(int, dynamic)> call(
      String method, {
      bool auth = true,
      Map<String, dynamic>? params,
      String? origin,
    }) async {
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/mcp'),
      );
      req.headers.contentType = ContentType.json;
      req.headers.set('accept', 'application/json, text/event-stream');
      if (auth) req.headers.set('authorization', 'Bearer ${server.token}');
      if (origin != null) req.headers.set('origin', origin);
      req.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': method,
          'params': params ?? {},
        }),
      );
      final response = await req.close();
      final body = await utf8.decoder.bind(response).join();
      return (response.statusCode, body.isEmpty ? null : jsonDecode(body));
    }

    expect((await call('tools/list', auth: false)).$1, 401);
    expect((await call('tools/list', origin: 'https://evil.example')).$1, 403);
    final init = await call(
      'initialize',
      params: {
        'protocolVersion': '2025-11-25',
        'capabilities': {},
        'clientInfo': {'name': 'test', 'version': '1'},
      },
    );
    expect(init.$2['result']['protocolVersion'], '2025-11-25');
    final listing = await call('tools/list');
    expect(listing.$2['result']['tools'], hasLength(2));
    final date = DateTime.now();
    final now = DateTime(date.year, date.month, date.day + 1, 14);
    await r.saveItem(
      const Item(
        id: 'task',
        categoryId: 'task',
        title: '学习',
        estimatedMinutes: 30,
      ),
    );
    final plan = await call(
      'tools/call',
      params: {
        'name': 'propose_schedule',
        'arguments': {
          'summary': '测试',
          'contextVersion': PlannerTools(r).contextVersion,
          'operations': [
            {
              'action': 'add',
              'parentId': 'task',
              'title': '日程',
              'start': timestamp(now),
              'end': timestamp(now.add(const Duration(minutes: 30))),
            },
          ],
        },
      },
    );
    expect(plan.$2['result']['isError'], isFalse);
    expect(r.items, hasLength(1));
    expect(r.sessions, hasLength(1));
    final apply = await call('tools/call', params: {'name': 'apply_plan'});
    expect(apply.$2['error']['code'], -32602);
    expect(r.items, hasLength(1));
    final resource = await call(
      'resources/read',
      params: {'uri': 'chronopilot://schedule/context'},
    );
    expect(
      resource.$2['result']['contents'][0]['mimeType'],
      'application/json',
    );
    expect((await call('unknown')).$2['error']['code'], -32601);
    final previousToken = server.token;
    await server.stop();
    await server.start(port: 0);
    expect(server.token, isNot(previousToken));
    await server.stop();
    expect(server.token, isNull);
    expect(server.running, isFalse);
  });
}
