import 'dart:math' as math;
import 'dart:ui' show VoidCallback;

import 'package:dartlab/core/lite.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/live_remote/data/live_packet.dart';
import 'package:dartlab/features/live_remote/data/live_pusher.dart';
import 'package:dartlab/features/live_remote/presentation/live_push_controller.dart';
import 'package:dartlab/features/second_screen/domain/screen_state.dart';
import 'package:dartlab/features/second_screen/presentation/screen_feed.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:dartlab/features/sync/domain/sync_role.dart';
import 'package:dartlab/features/sync/presentation/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_cloud.dart';
import '../../helpers/live_states.dart';

final secret = CloudSecret.generate(math.Random(31));
const url = 'dartlab-sync.ben.workers.dev';

/// Der Feed der Spiele, von Hand gesteuert.
class FakeFeed extends ScreenFeed {
  FakeFeed(super.ref);
  ScreenState current = ScreenState.idle;
  VoidCallback? onChange;
  int attaches = 0;
  int detaches = 0;

  @override
  bool get attached => onChange != null;

  @override
  void attach(VoidCallback onChange) {
    attaches++;
    this.onChange = onChange;
  }

  @override
  void detach() {
    detaches++;
    onChange = null;
  }

  @override
  ScreenState snapshot() => current;

  /// Ein Spiel meldet eine Änderung.
  void play(ScreenState s) {
    current = s;
    onChange?.call();
  }
}

Future<void> until(bool Function() done, {Duration max = const Duration(seconds: 5), String? what}) async {
  final end = DateTime.now().add(max);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Zeitüberschreitung${what == null ? '' : ': $what'}');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> pause([int ms = 300]) => Future<void>.delayed(Duration(milliseconds: ms));

typedef Rig = ({ProviderContainer c, FakeCloud cloud, FakeFeed feed, List<LivePushInfo> seen});

Future<Rig> rig({
  bool share = true,
  String role = 'cloud',
  String cloudUrl = url,
  String? cloudSecret,
  bool lite = false,
  FakeCloud? cloud,
}) async {
  cloud ??= FakeCloud();
  SharedPreferences.setMockInitialValues({
    'sync.role': role,
    'sync.cloudUrl': cloudUrl,
    'sync.cloudSecret': cloudSecret ?? secret.text,
    if (share) 'sync.liveShare': true,
  });
  final sp = await SharedPreferences.getInstance();
  late FakeFeed feed;
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sp),
    cloudHttpClientProvider.overrideWithValue(cloud.client),
    screenFeedProvider.overrideWith((ref) => feed = FakeFeed(ref)),
    if (lite) liteProvider.overrideWithValue(true),
  ]);
  addTearDown(c.dispose);
  final seen = <LivePushInfo>[];
  c.listen(livePushControllerProvider, (_, n) => seen.add(n), fireImmediately: true);
  // Der Feed entsteht erst beim ersten Lesen.
  c.read(screenFeedProvider);
  return (c: c, cloud: cloud, feed: feed, seen: seen);
}

Future<LivePacket> storedPacket(FakeCloud cloud) async {
  final keys = await secret.keys();
  return openLivePacket(keys, cloud.vault(keys.token).live!);
}

