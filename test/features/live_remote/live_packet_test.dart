import 'dart:convert';
import 'dart:math' as math;

import 'package:dartlab/features/live_remote/data/live_packet.dart';
import 'package:dartlab/features/second_screen/domain/screen_state.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/live_states.dart';

void main() {
  final secret = CloudSecret.generate(math.Random(1));
  final other = CloudSecret.generate(math.Random(2));
  final sentAt = DateTime.fromMillisecondsSinceEpoch(1760000000000);

  test('Paket: verschlüsseln und wieder öffnen gibt denselben Stand', () async {
    final keys = await secret.keys();
    final body = await sealLivePacket(keys, LivePacket(state: liveMatch, sentAt: sentAt));
    final back = await openLivePacket(keys, body);
    expect(back.sentAt, sentAt);
    expect(back.state.toJson(), liveMatch.toJson());
    expect(back.state.players.first.name, 'Ben');
    expect(back.state.kind, ScreenKind.match);
  });

  test('Paket im Klartext: Version, Zeit und der Stand des zweiten Bildschirms', () {
    final json = LivePacket(state: liveSolo, sentAt: sentAt).toJson();
    expect(json['v'], 1);
    expect(json['t'], 1760000000000);
    expect(json['state'], liveSolo.toJson());
    expect((json['state'] as Map)['v'], screenStateVersion);
  });

  test('falsches Geheimnis: Fehler beim Öffnen, kein halber Stand', () async {
    final body = await sealLivePacket(await secret.keys(), LivePacket(state: liveMatch, sentAt: sentAt));
    await expectLater(openLivePacket(await other.keys(), body), throwsA(isA<CloudDecryptException>()));
  });

  test('der Name "live" ist an die Verschlüsselung gebunden', () async {
    final keys = await secret.keys();
    // Ein Meta- oder Session-Block lässt sich nicht als Live-Paket unterschieben, und umgekehrt.
    final asMeta = await keys.seal(LivePacket(state: liveMatch, sentAt: sentAt).toJson(), 'meta');
    await expectLater(openLivePacket(keys, asMeta), throwsA(isA<CloudDecryptException>()));
    final live = await sealLivePacket(keys, LivePacket(state: liveMatch, sentAt: sentAt));
    await expectLater(keys.open(live, 'meta'), throwsA(isA<CloudDecryptException>()));
    await expectLater(keys.open(live, 's:abc'), throwsA(isA<CloudDecryptException>()));
  });

  test('verändertes oder abgeschnittenes Paket wird abgelehnt', () async {
    final keys = await secret.keys();
    final body = await sealLivePacket(keys, LivePacket(state: liveMatch, sentAt: sentAt));
    final bytes = base64.decode(body);
    bytes[bytes.length ~/ 2] ^= 1;
    await expectLater(openLivePacket(keys, base64.encode(bytes)), throwsA(isA<CloudDecryptException>()));
    await expectLater(openLivePacket(keys, body.substring(0, 20)), throwsA(isA<CloudDecryptException>()));
    await expectLater(openLivePacket(keys, 'kein base64!'), throwsA(isA<CloudDecryptException>()));
  });

  test('im Paket steht kein Klartext, und jedes Paket sieht anders aus', () async {
    final keys = await secret.keys();
    final a = await sealLivePacket(keys, LivePacket(state: liveMatch, sentAt: sentAt));
    final b = await sealLivePacket(keys, LivePacket(state: liveMatch, sentAt: sentAt));
    expect(a, isNot(b), reason: 'neue Nonce je Paket');
    final raw = utf8.decode(base64.decode(a), allowMalformed: true);
    for (final word in ['Ben', 'CPU', 'match', 'T19', 'Leg']) {
      expect(raw, isNot(contains(word)), reason: word);
    }
    expect(a, isNot(contains('Ben')));
  });

  test('Pakete bleiben klein: weit unter der Grenze von 16 KB', () async {
    final keys = await secret.keys();
    for (final s in [liveMatch, liveMatchNext, liveSolo, liveTraining, ScreenState.idle]) {
      final body = await sealLivePacket(keys, LivePacket(state: s, sentAt: sentAt));
      expect(body.length, lessThan(2500), reason: s.title);
    }
    // Auch ein übergroßer Stand (viele Treffer und Kennzahlen) bleibt darunter.
    final rng = math.Random(3);
    final big = ScreenState(
      kind: ScreenKind.live,
      title: 'Autodarts Live',
      hits: [for (var i = 0; i < 60; i++) ScreenHit('T${i % 20 + 1}', x: rng.nextDouble(), y: rng.nextDouble())],
      stats: [for (var i = 0; i < 30; i++) ScreenStat('Kennzahl $i', '${rng.nextInt(1000)}')],
    );
    expect((await sealLivePacket(keys, LivePacket(state: big, sentAt: sentAt))).length, lessThan(16384));
  });

  test('Paket mit fehlenden oder fremden Feldern wird gelesen, nicht abgelehnt', () {
    final p = LivePacket.fromJson({'v': 9, 'state': {'kind': 'zukunft', 'neu': 1}, 'extra': true});
    expect(p.state.kind, ScreenKind.idle);
    expect(p.sentAt, DateTime.fromMillisecondsSinceEpoch(0));
    final q = LivePacket.fromJson(const {});
    expect(q.state.isIdle, isTrue);
  });
}
