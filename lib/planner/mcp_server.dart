import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'agent_tools.dart';

/// Stateless Streamable HTTP, protocol 2025-11-25 (also 03-26/06-18).
/// Loopback only; no background service and no tool to apply a draft.
class PlannerMcpServer extends ChangeNotifier {
  final PlannerTools tools;
  final Future<void> Function()? refreshContext;
  HttpServer? _server;
  Future<void>? _starting;
  String? token;
  int _generation = 0, _inflight = 0;
  bool _disposed = false;
  PlannerMcpServer(this.tools, {this.refreshContext});
  static const versions = ['2025-03-26', '2025-06-18', '2025-11-25'];
  int? get port => _server?.port;
  bool get running => _server != null;
  bool get starting => _starting != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start({int port = 8765}) {
    if (_disposed) return Future.error(StateError('MCP 已关闭'));
    if (running) return Future.value();
    return _starting ??= _bind(port).whenComplete(() {
      _starting = null;
      _notify();
    });
  }

  Future<void> _bind(int port) async {
    final generation = ++_generation;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    if (generation != _generation || _disposed) {
      await server.close(force: true);
      return;
    }
    token = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    _server = server;
    _notify();
    server.listen(
      (request) {
        unawaited(_handle(request, generation));
      },
      onError: (_) {
        unawaited(stop());
      },
    );
  }

  Future<void> stop() async {
    _generation++;
    final server = _server;
    _server = null;
    token = null;
    _notify();
    await server?.close(force: true);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }

