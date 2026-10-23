import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/autodarts_import/data/autodarts_import_repository.dart';
import 'package:dartlab/features/autodarts_import/data/autodarts_import_service.dart';
import 'package:dartlab/features/autodarts_import/data/autodarts_receiver.dart';
import 'package:dartlab/features/autodarts_import/domain/imported_match.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/autodarts_match_fixture.dart';

// Echter lokaler Server, echte Verbindungen; die Match-Daten sind synthetisch.

const _key = '482913';
const _origin = 'https://play.autodarts.com';

typedef Res = ({int status, Map<String, String> headers, String body});

Map<String, Object?>? asJson(Res r) {
  try {
    return jsonDecode(r.body) as Map<String, Object?>;
  } on FormatException {
    return null;
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late HttpClient client;
  setUp(() => client = HttpClient());
  tearDown(() => client.close(force: true));

  Future<Res> call(
    AutodartsReceiver r,
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
    String? key = _key,
    String? contentType = 'application/json',
    String? host,
  }) async {
    final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:${r.port}$path'));
    if (key != null) req.headers.set(importKeyHeader, key);
    if (contentType != null) req.headers.set('content-type', contentType);
    if (host != null) req.headers.host = host;
    headers.forEach(req.headers.set);
    if (body != null) req.add(body is List<int> ? body : utf8.encode(body is String ? body : jsonEncode(body)));
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    final h = <String, String>{};
    res.headers.forEach((name, values) => h[name.toLowerCase()] = values.join(','));
    return (status: res.statusCode, headers: h, body: text);
  }

  group('Protokoll (Handler als Attrappe)', () {
    late AutodartsReceiver r;
    final received = <Object?>[];
    final ids = <String?>[];

    Future<AutodartsReceiver> start({int maxBody = 2 * 1024 * 1024, int maxReq = 30, DateTime Function()? clock, ImportHandler? handler}) async {
      final rec = AutodartsReceiver(
        key: _key,
        maxBodyBytes: maxBody,
        maxRequests: maxReq,
        clock: clock,
        handler: handler ??
            (json, {id}) async {
              received.add(json);
              ids.add(id);
              return const ImportReply(ImportStatus.duplicate, id: 'm-1');
            },
      );
      await rec.start(port: 0);
      addTearDown(rec.stop);
      return rec;
    }

    setUp(() {
      received.clear();
      ids.clear();
    });

    test('bindet nur an 127.0.0.1', () async {
      r = await start();
      expect(r.running, isTrue);
      expect(r.port, isNonZero);
      // Über die Loopback-Adresse erreichbar, über „any“ gebunden wäre es auch von außen.
      final s = await Socket.connect(InternetAddress.loopbackIPv4, r.port!);
      await s.close();
    });

    test('ohne Code und mit falschem Code: 401, der Handler wird nie gerufen', () async {
      r = await start();
      expect((await call(r, 'POST', ImportPaths.autodarts, body: {'a': 1}, key: null)).status, 401);
      expect((await call(r, 'POST', ImportPaths.autodarts, body: {'a': 1}, key: '000000')).status, 401);
      expect((await call(r, 'POST', ImportPaths.autodarts, body: {'a': 1}, key: '4829130')).status, 401);
      expect(received, isEmpty);
    });

    test('richtiger Code: 200 mit ok, status und id', () async {
      r = await start();
      final res = await call(r, 'POST', '${ImportPaths.autodarts}?id=abc-1', body: {'a': 1});
      expect(res.status, 200);
      expect(asJson(res), containsPair('ok', true));
      expect(asJson(res), containsPair('status', 'duplicate'));
      expect(asJson(res), containsPair('id', 'm-1'));
      expect(received.single, {'a': 1});
      expect(ids.single, 'abc-1');
    });

    test('Match-Id aus der Adresse nur mit unbedenklichen Zeichen', () async {
      r = await start();
      await call(r, 'POST', '${ImportPaths.autodarts}?id=${Uri.encodeQueryComponent("../x y")}', body: {'a': 1});
      expect(ids.single, isNull);
    });

    test('Preflight einer erlaubten Seite: 204 mit Freigaben, auch für Private Network', () async {
      r = await start();
      final res = await call(r, 'OPTIONS', ImportPaths.autodarts, key: null, contentType: null, headers: {
        'Origin': _origin,
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'content-type,x-dartlab-key',
        'Access-Control-Request-Private-Network': 'true',
      });
      expect(res.status, 204);
      expect(res.headers['access-control-allow-origin'], _origin);
      expect(res.headers['access-control-allow-headers'], allOf(contains('Content-Type'), contains('X-DartLab-Key')));
      expect(res.headers['access-control-allow-methods'], contains('POST'));
      expect(res.headers['access-control-allow-private-network'], 'true');
      expect(res.headers['vary'], contains('Origin'));
      expect(received, isEmpty);
    });

    test('auch .io ist erlaubt', () async {
      r = await start();
      final res = await call(r, 'POST', ImportPaths.autodarts, body: {'a': 1}, headers: {'Origin': 'https://play.autodarts.io'});
      expect(res.status, 200);
      expect(res.headers['access-control-allow-origin'], 'https://play.autodarts.io');
    });

    test('fremder Origin: 403 ohne Freigabe-Header, Handler nie gerufen', () async {
      r = await start();
      for (final origin in ['https://evil.example', 'http://play.autodarts.com', 'https://play.autodarts.com.evil.example', 'null']) {
        final post = await call(r, 'POST', ImportPaths.autodarts, body: {'a': 1}, headers: {'Origin': origin});
        expect(post.status, 403, reason: origin);
        expect(post.headers.containsKey('access-control-allow-origin'), isFalse, reason: origin);
        final pre = await call(r, 'OPTIONS', ImportPaths.autodarts, key: null, contentType: null, headers: {'Origin': origin});
        expect(pre.status, 403, reason: origin);
        expect(pre.headers.containsKey('access-control-allow-origin'), isFalse, reason: origin);
      }
      expect(received, isEmpty);
    });

    test('fremder Host (DNS-Rebinding): 403', () async {
      r = await start();
      final res = await call(r, 'POST', ImportPaths.autodarts, body: {'a': 1}, host: 'evil.example');
      expect(res.status, 403);
      expect(received, isEmpty);
    });

    test('localhost als Host ist erlaubt', () async {
      r = await start();
      final res = await call(r, 'POST', ImportPaths.autodarts, body: {'a': 1}, host: 'localhost');
      expect(res.status, 200);
    });

    test('nur POST: GET, PUT, DELETE geben 405 mit Allow', () async {
      r = await start();
      for (final m in ['GET', 'PUT', 'DELETE', 'PATCH']) {
        final res = await call(r, m, ImportPaths.autodarts);
        expect(res.status, 405, reason: m);
        expect(res.headers['allow'], contains('POST'));
      }
      expect(received, isEmpty);
    });

    test('unbekannter Pfad: 404', () async {
      r = await start();
      expect((await call(r, 'POST', '/import/other', body: {})).status, 404);
      expect((await call(r, 'GET', '/')).status, 404);
    });

    test('Ping mit Code: 200; ohne Code: 401', () async {
      r = await start();
      final ok = await call(r, 'GET', ImportPaths.ping);
      expect(ok.status, 200);
      expect(asJson(ok), containsPair('ok', true));
      expect((await call(r, 'GET', ImportPaths.ping, key: null)).status, 401);
    });

    test('nur JSON: anderer Inhaltstyp gibt 415', () async {
      r = await start();
      final res = await call(r, 'POST', ImportPaths.autodarts, body: 'x=1', contentType: 'application/x-www-form-urlencoded');
      expect(res.status, 415);
      expect((await call(r, 'POST', ImportPaths.autodarts, body: '{"a":1}', contentType: null)).status, 415);
      expect(received, isEmpty);
    });

    test('text/plain wird wie JSON gelesen (kein Preflight im Browser nötig)', () async {
      r = await start();
      final res = await call(r, 'POST', ImportPaths.autodarts, body: '{"a":2}', contentType: 'text/plain');
      expect(res.status, 200);
      expect(received.single, {'a': 2});
    });

    test('kaputtes JSON: 400', () async {
      r = await start();
      final res = await call(r, 'POST', ImportPaths.autodarts, body: '{"a":');
      expect(res.status, 400);
      expect(received, isEmpty);
    });

    test('zu großer Körper: 413 (auch ohne Content-Length gemessen)', () async {
      r = await start(maxBody: 1000);
      final big = jsonEncode({'pad': 'x' * 2000});
      final res = await call(r, 'POST', ImportPaths.autodarts, body: big);
      expect(res.status, 413);
      expect(received, isEmpty);
      final fine = await call(r, 'POST', ImportPaths.autodarts, body: {'pad': 'x' * 100});
      expect(fine.status, 200);
    });

    test('Grenze 2 MB: knapp darunter geht, darüber nicht', () async {
      r = await start();
      final under = jsonEncode({'pad': 'x' * (2 * 1024 * 1024 - 100)});
      expect((await call(r, 'POST', ImportPaths.autodarts, body: under)).status, 200);
      final over = jsonEncode({'pad': 'x' * (2 * 1024 * 1024 + 10)});
      expect((await call(r, 'POST', ImportPaths.autodarts, body: over)).status, 413);
    });

    test('Rate-Limit: nach dem Kontingent 429 mit Retry-After, danach wieder frei', () async {
      var now = DateTime(2026, 10, 21, 12);
      r = await start(maxReq: 5, clock: () => now);
      for (var i = 0; i < 5; i++) {
        expect((await call(r, 'POST', ImportPaths.autodarts, body: {'i': i})).status, 200);
      }
      final blocked = await call(r, 'POST', ImportPaths.autodarts, body: {'i': 6});
      expect(blocked.status, 429);
      expect(blocked.headers['retry-after'], isNotNull);
      expect(received, hasLength(5));
      now = now.add(const Duration(seconds: 11));
      expect((await call(r, 'POST', ImportPaths.autodarts, body: {'i': 7})).status, 200);
    });

    test('Rate-Limit zählt auch falsche Codes (kein Durchprobieren)', () async {
      r = await start(maxReq: 4);
      for (var i = 0; i < 4; i++) {
        expect((await call(r, 'POST', ImportPaths.autodarts, body: {}, key: '11111$i')).status, 401);
      }
      expect((await call(r, 'POST', ImportPaths.autodarts, body: {}, key: _key)).status, 429);
    });

    test('unlesbares Match: 422 mit Text, Absturz im Handler: 500 ohne Einzelheiten', () async {
      r = await start(handler: (json, {id}) async => throw const AutodartsImportException(ImportProblem.format, 'Format unbekannt.'));
      final bad = await call(r, 'POST', ImportPaths.autodarts, body: {'a': 1});
      expect(bad.status, 422);
      expect(asJson(bad), containsPair('ok', false));
      expect(bad.body, contains('Format unbekannt'));

      final crash = await start(handler: (json, {id}) async => throw StateException('geheim: $_key'));
      final res = await call(crash, 'POST', ImportPaths.autodarts, body: {'a': 1});
      expect(res.status, 500);
      expect(res.body, isNot(contains('geheim')));
      expect(res.body, isNot(contains(_key)));
    });

    test('Antworten werden nicht zwischengespeichert', () async {
      r = await start();
      final res = await call(r, 'POST', ImportPaths.autodarts, body: {'a': 1});
      expect(res.headers['cache-control'], contains('no-store'));
    });

    test('Port belegt: SocketException, Port nach stop() wieder frei', () async {
      r = await start();
      final second = AutodartsReceiver(key: _key, handler: (j, {id}) async => const ImportReply(ImportStatus.ignored));
      await expectLater(second.start(port: r.port!), throwsA(isA<SocketException>()));
      expect(second.running, isFalse);
      final port = r.port!;
      await r.stop();
      expect(r.running, isFalse);
      final again = AutodartsReceiver(key: _key, handler: (j, {id}) async => const ImportReply(ImportStatus.ignored));
      await again.start(port: port);
      addTearDown(again.stop);
      expect(again.port, port);
    });

    test('nichts im Protokoll: weder Inhalt noch Code erscheinen in print/debugPrint', () async {
      final logged = <String>[];
      await runZoned(
        () async {
          r = await start();
          await call(r, 'POST', ImportPaths.autodarts, body: {'secret-name': 'Geheimer Spieler'}, key: '999999');
          await call(r, 'POST', ImportPaths.autodarts, body: {'secret-name': 'Geheimer Spieler'});
        },
        zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => logged.add(line)),
      );
      expect(logged, isEmpty);
    });
  });

  group('Ende zu Ende mit der echten Importlogik', () {
    late AppDatabase db;
    late AutodartsReceiver r;
    var name = '';

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final me = await ProfileRepository(db).resolve(null);
      name = 'Ben';
      final service = AutodartsImportService(
        repository: AutodartsImportRepository(db),
        playerId: () async => me,
        myName: () => name,
        rememberName: (n) async => name = n,
      );
      r = AutodartsReceiver(key: _key, handler: (json, {id}) => service.importJson(json, externalId: id, origin: 'browserScript'));
      await r.start(port: 0);
    });
    tearDown(() async {
      await r.stop();
      await db.close();
    });

    test('imported, dann duplicate, dann ignored (Cricket), dann pending (Name unbekannt)', () async {
      final first = await call(r, 'POST', ImportPaths.autodarts, body: syntheticMatch(), headers: {'Origin': _origin});
      expect(first.status, 200);
      expect(asJson(first), containsPair('status', 'imported'));
      expect(asJson(first), containsPair('id', 'synthetic-0001'));
      expect(asJson(first), containsPair('legs', '3:2'));
      expect(asJson(first), containsPair('opponent', 'Gegner'));

      final again = await call(r, 'POST', ImportPaths.autodarts, body: syntheticMatch());
      expect(asJson(again), containsPair('status', 'duplicate'));
      expect(await db.select(db.sessions).get(), hasLength(1));

      final cricket = await call(r, 'POST', ImportPaths.autodarts, body: syntheticMatch(variant: 'Cricket', id: 'cr-1'));
      expect(cricket.status, 200);
      expect(asJson(cricket), containsPair('status', 'ignored'));

      name = '';
      final unknown = await call(r, 'POST', ImportPaths.autodarts, body: syntheticMatch(id: 'p-1'));
      expect(asJson(unknown), containsPair('status', 'pending'));
      expect(await db.select(db.sessions).get(), hasLength(1));
    });

    test('Unsinn gibt 422, nichts wird gespeichert', () async {
      final res = await call(r, 'POST', ImportPaths.autodarts, body: {'hello': 'world'});
      expect(res.status, 422);
      expect(await db.select(db.sessions).get(), isEmpty);
    });
  });
}

class StateException implements Exception {
  StateException(this.message);
  final String message;
  @override
  String toString() => message;
}
