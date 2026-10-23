import 'dart:math' as math;

import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/live_remote/data/live_sink.dart';
import 'package:dartlab/features/live_remote/presentation/live_viewer_controller.dart';
import 'package:dartlab/features/second_screen/domain/screen_state.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:dartlab/features/sync/presentation/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_cloud.dart';
import '../../helpers/live_states.dart';

final secret = CloudSecret.generate(math.Random(11));
const url = 'https://dartlab-sync.ben.workers.dev';

Future<void> until(bool Function() done, {Duration max = const Duration(seconds: 5), String? what}) async {
  final end = DateTime.now().add(max);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Zeitüberschreitung${what == null ? '' : ': $what'}');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> pause([int ms = 150]) => Future<void>.delayed(Duration(milliseconds: ms));

/// Legt Bens Tresor an und schickt ein Live-Paket, wie Bens App es täte.
Future<void> bensPacket(FakeCloud cloud, ScreenState state, {CloudSecret? as}) async {
  final sink = (await CloudLiveSink.create(url, (as ?? secret).text, client: cloud.client()))!;
  await sink.send(state);
  sink.close();
}

/// Ein Tresor mit Meta (so wie nach Bens erstem Abgleich).
void bensVault(FakeCloud cloud, [CloudSecret? s]) async {
  final keys = await (s ?? secret).keys();
  cloud.vault(keys.token).meta = 'meta';
}

Future<ProviderContainer> viewer(FakeCloud cloud, {CloudSecret? useSecret}) async {
  SharedPreferences.setMockInitialValues({
    'sync.role': 'cloud',
    'sync.cloudUrl': url,
    'sync.cloudSecret': (useSecret ?? secret).text,
  });
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sp),
    cloudHttpClientProvider.overrideWithValue(cloud.client),
  ]);
  addTearDown(c.dispose);
  return c;
}

class Seen {
  Seen(ProviderContainer c) {
    sub = c.listen(liveViewerProvider, (_, next) => states.add(next), fireImmediately: true);
  }
  late final ProviderSubscription<LiveViewState> sub;
  final states = <LiveViewState>[];
  LiveViewStatus get status => states.last.status;
  List<LiveViewStatus> get statuses => [for (final s in states) s.status];
}

