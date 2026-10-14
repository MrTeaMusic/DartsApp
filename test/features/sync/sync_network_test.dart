import 'dart:convert';
import 'dart:io';

import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/sync/data/sync_client.dart';
import 'package:dartlab/features/sync/data/sync_server.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart' as darts;
import '../../helpers/sync_device.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Device hub;
  late Device phone;
  late SyncServer server;

  setUp(() async {
    hub = Device();
    phone = Device();
    server = SyncServer(hub.store, key: '123456');
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  });
  tearDown(() async {
    await server.dispose();
    await hub.db.close();
    await phone.db.close();
  });

  SyncClient client(Device d, {String key = '123456', int chunk = 200}) =>
      SyncClient(d.store, host: '127.0.0.1', port: server.port!, key: key, chunk: chunk);

  test('Abgleich über das Netzwerk in beide Richtungen', () async {
    await hub.play(await hub.me(), minute: 1);
    await phone.play(await phone.me(), minute: 2);
    await phone.play(await phone.me(), minute: 3);
    await phone.profiles.create('Lisa');

    final received = <Object>[];
    server.merged.listen(received.add);

    final r = await client(phone, chunk: 1).sync();
    expect(r.sent, 2);
    expect(r.received, 1);
    expect(r.remote.sessions, 2);
    expect(r.remote.players, 1);
    expect(r.local.sessions, 1);
    for (final d in [hub, phone]) {
      expect(await d.sessions(), hasLength(3));
      expect((await d.active()).map((p) => p.name), unorderedEquals(['Ich', 'Lisa']));
    }
    expect(received, isNotEmpty);

    // Zweiter Abgleich: nichts zu tun.
    final again = await client(phone).sync();
    expect(again.sent + again.received, 0);
    expect(again.local.changedAnything || again.remote.changedAnything, isFalse);
  });

  test('große Pakete (im Hintergrund umgewandelt) kommen vollständig an', () async {
    Future<void> big(Device d, int minute) async {
      final me = await d.me();
      final sid = await d.games.startSession(
          playerId: me, gameId: 'highscore_hunt', config: const {'visits': 1}, seed: minute, startedAt: DateTime(2026, 10, 1, 12, minute));
      await d.games.replaceThrows(sessionId: sid, playerId: me, gameId: 'highscore_hunt', darts: [
        for (var i = 0; i < 1200; i++) (dart: darts.d(['T20', 'S5', 'MISS', 'D16'][i % 4]), visitIndex: i ~/ 3, counted: true),
      ]);
      await d.games.endSession(sid, result: const GameResult(metrics: {'points': 65}, summary: []), finished: true);
    }

    await big(hub, 1);
    await big(phone, 2);
    final r = await SyncClient(phone.store, host: '127.0.0.1', port: server.port!, key: '123456').sync();
    expect(r.sent, 1);
    expect(r.received, 1);
    for (final dev in [hub, phone]) {
      expect(await dev.db.select(dev.db.throws).get(), hasLength(2400));
    }
  });

  test('zwei Clients sehen über den Hub die Daten des anderen', () async {
    final ipad = Device();
    addTearDown(ipad.db.close);
    await phone.play(await phone.me(), minute: 1);
    await ipad.play(await ipad.me(), minute: 2);
    await client(phone).sync();
    await client(ipad).sync();
    await client(phone).sync();
    expect(await phone.sessions(), hasLength(2));
    expect(await ipad.sessions(), hasLength(2));
    expect(await hub.sessions(), hasLength(2));
  });

  test('falscher Code wird abgelehnt und ändert nichts', () async {
    await phone.play(await phone.me(), minute: 1);
    await expectLater(
      client(phone, key: '654321').sync(),
      throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.wrongKey)),
    );
    expect(await hub.sessions(), isEmpty);
  });

  test('nicht erreichbar und fremder Dienst werden erkannt', () async {
    final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final freePort = free.port;
    await free.close();
    await expectLater(
      SyncClient(phone.store, host: '127.0.0.1', port: freePort, key: 'x').sync(),
      throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.unreachable)),
    );

    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    other.listen((req) => req.response
      ..write('<html></html>')
      ..close());
    addTearDown(() => other.close(force: true));
    await expectLater(
      SyncClient(phone.store, host: '127.0.0.1', port: other.port, key: 'x').sync(),
      throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.notDartLab)),
    );
  });

  test('Gruß ohne Code, Unsinn wird mit 400 beantwortet', () async {
    final http = HttpClient();
    addTearDown(http.close);
    final hello = await (await http.get('127.0.0.1', server.port!, '/hello')).close();
    final body = jsonDecode(await utf8.decodeStream(hello)) as Map;
    expect(body['app'], syncProtocol);
    expect(body['keyOk'], isFalse);

    final req = await http.post('127.0.0.1', server.port!, '/push');
    req.headers.set(syncKeyHeader, '123456');
    req.write('kein json');
    expect((await req.close()).statusCode, HttpStatus.badRequest);
  });

  test('zu große Anfragen werden abgelehnt', () async {
    final small = SyncServer(hub.store, key: 'k', maxBodyBytes: 100);
    await small.start(port: 0, address: InternetAddress.loopbackIPv4);
    addTearDown(small.dispose);
    final http = HttpClient();
    addTearDown(http.close);
    final req = await http.post('127.0.0.1', small.port!, '/push');
    req.headers.set(syncKeyHeader, 'k');
    req.write(jsonEncode({'sessions': List.filled(50, 'x' * 10)}));
    expect((await req.close()).statusCode, HttpStatus.requestEntityTooLarge);
  });
}