void main() {
  group('Schalter aus (Standard): keine Arbeit', () {
    test('Standard ist aus', () {
      expect(const AppSettings().liveShare, isFalse);
    });

    test('Cloud-Rolle ohne Schalter: kein Zuhören, kein Zeitgeber, keine Anfrage', () async {
      final r = await rig(share: false);
      await pause(500);
      expect(r.seen.map((i) => i.status), [LivePushStatus.off]);
      expect(r.feed.attaches, 0);
      expect(r.feed.attached, isFalse);
      expect(r.cloud.requests, isEmpty);
    });

    test('auch mit laufendem Spiel geht nichts raus', () async {
      final r = await rig(share: false);
      r.feed.play(liveMatch);
      await pause(500);
      expect(r.cloud.requests, isEmpty);
      expect(r.cloud.livePuts, 0);
    });

    for (final role in ['off', 'hub', 'client']) {
      test('Schalter an, aber Rolle "$role": nichts', () async {
        final r = await rig(role: role);
        await pause(300);
        expect(r.seen.last.status, LivePushStatus.off);
        expect(r.feed.attaches, 0);
        expect(r.cloud.requests, isEmpty);
      });
    }

    test('Lite schickt nie etwas, auch wenn die Einstellung irgendwie an wäre', () async {
      final r = await rig(lite: true);
      r.feed.play(liveMatch);
      await pause(300);
      expect(r.seen.last.status, LivePushStatus.off);
      expect(r.feed.attaches, 0);
      expect(r.cloud.requests, isEmpty);
    });

    test('Adresse oder Geheimnis fehlen: Hinweis, keine Anfrage', () async {
      var r = await rig(cloudUrl: '');
      await pause(200);
      expect(r.seen.last.status, LivePushStatus.notConfigured);
      expect(r.cloud.requests, isEmpty);
      expect(r.feed.attaches, 0);
      r = await rig(cloudSecret: 'ZU-KURZ');
      await pause(200);
      expect(r.seen.last.status, LivePushStatus.notConfigured);
      expect(r.cloud.requests, isEmpty);
    });
  });

  group('Schalter an', () {
    test('prüft den Speicher, hängt sich an die Spiele und sendet das Spiel verschlüsselt', () async {
      final r = await rig();
      await until(() => r.seen.last.status == LivePushStatus.waiting, what: 'bereit');
      expect(r.feed.attached, isTrue);
      expect(r.cloud.requests, ['GET /v1/hello']);
      expect(r.cloud.livePuts, 0, reason: 'ohne Spiel wird nichts gesendet');

      r.feed.play(liveMatch);
      await until(() => r.cloud.livePuts == 1, what: 'erstes Paket');
      expect((await storedPacket(r.cloud)).state.toJson(), liveMatch.toJson());
      await until(() => r.seen.last.status == LivePushStatus.ok);
      expect(r.seen.last.lastSent, isNotNull);

      // Der Server sieht nichts im Klartext.
      expect(r.cloud.dump(), isNot(contains('Ben')));

      // Spielende: idle.
      r.feed.play(ScreenState.idle);
      await until(() => r.cloud.livePuts == 2, what: 'idle');
      expect((await storedPacket(r.cloud)).state.isIdle, isTrue);
    });

    test('der Pusher benutzt den Stand der Feed-Funktion (dieselbe wie beim Hub)', () async {
      final r = await rig();
      await until(() => r.feed.attached);
      r.feed.play(liveSolo);
      await until(() => r.cloud.livePuts == 1);
      expect((await storedPacket(r.cloud)).state.toJson(), liveSolo.toJson());
    });

    test('Schalter aus während des Spiels: idle für die Zuschauer, Feed frei, danach Ruhe', () async {
      final r = await rig();
      await until(() => r.feed.attached);
      r.feed.play(liveMatch);
      await until(() => r.cloud.livePuts == 1);
      await r.c.read(settingsProvider.notifier).update((s) => s.copyWith(liveShare: false));
      await until(() => r.cloud.livePuts == 2, what: 'idle beim Ausschalten');
      expect((await storedPacket(r.cloud)).state.isIdle, isTrue);
      expect(r.feed.attached, isFalse);
      await until(() => r.seen.last.status == LivePushStatus.off, what: 'Status aus');
      final n = r.cloud.requests.length;
      r.feed.play(liveMatchNext);
      await pause(500);
      expect(r.cloud.requests.length, n);
    });

    test('Schalter aus ohne Spiel: nichts mehr gesendet', () async {
      final r = await rig();
      await until(() => r.feed.attached);
      await r.c.read(settingsProvider.notifier).update((s) => s.copyWith(liveShare: false));
      await pause(300);
      expect(r.cloud.livePuts, 0);
      expect(r.feed.attached, isFalse);
    });

    test('Rolle wechselt weg von Cloud: Schluss', () async {
      final r = await rig();
      await until(() => r.feed.attached);
      await r.c.read(settingsProvider.notifier).update((s) => s.copyWith(syncRole: SyncRole.off));
      await pause(200);
      expect(r.feed.attached, isFalse);
      expect(r.seen.last.status, LivePushStatus.off);
    });

    test('alter Worker: Hinweis, kein Absturz, nichts gesendet', () async {
      final r = await rig(cloud: FakeCloud()..liveSupported = false);
      await until(() => r.seen.last.status == LivePushStatus.workerTooOld);
      r.feed.play(liveMatch);
      await pause(400);
      expect(r.cloud.livePuts, 0);
      expect(r.cloud.requests, ['GET /v1/hello']);
      expect(r.seen.last.status, LivePushStatus.workerTooOld);
    });

    test('kein Netz: Fehlerstatus, das Spiel läuft unberührt, später klappt es', () async {
      final cloud = FakeCloud()..override = (req) => http.Response('Bad Gateway', 502);
      final r = await rig(cloud: cloud);
      await until(() => r.seen.last.status == LivePushStatus.server);
      r.feed.play(liveMatch);
      await pause(200);
      cloud.override = null;
      // Der nächste Versuch kommt nach 3 s (Backoff).
      await until(() => cloud.livePuts == 1, max: const Duration(seconds: 8), what: 'Wiederholung');
      expect((await storedPacket(cloud)).state.toJson(), liveMatch.toJson());
      await until(() => r.seen.last.status == LivePushStatus.ok);
    });

    test('neues Geheimnis: Pusher beginnt mit dem neuen Tresor', () async {
      final r = await rig();
      await until(() => r.feed.attached);
      r.feed.play(liveMatch);
      await until(() => r.cloud.livePuts == 1);
      final other = CloudSecret.generate(math.Random(32));
      await r.c.read(settingsProvider.notifier).update((s) => s.copyWith(syncCloudSecret: other.text));
      await until(() => r.cloud.livePuts >= 2, what: 'idle im alten Tresor');
      await until(() => r.feed.attached, what: 'neu angehängt');
      r.feed.play(liveMatchNext);
      await until(() => r.cloud.vault(r.cloud.vaults.keys.firstWhere((t) => t != r.cloud.vaults.keys.first)).live != null, what: 'neuer Tresor');
      expect(r.cloud.vaults.length, 2);
    });
  });
}