void main() {
  setUp(() {
    // Kurze Takte, damit die Tests mit echter Zeit schnell sind.
    LiveViewerController.pollPlaying = const Duration(milliseconds: 25);
    LiveViewerController.pollIdle = const Duration(milliseconds: 60);
    LiveViewerController.pollIdleSlow = const Duration(milliseconds: 200);
    LiveViewerController.idleSlowAfter = const Duration(hours: 1);
    LiveViewerController.lostBackoff = const [Duration(milliseconds: 30), Duration(milliseconds: 60), Duration(milliseconds: 90)];
    LiveViewerController.workerRecheck = const Duration(milliseconds: 100);
    LiveViewerController.wrongSecretRetry = const Duration(milliseconds: 100);
  });
  tearDown(() {
    LiveViewerController.pollPlaying = const Duration(seconds: 2);
    LiveViewerController.pollIdle = const Duration(seconds: 5);
    LiveViewerController.pollIdleSlow = const Duration(seconds: 15);
    LiveViewerController.idleSlowAfter = const Duration(minutes: 10);
    LiveViewerController.lostBackoff = const [Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8), Duration(seconds: 10)];
    LiveViewerController.workerRecheck = const Duration(seconds: 60);
    LiveViewerController.wrongSecretRetry = const Duration(seconds: 30);
  });

  test('ohne aktive Ansicht fragt nichts ab', () async {
    final cloud = FakeCloud();
    final c = await viewer(cloud);
    final seen = Seen(c);
    await pause(300);
    expect(cloud.requests, isEmpty);
    expect(seen.status, LiveViewStatus.connecting);
  });

  test('aktiv: erst hello, dann Abfrage ohne Version; kein Paket heißt "spielt nicht"', () async {
    final cloud = FakeCloud();
    bensVault(cloud);
    await pause(20);
    final c = await viewer(cloud);
    final seen = Seen(c);
    c.read(liveViewerProvider.notifier).setActive(true);
    await until(() => seen.status == LiveViewStatus.notPlaying);
    expect(cloud.requests.take(2), ['GET /v1/hello', 'GET /v1/live']);
    expect(seen.states.last.screen, isNull);
    c.read(liveViewerProvider.notifier).setActive(false);
  });

  test('Ben spielt: Stand kommt an, weitere Abfragen sind bedingt (304)', () async {
    final cloud = FakeCloud();
    await bensPacket(cloud, liveMatch);
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.playing);
    expect(seen.states.last.screen!.toJson(), liveMatch.toJson());
    await until(() => cloud.liveNotModified >= 3, what: 'bedingte Abfragen');
    expect(cloud.requests.where((r) => r == 'GET /v1/hello'), hasLength(1), reason: 'hello nur einmal');
    expect(cloud.requests.where((r) => r == 'GET /v1/live?since=1'), isNotEmpty);
    expect(seen.status, LiveViewStatus.playing);

    // Neues Paket: die Ansicht folgt, danach wieder 304 mit der neuen Version.
    await bensPacket(cloud, liveMatchNext);
    await until(() => seen.states.last.screen?.hitSerial == 41, what: 'neuer Stand');
    final before = cloud.liveNotModified;
    await until(() => cloud.liveNotModified > before);
    expect(cloud.requests.where((r) => r == 'GET /v1/live?since=2'), isNotEmpty);
    n.setActive(false);
  });

  test('idle-Paket und veraltetes Paket: Ben spielt nicht', () async {
    final cloud = FakeCloud();
    await bensPacket(cloud, liveMatch);
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.playing);

    // Das Paket wird zu alt (kein Herzschlag mehr): Auch die bedingte Antwort 304 kennt das Alter.
    cloud.liveAge = const Duration(seconds: 61);
    await until(() => seen.status == LiveViewStatus.notPlaying, what: 'veraltet');
    expect(seen.states.last.screen, isNull);
    // Ein frischer Herzschlag macht es wieder lebendig.
    cloud.liveAge = const Duration(seconds: 3);
    await bensPacket(cloud, liveMatch);
    await until(() => seen.status == LiveViewStatus.playing);

    await bensPacket(cloud, ScreenState.idle);
    await until(() => seen.status == LiveViewStatus.notPlaying, what: 'idle');
    n.setActive(false);
  });

  test('knapp unter einer Minute zählt noch als Spiel', () async {
    final cloud = FakeCloud()..liveAge = const Duration(seconds: 59);
    await bensPacket(cloud, liveSolo);
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.playing);
    n.setActive(false);
  });

  test('Reiter zu: keine Abfragen mehr; wieder auf: sofort weiter', () async {
    final cloud = FakeCloud();
    await bensPacket(cloud, liveMatch);
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.playing);
    n.setActive(false);
    await pause(100); // eine laufende Abfrage darf noch fertig werden
    final stopped = cloud.requests.length;
    await pause(400);
    expect(cloud.requests.length, stopped, reason: 'nichts, solange der Reiter zu ist');
    n.setActive(true);
    await until(() => cloud.requests.length > stopped);
    expect(cloud.requests.last, startsWith('GET /v1/live?since='), reason: 'bedingt mit der bekannten Version');
    n.setActive(false);
  });

  test('doppeltes setActive(true) startet keine zweite Abfrage-Schleife', () async {
    final cloud = FakeCloud();
    await bensPacket(cloud, liveMatch);
    final c = await viewer(cloud);
    final n = c.read(liveViewerProvider.notifier);
    for (var i = 0; i < 5; i++) {
      n.setActive(true);
    }
    await pause(500);
    n.setActive(false);
    await pause(100);
    // 500 ms bei 25 ms Takt: höchstens ~20 Abfragen, nicht 5 mal so viele.
    expect(cloud.liveGets, lessThan(30));
  });

  test('Takt: spielt Ben, wird schneller abgefragt als im Leerlauf', () async {
    final cloud = FakeCloud();
    await bensPacket(cloud, liveMatch);
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.playing);
    var start = cloud.liveGets;
    await pause(600);
    final whilePlaying = cloud.liveGets - start;
    await bensPacket(cloud, ScreenState.idle);
    await until(() => seen.status == LiveViewStatus.notPlaying);
    start = cloud.liveGets;
    await pause(600);
    final whileIdle = cloud.liveGets - start;
    expect(whilePlaying, greaterThan(whileIdle * 1.5), reason: '$whilePlaying vs $whileIdle');
    n.setActive(false);
  });

  test('nach langer Ruhe wird noch seltener abgefragt', () async {
    LiveViewerController.idleSlowAfter = const Duration(milliseconds: 300);
    final cloud = FakeCloud();
    bensVault(cloud);
    await pause(20);
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.notPlaying);
    await pause(500);
    final start = cloud.liveGets;
    await pause(1000);
    final slow = cloud.liveGets - start;
    expect(slow, lessThanOrEqualTo(7), reason: '1 s bei 200 ms Takt: $slow');
    n.setActive(false);
  });

  test('Verbindung weg: "lost" mit letztem Stand, danach Erholung', () async {
    final cloud = FakeCloud();
    await bensPacket(cloud, liveMatch);
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.playing);

    cloud.override = (req) => http.Response('Bad Gateway', 502);
    await until(() => seen.status == LiveViewStatus.lost);
    expect(seen.states.last.screen!.toJson(), liveMatch.toJson(), reason: 'letzter Stand bleibt stehen');
    final attempts = cloud.requests.length;
    await pause(400);
    expect(cloud.requests.length, greaterThan(attempts + 2), reason: 'es wird weiter versucht');
    // Mit wachsendem Abstand: 30, 60, 90, 90 ms ...: in 400 ms höchstens ~7 Versuche.
    expect(cloud.requests.length - attempts, lessThan(10));

    cloud.override = null;
    await until(() => seen.status == LiveViewStatus.playing);
    expect(seen.states.last.screen!.hitSerial, 40);
    n.setActive(false);
  });

  test('"lost" ohne vorheriges Spiel zeigt keinen alten Stand', () async {
    final cloud = FakeCloud()..override = (req) => http.Response('', 503);
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.lost);
    expect(seen.states.last.screen, isNull);
    n.setActive(false);
  });

  test('retryNow überspringt die Wartezeit', () async {
    LiveViewerController.lostBackoff = const [Duration(seconds: 30)];
    final cloud = FakeCloud()..override = (req) => http.Response('', 503);
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.lost);
    cloud.override = null;
    bensVault(cloud);
    await bensPacket(cloud, liveMatch);
    n.retryNow();
    await until(() => seen.status == LiveViewStatus.playing);
    n.setActive(false);
  });

  test('alter Worker (hello ohne live): Hinweis statt Absturz, keine Live-Abfrage, später neue Prüfung', () async {
    final cloud = FakeCloud()..liveSupported = false;
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.workerTooOld);
    await pause(350);
    expect(cloud.requests.where((r) => r.startsWith('GET /v1/live')), isEmpty);
    expect(cloud.requests.where((r) => r == 'GET /v1/hello').length, inInclusiveRange(2, 5), reason: 'nur gelegentlich neu prüfen');

    // Ben aktualisiert den Worker.
    cloud.liveSupported = true;
    bensVault(cloud);
    await bensPacket(cloud, liveMatch);
    await until(() => seen.status == LiveViewStatus.playing);
    n.setActive(false);
  });

  test('alter Worker, der hello richtig meldet, aber /v1/live nicht kennt (404)', () async {
    final cloud = FakeCloud();
    cloud.override = (req) => req.url.path == '/v1/live'
        ? http.Response('{"error":"not-found"}', 404, headers: {'content-type': 'application/json', 'x-dartlab-cloud': '1'})
        : null;
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.workerTooOld);
    n.setActive(false);
  });

  test('falsches Geheimnis: es gibt keinen Tresor dazu', () async {
    final cloud = FakeCloud();
    bensVault(cloud);
    await bensPacket(cloud, liveMatch);
    await pause(20);
    final wrong = CloudSecret.generate(math.Random(99));
    final c = await viewer(cloud, useSecret: wrong);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.wrongSecret);
    expect(seen.states.last.screen, isNull);
    n.setActive(false);
  });

  test('Paket mit anderem Schlüssel verschlüsselt: lässt sich nicht öffnen, kein Absturz', () async {
    final cloud = FakeCloud();
    final other = CloudSecret.generate(math.Random(5));
    final sink = (await CloudLiveSink.create(url, other.text, client: cloud.client()))!;
    await sink.send(liveMatch);
    // Das Paket von "other" landet unter dem Tresor von "secret" (Server vertauscht oder verändert).
    final stolen = cloud.vault((await other.keys()).token).live!;
    cloud.vault((await secret.keys()).token).live = stolen;
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.wrongSecret);
    n.setActive(false);
  });

  test('401 des Servers: Geheimnis passt nicht', () async {
    final cloud = FakeCloud()
      ..override = (req) => req.url.path == '/v1/live'
          ? http.Response('{"error":"unauthorized"}', 401, headers: {'content-type': 'application/json', 'x-dartlab-cloud': '1'})
          : null;
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.wrongSecret);
    n.setActive(false);
  });

  test('Nur lesen: die Ansicht schickt nie etwas', () async {
    final cloud = FakeCloud();
    await bensPacket(cloud, liveMatch);
    cloud.livePuts = 0;
    cloud.requests.clear();
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.playing);
    await pause(300);
    n.setActive(false);
    expect(cloud.requests.every((r) => r.startsWith('GET ')), isTrue, reason: '${cloud.requests}');
    expect(cloud.livePuts, 0);
    expect(cloud.metaPuts, 0);
    expect(cloud.sessionPuts, 0);
    expect(cloud.deleted, isEmpty);
  });

  test('neues Geheimnis in den Einstellungen bei offener Ansicht: von vorn', () async {
    final cloud = FakeCloud();
    await bensPacket(cloud, liveMatch);
    final c = await viewer(cloud);
    final seen = Seen(c);
    final n = c.read(liveViewerProvider.notifier)..setActive(true);
    await until(() => seen.status == LiveViewStatus.playing);
    final other = CloudSecret.generate(math.Random(77));
    await c.read(settingsProvider.notifier).update((s) => s.copyWith(syncCloudSecret: other.text));
    await until(() => seen.status == LiveViewStatus.wrongSecret, what: 'neues, unbekanntes Geheimnis');
    await c.read(settingsProvider.notifier).update((s) => s.copyWith(syncCloudSecret: secret.text));
    await until(() => seen.status == LiveViewStatus.playing);
    n.setActive(false);
  });
}
