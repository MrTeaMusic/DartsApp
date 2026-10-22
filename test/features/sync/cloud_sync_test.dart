import 'dart:convert';

import 'package:dartlab/features/autodarts_live/domain/live_stats.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/sync/data/cloud_api.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:dartlab/features/sync/data/cloud_remote.dart';
import 'package:dartlab/features/sync/data/sync_client.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/darts.dart' as darts;
import '../../helpers/fake_cloud.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('Geheimnis und Verschlüsselung', () {
    test('Text, Eingabe und Schlüssel sind stabil', () async {
      final s = CloudSecret.generate();
      expect(s.text, hasLength(CloudSecret.textLength));
      expect(s.display, matches(RegExp(r'^([0-9A-Z]{4}-){6}[0-9A-Z]{2}$')));
      // Eintippen: klein, mit Leerzeichen, verwechselbare Zeichen.
      final typed = s.display.toLowerCase().replaceAll('-', ' ').replaceAll('0', 'o').replaceAll('1', 'l');
      expect(CloudSecret.tryParse(typed)?.text, s.text);
      expect(CloudSecret.tryParse('zu kurz'), isNull);
      expect(CloudSecret.tryParse('U' * 26), isNull, reason: 'U gibt es im Alphabet nicht');

      final a = await s.keys();
      final b = await CloudSecret.tryParse(s.display)!.keys();
      expect(a.token, b.token);
      expect(a.token, hasLength(64));
      expect((await CloudSecret.generate().keys()).token, isNot(a.token));
    });

    test('verschlüsseln, öffnen, falscher Schlüssel und vertauschter Name', () async {
      final k = await CloudSecret.generate().keys();
      final other = await CloudSecret.generate().keys();
      final sealed = await k.seal({'name': 'Ben', 'n': 3}, 'meta');
      expect(sealed, isNot(contains('Ben')));
      expect(await k.open(sealed, 'meta'), {'name': 'Ben', 'n': 3});
      expect(await k.seal({'a': 1}, 'meta'), isNot(await k.seal({'a': 1}, 'meta')), reason: 'frische Nonce');
      await expectLater(other.open(sealed, 'meta'), throwsA(isA<CloudDecryptException>()));
      await expectLater(k.open(sealed, 's:abc'), throwsA(isA<CloudDecryptException>()));
      await expectLater(k.open('kein base64!', 'meta'), throwsA(isA<CloudDecryptException>()));
    });

    test('Adressen', () {
      expect(CloudApi.tryParseUrl('dartlab-sync.ben.workers.dev')?.toString(), 'https://dartlab-sync.ben.workers.dev');
      expect(CloudApi.tryParseUrl('https://x.example/')?.host, 'x.example');
      expect(CloudApi.tryParseUrl('http://127.0.0.1:8787')?.port, 8787);
      expect(CloudApi.tryParseUrl('http://example.com'), isNull, reason: 'unverschlüsselt nur lokal');
      expect(CloudApi.tryParseUrl(''), isNull);
      expect(CloudApi.tryParseUrl('zwei wörter'), isNull);
    });
  });

  group('Abgleich über die Cloud', () {
    late FakeCloud cloud;
    late CloudSecret secret;
    late CloudDevice phone;
    late CloudDevice ipad;

    setUp(() {
      cloud = FakeCloud();
      secret = CloudSecret.generate();
      phone = CloudDevice(cloud, secret);
      ipad = CloudDevice(cloud, secret);
    });
    tearDown(() async {
      await phone.device.db.close();
      await ipad.device.db.close();
    });

    test('zwei Geräte sehen die Daten des anderen, nichts liegt im Klartext', () async {
      await phone.device.play(await phone.device.me(), minute: 1);
      await phone.device.play(await phone.device.me(), minute: 2);
      await phone.device.profiles.create('Lisa');
      await ipad.device.play(await ipad.device.me(), minute: 3);

      final first = await phone.sync();
      expect(first.sent, 2);
      expect(first.received, 0);
      final second = await ipad.sync();
      expect(second.sent, 1);
      expect(second.received, 2);
      await phone.sync();

      for (final d in [phone.device, ipad.device]) {
        expect(await d.sessions(), hasLength(3));
        expect((await d.active()).map((p) => p.name), unorderedEquals(['Ich', 'Lisa']));
        expect(await d.db.select(d.db.throws).get(), hasLength(9));
      }
      expect(cloud.dump(), isNot(contains('Lisa')));
      expect(cloud.dump(), isNot(contains('highscore')));
    });

    test('ohne Änderungen wird nichts mehr geschrieben', () async {
      await phone.device.play(await phone.device.me(), minute: 1);
      // Erst ein paar Runden, bis beide Geräte denselben Stand haben (die
      // Profile "Ich" wurden auf jedem Gerät zu einer anderen Sekunde angelegt).
      for (final d in [phone, ipad, phone, ipad]) {
        await d.sync();
      }
      final puts = (cloud.metaPuts, cloud.sessionPuts);
      for (final d in [phone, ipad, phone]) {
        final again = await d.sync();
        expect(again.sent + again.received, 0);
      }
      expect((cloud.metaPuts, cloud.sessionPuts), puts);
    });

    test('Löschen kommt an und der Block verschwindet aus der Cloud', () async {
      final uid = await phone.device.play(await phone.device.me(), minute: 1);
      await phone.sync();
      await ipad.sync();
      expect(await ipad.device.sessions(), hasLength(1));

      final row = (await phone.device.sessions()).single;
      await phone.device.games.deleteSession(row.id);
      await phone.sync();
      expect(cloud.deleted, [uid]);
      await ipad.sync();
      final alive = await ipad.device.sessions();
      expect(alive.single.deletedAt, isNotNull);
      expect(await ipad.device.db.select(ipad.device.db.throws).get(), isEmpty);
    });

    test('ein Gerät, das zwischendurch schreibt: der Abgleich läuft noch einmal', () async {
      await phone.device.play(await phone.device.me(), minute: 1);
      await ipad.device.play(await ipad.device.me(), minute: 2);
      final token = (await secret.keys()).token;
      await phone.sync(); // Tresor anlegen

      var raced = false;
      cloud.beforeMetaPut = (t) async {
        if (raced) return;
        raced = true;
        // Das iPad schreibt genau jetzt (Meta-Version steigt).
        cloud.beforeMetaPut = null;
        await ipad.sync();
      };
      await phone.device.play(await phone.device.me(), minute: 4);
      final r = await phone.sync();
      expect(raced, isTrue);
      expect(r.received, greaterThanOrEqualTo(1), reason: 'zweiter Durchlauf holt das Neue vom iPad');
      await ipad.sync();
      for (final d in [phone.device, ipad.device]) {
        expect(await d.sessions(), hasLength(3));
      }
      expect(cloud.vault(token).rev, greaterThan(1));
    });

    test('falsches Geheimnis, fremder Dienst, kein Netz', () async {
      await phone.device.play(await phone.device.me(), minute: 1);
      await phone.sync();
      // Gleiche Adresse, anderes Geheimnis: ein eigener (leerer) Tresor, nichts sichtbar.
      final stranger = CloudDevice(cloud, CloudSecret.generate());
      addTearDown(stranger.device.db.close);
      await stranger.sync();
      expect(await stranger.device.sessions(), isEmpty);

      // Dieselbe Meta unter dem richtigen Token, aber mit einem anderen Schlüssel verschlüsselt.
      final token = (await secret.keys()).token;
      final strangerToken = (await stranger.secret.keys()).token;
      cloud.vault(strangerToken).meta = cloud.vault(token).meta;
      cloud.vault(strangerToken).rev = cloud.vault(token).rev;
      await expectLater(
        stranger.sync(),
        throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.wrongSecret)),
      );

      cloud.override = (_) => http.Response('<html>nope</html>', 200);
      await expectLater(phone.sync(), throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.notDartLab)));
      cloud.override = (_) => throw http.ClientException('offline');
      await expectLater(phone.sync(), throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.unreachable)));
      cloud.override = (_) => http.Response('{"error":"quota"}', 500, headers: {'x-dartlab-cloud': '1'});
      await expectLater(
        phone.sync(),
        throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.server).having((e) => e.detail, 'detail', 'quota')),
      );
    });

    test('ein vertauschter Block fällt auf', () async {
      final a = await phone.device.play(await phone.device.me(), minute: 1);
      final b = await phone.device.play(await phone.device.me(), minute: 2);
      await phone.sync();
      final v = cloud.vault((await secret.keys()).token);
      final tmp = v.sessions[a]!;
      v.sessions[a] = v.sessions[b]!;
      v.sessions[b] = tmp;
      await expectLater(ipad.sync(), throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.wrongSecret)));
    });

    test('Tresor vorhanden? (für das Verbinden eines weiteren Geräts)', () async {
      final keys = await secret.keys();
      CloudRemote remote() => CloudRemote(CloudApi('https://x.example', keys.token, client: cloud.client()), keys);
      expect(await remote().vaultExists(), isFalse);
      await phone.sync();
      expect(await remote().vaultExists(), isTrue);
    });

    test('Autodarts-Live-Sessions, die weiterwachsen, werden ersetzt', () async {
      final d = phone.device;
      final me = await d.me();
      final sid = await d.games.startSession(
        playerId: me,
        gameId: autodartsLiveGameId,
        config: const {'mode': 'listen'},
        seed: 0,
        startedAt: DateTime(2026, 10, 1, 12),
      );
      Future<void> grow(int from, int to) async {
        for (var i = from; i < to; i++) {
          await d.games.addThrow(
            sessionId: sid,
            playerId: me,
            gameId: autodartsLiveGameId,
            seq: i,
            visitIndex: i ~/ 3,
            counted: true,
            dart: darts.d(['T20', 'S5', 'MISS', 'D16'][i % 4]),
          );
        }
        await d.games.endSession(sid, result: GameResult(metrics: {'darts': to.toDouble()}, summary: const []), finished: true);
      }

      await grow(0, 3);
      await phone.sync();
      await ipad.sync();
      expect(await ipad.device.db.select(ipad.device.db.throws).get(), hasLength(3));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await grow(3, 6);
      await phone.sync();
      await ipad.sync();
      expect(await ipad.device.db.select(ipad.device.db.throws).get(), hasLength(6));
    });
  });

  test('Anfragen tragen nur das Token, nie das Geheimnis', () async {
    final secret = CloudSecret.generate();
    final cloud = FakeCloud();
    final seen = <http.Request>[];
    cloud.override = (r) {
      seen.add(r);
      return null;
    };
    final dev = CloudDevice(cloud, secret);
    addTearDown(dev.device.db.close);
    await dev.device.play(await dev.device.me(), minute: 1);
    await dev.sync();
    expect(seen, isNotEmpty);
    for (final r in seen) {
      expect(jsonEncode([r.url.toString(), r.headers, r.body]), isNot(contains(secret.text)));
    }
  });
}
