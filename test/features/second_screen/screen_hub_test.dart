import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartlab/features/second_screen/data/screen_client.dart';
import 'package:dartlab/features/second_screen/data/screen_hub.dart';
import 'package:dartlab/features/second_screen/domain/screen_state.dart';
import 'package:dartlab/features/sync/data/sync_server.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sync_device.dart';

Future<void> until(bool Function() done, {Duration max = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(max);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Zeitüberschreitung');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

ScreenState training(String score) => ScreenState(
      kind: ScreenKind.training,
      title: 'X01',
      players: [ScreenPlayer(name: 'Ben', score: score, scoreLabel: 'Rest', active: true)],
    );

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Device hub;
  late SyncServer server;
  late ScreenHub screen;
  var current = ScreenState.idle;
  var snapshots = 0;

  setUp(() async {
    hub = Device();
    current = ScreenState.idle;
    snapshots = 0;
    screen = ScreenHub(
      snapshot: () {
        snapshots++;
        return current;
      },
      throttle: const Duration(milliseconds: 40),
      heartbeat: const Duration(milliseconds: 300),
    );
    server = SyncServer(hub.store, key: '123456', screen: screen);
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  });
  tearDown(() async {
    await server.dispose();
    await hub.db.close();
  });

  Future<ScreenLink> connect({String key = '123456'}) => connectScreen(host: '127.0.0.1', port: server.port!, key: key);

  test('Viewer bekommt sofort den Stand und danach jede Änderung', () async {
    final counts = <int>[];
    screen.viewerCount.listen(counts.add);
    final link = await connect();
    final received = <ScreenState>[];
    final sub = link.states.listen(received.add);
    await until(() => received.isNotEmpty);
    expect(received.single.isIdle, isTrue);
    expect(screen.viewers, 1);

    current = training('501');
    screen.markDirty();
    await until(() => received.length == 2);
    expect(received.last.kind, ScreenKind.training);
    expect(received.last.players.single.score, '501');

    // Viele Änderungen kurz hintereinander werden zu einer Nachricht.
    for (final s in ['441', '381', '321', '261']) {
      current = training(s);
      screen.markDirty();
    }
    await until(() => received.length >= 3);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(received, hasLength(3));
    expect(received.last.players.single.score, '261');

    // Unveränderter Stand wird nicht noch einmal geschickt (auch nicht durch
    // den Herzschlag).
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(received, hasLength(3));

    // Herzschlag fängt Änderungen ohne markDirty ab.
    current = training('201');
    await until(() => received.length == 4);

    await sub.cancel();
    await link.close();
    await until(() => screen.viewers == 0);
    expect(counts, [1, 0]);
  });

  test('ohne Viewer wird nichts gebaut', () async {
    for (var i = 0; i < 20; i++) {
      screen.markDirty();
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(snapshots, 0);
  });

  test('mehrere Viewer bekommen denselben Stand', () async {
    final a = await connect();
    final b = await connect();
    final ra = <ScreenState>[];
    final rb = <ScreenState>[];
    a.states.listen(ra.add);
    b.states.listen(rb.add);
    await until(() => ra.isNotEmpty && rb.isNotEmpty && screen.viewers == 2);
    current = training('170');
    screen.markDirty();
    await until(() => ra.length == 2 && rb.length == 2);
    expect(ra.last.players.single.score, rb.last.players.single.score);
    await a.close();
    await b.close();
  });

  test('falscher Code, alter Hub und nicht erreichbarer PC werden unterschieden', () async {
    await expectLater(
      connect(key: '000000'),
      throwsA(isA<ScreenConnectException>().having((e) => e.kind, 'kind', ScreenFailure.wrongKey)),
    );

    final old = SyncServer(hub.store, key: '123456');
    await old.start(port: 0, address: InternetAddress.loopbackIPv4);
    addTearDown(old.dispose);
    await expectLater(
      connectScreen(host: '127.0.0.1', port: old.port!, key: '123456'),
      throwsA(isA<ScreenConnectException>().having((e) => e.kind, 'kind', ScreenFailure.hubTooOld)),
    );

    final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = free.port;
    await free.close();
    await expectLater(
      connectScreen(host: '127.0.0.1', port: port, key: '123456'),
      throwsA(isA<ScreenConnectException>().having((e) => e.kind, 'kind', ScreenFailure.unreachable)),
    );
  });

  test('WebSocket ohne Code wird abgewiesen', () async {
    await expectLater(WebSocket.connect('ws://127.0.0.1:${server.port}/screen/ws'), throwsA(isA<WebSocketException>()));
    expect(screen.viewers, 0);
  });

  test('Viewer, die etwas schicken, fliegen raus (nur lesen)', () async {
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/screen/ws', headers: {syncKeyHeader: '123456'});
    final done = Completer<void>();
    ws.listen((_) {}, onDone: done.complete);
    await until(() => screen.viewers == 1);
    ws.add('{"type":"start"}');
    await done.future.timeout(const Duration(seconds: 3));
    await until(() => screen.viewers == 0);
  });

  test('Browser-Seite: Code abfragen, mit Code anzeigen, nur GET', () async {
    final http = HttpClient();
    addTearDown(http.close);
    Future<(int, String, HttpHeaders)> get(String path, {String method = 'GET'}) async {
      final req = await http.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      final res = await req.close();
      return (res.statusCode, await utf8.decodeStream(res), res.headers);
    }

    final (s1, login, _) = await get('/screen');
    expect(s1, HttpStatus.unauthorized);
    expect(login, contains('name="key"'));
    expect(login, isNot(contains('WebSocket')));

    final (s2, page, headers) = await get('/screen?key=123456');
    expect(s2, HttpStatus.ok);
    expect(page, contains('new WebSocket'));
    expect(page, isNot(contains('innerHTML')));
    expect(headers.value('content-security-policy'), contains("default-src 'none'"));

    final (s3, _, _) = await get('/screen?key=123456', method: 'POST');
    expect(s3, HttpStatus.methodNotAllowed);

    // Browser schicken den Code als Parameter, weil sie keine Header setzen
    // können.
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/screen/ws?key=123456');
    final first = await ws.first.timeout(const Duration(seconds: 3));
    expect(decodeScreenMessage(first)?.isIdle, isTrue);

    // Der Code als Parameter öffnet keine Sync-Endpunkte.
    final (s4, _, _) = await get('/pull?key=123456', method: 'POST');
    expect(s4, HttpStatus.unauthorized);
  });

  test('Hello meldet den zweiten Bildschirm', () async {
    final http = HttpClient();
    addTearDown(http.close);
    final req = await http.get('127.0.0.1', server.port!, '/hello');
    final res = await req.close();
    final body = jsonDecode(await utf8.decodeStream(res)) as Map;
    expect(body['screen'], 1);
    expect(body['keyOk'], isFalse);
  });
}
