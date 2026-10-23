import 'dart:math' as math;

import 'package:dartlab/features/live_remote/data/live_packet.dart';
import 'package:dartlab/features/live_remote/data/live_sink.dart';
import 'package:dartlab/features/second_screen/domain/screen_state.dart';
import 'package:dartlab/features/sync/data/cloud_api.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:dartlab/features/sync/data/sync_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/fake_cloud.dart';
import '../../helpers/live_states.dart';

const url = 'https://dartlab-sync.ben.workers.dev';
final secret = CloudSecret.generate(math.Random(21));

Future<CloudApi> api(FakeCloud cloud, [CloudSecret? s]) async => CloudApi(url, (await (s ?? secret).keys()).token, client: cloud.client());

void main() {
  group('hello', () {
    test('neuer Worker meldet live, alter nicht', () async {
      final cloud = FakeCloud();
      expect((await (await api(cloud)).hello()).hasLive, isTrue);
      cloud.liveSupported = false;
      final old = await (await api(cloud)).hello();
      expect(old.hasLive, isFalse);
      expect(old.live, 0);
    });

    test('hello prüft weiter, ob es ein DartLab-Speicher ist', () async {
      final cloud = FakeCloud()..override = (_) => http.Response('{"app":"anderes"}', 200, headers: {'x-dartlab-cloud': '1'});
      await expectLater(
        (await api(cloud)).hello(),
        throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.notDartLab)),
      );
    });
  });

  group('putLive und getLive', () {
    test('ohne Tresor: noVault; Tresor ohne Paket: null; dann das Paket', () async {
      final cloud = FakeCloud();
      final a = await api(cloud);
      await expectLater(a.getLive(), throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.noVault)));
      cloud.vault((await secret.keys()).token).meta = 'x';
      expect(await a.getLive(), isNull);
      await a.putLive('AAAA');
      var r = await a.getLive();
      expect(r!.rev, 1);
      expect(r.body, 'AAAA');
      expect(r.notModified, isFalse);
      await a.putLive('BBBB');
      r = await a.getLive();
      expect((r!.rev, r.body), (2, 'BBBB'));
    });

    test('bedingte Abfrage: gleiche Version gibt 304 ohne Inhalt, mit Alter', () async {
      final cloud = FakeCloud()..liveAge = const Duration(seconds: 12);
      final a = await api(cloud);
      await a.putLive('AAAA');
      final full = await a.getLive();
      expect(full!.age, const Duration(seconds: 12));
      final same = await a.getLive(since: full.rev);
      expect(same!.notModified, isTrue);
      expect(same.rev, full.rev);
      expect(same.body, isNull);
      expect(same.age, const Duration(seconds: 12));
      expect(cloud.liveNotModified, 1);
      // Älterer Stand angegeben: voller Inhalt.
      await a.putLive('BBBB');
      final next = await a.getLive(since: full.rev);
      expect(next!.notModified, isFalse);
      expect(next.body, 'BBBB');
    });

    test('die Anfrage trägt nur ?since=<Zahl>, kein Anhängsel ohne Abfrage', () async {
      final cloud = FakeCloud();
      final a = await api(cloud);
      await a.hello();
      await a.putLive('AAAA');
      await a.getLive();
      await a.getLive(since: 1);
      expect(cloud.requests, ['GET /v1/hello', 'PUT /v1/live', 'GET /v1/live', 'GET /v1/live?since=1']);
    });

    test('alter Worker: 404 not-found wird zu CloudTooOldException', () async {
      final cloud = FakeCloud()..liveSupported = false;
      final a = await api(cloud);
      await expectLater(a.getLive(), throwsA(isA<CloudTooOldException>()));
      await expectLater(a.putLive('AAAA'), throwsA(isA<CloudTooOldException>()));
    });

    test('Zu großes Paket oder Serverfehler: SyncException, nichts anderes', () async {
      final cloud = FakeCloud();
      final a = await api(cloud);
      await expectLater(a.putLive('A' * 20000), throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.server)));
      cloud.override = (_) => http.Response('', 429);
      await expectLater(a.putLive('AAAA'), throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.server)));
      cloud.override = (_) => http.Response('{"error":"unauthorized"}', 401, headers: {'x-dartlab-cloud': '1'});
      await expectLater(a.getLive(), throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.wrongKey)));
    });
  });

  group('CloudLiveSink', () {
    test('verschlüsselt den Stand mit dem Namen "live" und schickt ihn', () async {
      final cloud = FakeCloud();
      final sink = (await CloudLiveSink.create(url, secret.display, client: cloud.client()))!;
      await sink.check();
      await sink.send(liveMatch);
      final stored = cloud.vault((await secret.keys()).token).live!;
      final packet = await openLivePacket(await secret.keys(), stored);
      expect(packet.state.toJson(), liveMatch.toJson());
      expect(cloud.dump(), isNot(contains('Ben')));
      expect(cloud.dump(), isNot(contains('CPU')));
      sink.close();
    });

    test('alter Worker: check() wirft CloudTooOldException', () async {
      final cloud = FakeCloud()..liveSupported = false;
      final sink = (await CloudLiveSink.create(url, secret.text, client: cloud.client()))!;
      await expectLater(sink.check(), throwsA(isA<CloudTooOldException>()));
    });

    test('ohne brauchbare Adresse oder Geheimnis gibt es kein Ziel', () async {
      expect(await CloudLiveSink.create('', secret.text), isNull);
      expect(await CloudLiveSink.create(url, 'zu kurz'), isNull);
      expect(await CloudLiveSink.create('mit leerzeichen', secret.text), isNull);
    });

    test('zwei Pakete: das zweite ersetzt das erste', () async {
      final cloud = FakeCloud();
      final sink = (await CloudLiveSink.create(url, secret.text, client: cloud.client()))!;
      await sink.send(liveMatch);
      await sink.send(liveMatchNext);
      expect(cloud.vault((await secret.keys()).token).liveRev, 2);
      final packet = await openLivePacket(await secret.keys(), cloud.vault((await secret.keys()).token).live!);
      expect(packet.state.hitSerial, 41);
      sink.close();
    });

    test('ein Live-Paket stört den Abgleich nicht: Meta und Sessions bleiben', () async {
      final cloud = FakeCloud();
      final sink = (await CloudLiveSink.create(url, secret.text, client: cloud.client()))!;
      await sink.send(liveMatch);
      final v = cloud.vault((await secret.keys()).token);
      expect(v.meta, isNull);
      expect(v.sessions, isEmpty);
      expect(v.rev, 0);
      // idle ist ein ganz normales Paket.
      await sink.send(ScreenState.idle);
      final back = await openLivePacket(await secret.keys(), v.live!);
      expect(back.state.isIdle, isTrue);
    });
  });
}