  Map<String, dynamic> _error(dynamic id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
  bool _authorized(HttpRequest request) {
    final expected = token;
    final value = request.headers.value('authorization');
    if (expected == null || value == null) return false;
    final a = utf8.encode('Bearer $expected'), b = utf8.encode(value);
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<void> _handle(HttpRequest request, int generation) async {
    final response = request.response;
    var counted = false;
    void json(dynamic value) {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(value));
    }

    void reject(int status) {
      response.statusCode = status;
    }

    try {
      response.headers.set('Cache-Control', 'no-store');
      final host = request.headers.value('host') ?? '';
      final originText = request.headers.value('origin');
      final origin = originText == null ? null : Uri.tryParse(originText);
      if (!RegExp(r'^(127\.0\.0\.1|localhost)(:\d+)?$').hasMatch(host) ||
          (originText != null &&
              (origin == null ||
                  !['http', 'https'].contains(origin.scheme) ||
                  !['127.0.0.1', 'localhost'].contains(origin.host) ||
                  origin.userInfo.isNotEmpty))) {
        reject(403);
        return;
      }
      if (!_authorized(request)) {
        reject(401);
        return;
      }
      if (request.uri.path != '/mcp') {
        reject(404);
        return;
      }
      if (request.method != 'POST') {
        response.headers.set('Allow', 'POST');
        reject(405);
        return;
      }
      if (_inflight >= 4) {
        reject(429);
        return;
      }
      _inflight++;
      counted = true;
      if (request.headers.contentType?.mimeType != 'application/json') {
        reject(415);
        return;
      }
      final accept = request.headers.value('accept') ?? '';
      if (!accept.contains('application/json') ||
          !accept.contains('text/event-stream')) {
        reject(406);
        return;
      }
      final version = request.headers.value('mcp-protocol-version');
      if (version != null && !versions.contains(version)) {
        reject(400);
        return;
      }
      if (request.contentLength > 262144) {
        reject(413);
        return;
      }
      final bytes = <int>[];
      await for (final part in request.timeout(const Duration(seconds: 10))) {
        bytes.addAll(part);
        if (bytes.length > 262144) {
          reject(413);
          return;
        }
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        json(_error(null, -32700, 'Parse error'));
        return;
      }
      if (decoded is! Map || decoded['jsonrpc'] != '2.0') {
        json(_error(null, -32600, 'Invalid Request'));
        return;
      }
      final id = decoded['id'];
      if (id != null && id is! String && id is! num) {
        json(_error(null, -32600, 'Invalid id'));
        return;
      }
      // No server-initiated requests exist; accept client response envelopes.
      if (!decoded.containsKey('method') &&
          (decoded.containsKey('result') || decoded.containsKey('error'))) {
        reject(202);
        return;
      }
      if (decoded['method'] is! String) {
        json(_error(id, -32600, 'Invalid method'));
        return;
      }
      final method = decoded['method'] as String;
      if (decoded['params'] != null && decoded['params'] is! Map) {
        json(_error(id, -32602, 'Invalid params'));
        return;
      }
      final params = Map<String, dynamic>.from(decoded['params'] as Map? ?? {});
      if (!decoded.containsKey('id')) {
        // Notifications never execute tools or mutate local data.
        if (method.startsWith('notifications/')) {
          reject(202);
        } else {
          reject(400);
        }
        return;
      }
      if (id == null) {
        json(_error(null, -32600, 'Request id must not be null'));
        return;
      }
      dynamic result;
      switch (method) {
        case 'initialize':
          if (params['protocolVersion'] is! String ||
              params['capabilities'] is! Map ||
              params['clientInfo'] is! Map) {
            json(
              _error(
                id,
                -32602,
                'initialize requires protocolVersion, capabilities, clientInfo',
              ),
            );
            return;
          }
          result = {
            'protocolVersion': versions.contains(params['protocolVersion'])
                ? params['protocolVersion']
                : versions.last,
            'capabilities': {'tools': {}, 'resources': {}},
            'serverInfo': {'name': 'ChronoPilot-Go', 'version': '0.2.0'},
            'instructions':
                'Read current context; propose schedules for existing tasks only. User must confirm in Android app.',
          };
        case 'ping':
          result = <String, dynamic>{};
        case 'tools/list':
          result = {'tools': PlannerTools.definitions};
        case 'resources/list':
          result = {
            'resources': [
              {
                'uri': 'chronopilot://schedule/context',
                'name': 'schedule-context',
                'description': '当前日程、任务和明确填写的偏好',
                'mimeType': 'application/json',
              },
            ],
          };
        case 'resources/templates/list':
          result = {'resourceTemplates': []};
        case 'resources/read':
          if (params['uri'] != 'chronopilot://schedule/context') {
            json(_error(id, -32602, 'Unknown resource'));
            return;
          }
          await refreshContext?.call();
          if (generation != _generation) return;
          result = {
            'contents': [
              {
                'uri': 'chronopilot://schedule/context',
                'mimeType': 'application/json',
                'text': jsonEncode(tools.context()),
              },
            ],
          };
        case 'tools/call':
          if (params['name'] is! String ||
              params['arguments'] != null && params['arguments'] is! Map) {
            json(_error(id, -32602, 'Invalid tool parameters'));
            return;
          }
          if (!PlannerTools.definitions.any(
            (e) => e['name'] == params['name'],
          )) {
            json(_error(id, -32602, 'Unknown tool'));
            return;
          }
          try {
            final args = Map<String, dynamic>.from(
              params['arguments'] as Map? ?? {},
            );
            await refreshContext?.call();
            if (generation != _generation) return;
            if (params['name'] == 'get_schedule_context' && args.isNotEmpty) {
              throw const FormatException('上下文工具不接受参数');
            }
            final value = params['name'] == 'get_schedule_context'
                ? tools.context()
                : await tools.saveMcpDraft(args);
            result = {
              'content': [
                {'type': 'text', 'text': jsonEncode(value)},
              ],
              'isError': false,
            };
          } catch (e) {
            result = {
              'content': [
                {
                  'type': 'text',
                  'text': e is FormatException
                      ? e.message.toString()
                      : '暂不可用，日程未修改',
                },
              ],
              'isError': true,
            };
          }
        default:
          json(_error(id, -32601, 'Method not found'));
          return;
      }
      if (generation == _generation) {
        json({'jsonrpc': '2.0', 'id': id, 'result': result});
      }
    } catch (_) {
      try {
        reject(400);
      } catch (_) {
        /* Connection already closed. */
      }
    } finally {
      if (counted) _inflight--;
      try {
        await response.close();
      } catch (_) {
        /* App may have stopped the server. */
      }
    }
  }
}
