import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'agent_tools.dart';

/// Foreground, authenticated loopback Streamable HTTP (JSON response mode).
/// No endpoint can apply a plan. Confirmation exists only in the app UI.
class PlannerMcpServer {
  final PlannerTools tools;
  HttpServer? _server;
  String? token;
  PlannerMcpServer(this.tools);
  int? get port => _server?.port;
  bool get running => _server != null;
  Future<void> start({int port = 8765}) async {
    if (running) return;
    token = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen((request) {
      unawaited(_handle(request));
    });
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    token = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    void reject(int status) {
      response.statusCode = status;
    }

    try {
      final origin = request.headers.value('origin');
      final host = request.headers.value('host') ?? '';
      if (!RegExp(r'^(127\.0\.0\.1|localhost)(:\d+)?$').hasMatch(host) ||
          (origin != null &&
              ![
                '127.0.0.1',
                'localhost',
              ].contains(Uri.tryParse(origin)?.host))) {
        reject(403);
        return;
      }
      if (token == null ||
          request.headers.value('authorization') != 'Bearer $token') {
        reject(401);
        return;
      }
      if (request.uri.path != '/mcp') {
        reject(404);
        return;
      }
      if (request.method != 'POST') {
        reject(405);
        return;
      }
      if (request.headers.contentType?.mimeType != 'application/json') {
        reject(415);
        return;
      }
      final version = request.headers.value('mcp-protocol-version');
      if (version != null &&
          !['2025-03-26', '2025-06-18', '2025-11-25'].contains(version)) {
        reject(400);
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
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': null,
            'error': {'code': -32700, 'message': 'Parse error'},
          }),
        );
        return;
      }
      if (decoded is! Map ||
          decoded['jsonrpc'] != '2.0' ||
          decoded['method'] is! String) {
        reject(400);
        return;
      }
      final id = decoded['id'];
      final method = decoded['method'];
      if (id == null) {
        response.statusCode = 202;
        return;
      }
      dynamic result;
      Map<String, dynamic>? error;
      final params = Map<String, dynamic>.from(decoded['params'] as Map? ?? {});
      switch (method) {
        case 'initialize':
          final wanted = params['protocolVersion'];
          result = {
            'protocolVersion':
                ['2025-03-26', '2025-06-18', '2025-11-25'].contains(wanted)
                ? wanted
                : '2025-11-25',
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'zju-planner', 'version': '0.1.0'},
            'instructions':
                'Read schedule and propose drafts. User must confirm in Android app.',
          };
        case 'ping':
          result = <String, dynamic>{};
        case 'tools/list':
          result = {'tools': PlannerTools.definitions};
        case 'tools/call':
          try {
            final name = params['name'];
            final args = Map<String, dynamic>.from(
              params['arguments'] as Map? ?? {},
            );
            final value = switch (name) {
              'get_schedule_context' => tools.context(),
              'propose_schedule' => await tools.saveMcpDraft(args),
              _ => throw const FormatException('Unknown tool'),
            };
            result = {
              'content': [
                {'type': 'text', 'text': jsonEncode(value)},
              ],
              'isError': false,
            };
          } catch (_) {
            result = {
              'content': [
                {
                  'type': 'text',
                  'text':
                      'Invalid or conflicting plan. Read context and revise; nothing applied.',
                },
              ],
              'isError': true,
            };
          }
        default:
          error = {'code': -32601, 'message': 'Method not found'};
      }
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          if (error != null) 'error': error else 'result': result,
        }),
      );
    } catch (_) {
      if (!response.headers.chunkedTransferEncoding) response.statusCode = 400;
    } finally {
      await response.close();
    }
  }
}
