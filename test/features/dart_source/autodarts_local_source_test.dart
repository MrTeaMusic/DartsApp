import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/data/autodarts_local_source.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kleiner Fake-Board-Manager mit `/api/events` (WebSocket) und `/api/state`.
class FakeBoardManager {
  FakeBoardManager._(this.server, {required this.webSocket});

  static Future<FakeBoardManager> start({bool webSocket = true}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeBoardManager._(server, webSocket: webSocket);
    server.listen(fake._handle);
    return fake;
  }

  final HttpServer server;
  final bool webSocket;
  final sockets = <WebSocket>[];
  final requests = <String>[];
  Map<String, Object?> state = {'connected': true, 'running': true, 'status': 'Throw', 'numThrows': 0, 'throws': <Object>[]};

  int get port => server.port;

  Future<void> _handle(HttpRequest req) async {
    requests.add('${req.method} ${req.uri.path}');
    if (req.uri.path == '/api/events' && webSocket && WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      sockets.add(ws);
      ws.listen((_) {}, onDone: () => sockets.remove(ws));
      return;
    }
    if (req.uri.path == '/api/state') {
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

Map<String, Object?> withThrows(List<String> names) => {
      'connected': true,
      'running': true,
      'status': 'Throw',
      'numThrows': names.length,
      'throws': [
        for (final n in names)
          {
            'segment': {'name': n, 'number': Segment.tryParse(n)!.number, 'multiplier': Segment.tryParse(n)!.multiplier, 'bed': 'Single'},
            'coords': {'x': 0.1, 'y': 0.2},
          },
      ],
    };

Future<T> waitFor<T>(Stream<T> stream, bool Function(T) test) =>
    stream.firstWhere(test).timeout(const Duration(seconds: 5));

void main() {
  test('WebSocket: verbindet, meldet Würfe und loggt Rohdaten', () async {
    final board = await FakeBoardManager.start();
    final source = AutodartsLocalSource(host: '127.0.0.1', port: board.port, random: math.Random(1));
    final raw = <RawMessage>[];
    source.rawMessages.listen(raw.add);
    final connected = waitFor(source.statusChanges, (s) => s.phase == SourcePhase.connected);
    await source.start();
    await connected;
    // Warten, bis der Server den Socket kennt.
    while (board.sockets.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    final thrown = waitFor(source.events, (e) => e is DartThrown);
    board.push(withThrows([])); // Ausgangslage
    board.push(withThrows(['T20']));
    final event = await thrown as DartThrown;
    expect(event.dart.segment, Segment.triple(20));
    expect(event.dart.position?.x, 0.1);
    expect(raw.where((m) => m.channel == 'ws'), isNotEmpty);

    expect(await source.send(AutodartsCommand.reset), isTrue);
    expect(board.requests, contains('POST /api/reset'));

    await source.dispose();
    await board.close();
  });

  test('Verbindungsabbruch führt zu Wiederverbindung', () async {
    final board = await FakeBoardManager.start();
    final source = AutodartsLocalSource(host: '127.0.0.1', port: board.port, random: math.Random(1));
    final phases = <SourcePhase>[];
    source.statusChanges.listen((s) => phases.add(s.phase));
    final connected = waitFor(source.statusChanges, (s) => s.phase == SourcePhase.connected);
    await source.start();
    await connected;
    while (board.sockets.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    final reconnected = waitFor(
      source.statusChanges,
      (s) => s.phase == SourcePhase.connected && phases.contains(SourcePhase.reconnecting),
    );
    await board.dropClients();
    await reconnected;
    expect(phases, containsAllInOrder([SourcePhase.connected, SourcePhase.reconnecting, SourcePhase.connecting, SourcePhase.connected]));

    await source.dispose();
    await board.close();
  });

  test('ohne WebSocket: HTTP-Polling auf /api/state', () async {
    final board = await FakeBoardManager.start(webSocket: false);
    final source = AutodartsLocalSource(
      host: '127.0.0.1',
      port: board.port,
      pollInterval: const Duration(milliseconds: 20),
      random: math.Random(1),
    );
    final polling = waitFor(source.statusChanges, (s) => s.phase == SourcePhase.polling);
    await source.start();
    await polling;

    final thrown = waitFor(source.events, (e) => e is DartThrown);
    board.state = withThrows(['D16']);
    expect((await thrown as DartThrown).dart.segment, Segment.double(16));

    await source.dispose();
    await board.close();
  });

  test('nicht erreichbar: Status "reconnecting" mit nächstem Versuch', () async {
    // Freien Port finden und wieder schließen.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final source = AutodartsLocalSource(host: '127.0.0.1', port: port, random: math.Random(1));
    final retry = waitFor(source.statusChanges, (s) => s.phase == SourcePhase.reconnecting);
    await source.start();
    final status = await retry;
    expect(status.nextRetry, isNotNull);
    expect(status.message, contains('nicht erreichbar'));
    await source.stop();
    expect(source.status, SourceStatus.idle);
    await source.dispose();
  });

  test('Backoff wächst und ist gedeckelt', () {
    final source = AutodartsLocalSource(host: 'x', random: math.Random(1), maxBackoff: const Duration(seconds: 30));
    expect(source.backoffFor(0).inMilliseconds, inInclusiveRange(1000, 1200));
    expect(source.backoffFor(3).inMilliseconds, inInclusiveRange(8000, 9600));
    expect(source.backoffFor(20).inMilliseconds, inInclusiveRange(30000, 36000));
    expect(source.webSocketUri.toString(), 'ws://x:3180/api/events');
    expect(source.stateUri.toString(), 'http://x:3180/api/state');
  });
}
