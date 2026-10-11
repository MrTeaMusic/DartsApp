import 'dart:convert';
import 'dart:io';

/// Kleiner Fake-Board-Manager mit `/api/events` (WebSocket) und `/api/state`.
class FakeBoardManager {
  FakeBoardManager._(this.server, {required this.webSocket, this.silent = false});

  static Future<FakeBoardManager> start({bool webSocket = true, bool silent = false, int stateStatus = 200}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeBoardManager._(server, webSocket: webSocket, silent: silent)..stateStatus = stateStatus;
    server.listen(fake._handle);
    return fake;
  }

  final HttpServer server;
  final bool webSocket;

  /// WebSocket schickt nach dem Verbinden nichts von selbst.
  final bool silent;
  int stateStatus = 200;
  final sockets = <WebSocket>[];
  final requests = <String>[];
  Map<String, Object?> state = {'connected': true, 'running': true, 'status': 'Throw', 'numThrows': 0, 'throws': <Object>[]};

  int get port => server.port;

  /// Beim Verbinden sofort den Zustand schicken (für die Diagnose).
  bool greet = false;

  Future<void> _handle(HttpRequest req) async {
    requests.add('${req.method} ${req.uri.path}');
    if (req.uri.path == '/api/events' && webSocket && WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      sockets.add(ws);
      ws.listen((_) {}, onDone: () => sockets.remove(ws));
      if (!silent && greet) ws.add(jsonEncode({'type': 'state', 'data': state}));
      return;
    }
    if (req.uri.path == '/api/state') {
      req.response.statusCode = stateStatus;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(state));
    } else if (req.uri.path == '/api/reset' && req.method == 'POST') {
      req.response.statusCode = 200;
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  }

  void push(Map<String, Object?> s) {
    state = s;
    for (final ws in sockets) {
      ws.add(jsonEncode({'type': 'state', 'data': s}));
    }
  }

  Future<void> dropClients() async {
    for (final ws in [...sockets]) {
      await ws.close();
    }
  }

  Future<void> close() async {
    await dropClients();
    await server.close(force: true);
  }
}

