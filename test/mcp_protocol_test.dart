import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/planner/agent_tools.dart';
import 'package:celechron/planner/mcp_server.dart';
import 'package:celechron/planner/repository.dart';

void main() {
  test('MCP malformed JSON、版本、Accept 与通知均按协议拒绝或应答', () async {
    final r = PlannerRepository(scope: 'test', writer: (_) async {});
    final server = PlannerMcpServer(PlannerTools(r));
    await Future.wait([server.start(port: 0), server.start(port: 0)]);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.stop();
      server.dispose();
    });
    Future<(int, dynamic)> send(
      String body, {
      String method = 'POST',
      String? version,
      String accept = 'application/json, text/event-stream',
    }) async {
      final req = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${server.port}/mcp'),
      );
      req.headers.set('authorization', 'Bearer ${server.token}');
      req.headers.contentType = ContentType.json;
      req.headers.set('accept', accept);
      if (version != null) req.headers.set('mcp-protocol-version', version);
      if (method == 'POST') req.write(body);
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
    }

    expect((await send('{')).$2['error']['code'], -32700);
    expect((await send('[]')).$2['error']['code'], -32600);
    expect((await send('{}', version: '2099-01-01')).$1, 400);
    expect((await send('{}', accept: 'text/plain')).$1, 406);
    expect((await send('', method: 'GET')).$1, 405);
    expect(
      (await send(
        jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
      )).$1,
      202,
    );
    expect(
      (await send(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'tools/call',
          'params': {'name': 'propose_schedule'},
        }),
      )).$1,
      400,
    );
    expect(r.sessions, isEmpty);
    expect(
      (await send(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': [],
        }),
      )).$2['error']['code'],
      -32602,
    );
  });
  test('在绑定完成前停止不会遗留监听端口', () async {
    final r = PlannerRepository(scope: 'test', writer: (_) async {});
    final s = PlannerMcpServer(PlannerTools(r));
    final starting = s.start(port: 0);
    await s.stop();
    await starting;
    expect(s.running, isFalse);
    expect(s.token, isNull);
    s.dispose();
  });
}
