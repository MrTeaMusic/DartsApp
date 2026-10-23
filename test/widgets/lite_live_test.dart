import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/board/presentation/dartboard_view.dart';
import 'package:dartlab/features/live_remote/data/live_sink.dart';
import 'package:dartlab/features/live_remote/presentation/live_viewer_controller.dart';
import 'package:dartlab/features/second_screen/domain/screen_state.dart';
import 'package:dartlab/features/second_screen/presentation/screen_viewer_controller.dart';
import 'package:dartlab/features/sync/data/cloud_crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_cloud.dart';
import '../helpers/lite_app.dart';
import '../helpers/live_states.dart';

class FakeWakelock implements ScreenWakelock {
  final List<bool> calls = [];
  @override
  Future<void> set(bool on) async => calls.add(on);
}

const url = 'https://$liteUrl';

/// Bens App schickt ein Live-Paket.
Future<void> bensPacket(WidgetTester tester, FakeCloud cloud, ScreenState state) async {
  await tester.runAsync(() async {
    final sink = (await CloudLiveSink.create(url, liteSecret.text, client: cloud.client()))!;
    await sink.send(state);
    sink.close();
  });
}

/// Eine Lite-App, die schon eingerichtet ist (Adresse und Geheimnis gespeichert).
Future<ProviderContainer> openLite(WidgetTester tester, FakeCloud cloud, FakeWakelock wakelock, {Size size = const Size(360, 800)}) async {
  // Bens Tresor gibt es, damit der Abgleich der App und das Live-Paket zusammenpassen.
  await tester.runAsync(() => benInCloud(cloud));
  final c = await pumpLite(tester, cloud: cloud, size: size, prefs: liteConnectedPrefs(), overrides: [
    screenWakelockProvider.overrideWithValue(wakelock),
  ]);
  await settleLite(tester);
  return c;
}

/// Lässt die Zeit laufen und gibt echten Abfragen (Verschlüsselung) Raum.
Future<void> tick(WidgetTester tester, [Duration d = const Duration(seconds: 2)]) async {
  await tester.pump(d);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pump();
}

/// Die Navigation: unten (Handy) oder seitlich (breit).
Finder navLabel(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is NavigationBar || w is NavigationRail),
      matching: find.text(label),
    );

Future<void> openLiveTab(WidgetTester tester) async {
  await tester.tap(navLabel('Live'));
  await tester.pump();
  await tick(tester, const Duration(milliseconds: 100));
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(navLabel(label));
  await tester.pumpAndSettle();
}

int liveRequests(FakeCloud cloud) => cloud.requests.where((r) => r.contains('/v1/live')).length;

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late FakeCloud cloud;
  late FakeWakelock wakelock;
  setUp(() {
    cloud = FakeCloud();
    wakelock = FakeWakelock();
  });

  group('Abfragen nur bei offenem Reiter und Vordergrund', () {
    testWidgets('Statistik offen: keine einzige Live-Abfrage, Bildschirm nicht gesperrt', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      for (var i = 0; i < 5; i++) {
        await tick(tester, const Duration(seconds: 5));
      }
      expect(liveRequests(cloud), 0);
      expect(cloud.requests.where((r) => r.contains('hello')), isEmpty, reason: 'auch kein hello vom Live-Reiter');
      expect(wakelock.calls, isEmpty);
      await shutdownApp(tester, c);
    });

    testWidgets('Reiter auf: fragt ab und hält den Bildschirm an; Reiter zu: Schluss', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      await openLiveTab(tester);
      expect(find.byKey(const Key('live-tab')), findsOneWidget);
      expect(wakelock.calls, [true]);
      expect(liveRequests(cloud), greaterThan(0));
      // Ohne Spiel wird alle 5 Sekunden gefragt.
      await tick(tester, const Duration(seconds: 5));
      await tick(tester, const Duration(seconds: 5));
      final open = liveRequests(cloud);
      expect(open, greaterThanOrEqualTo(3));

      await openTab(tester, 'Statistik');
      expect(wakelock.calls, [true, false]);
      final closed = liveRequests(cloud);
      for (var i = 0; i < 5; i++) {
        await tick(tester, const Duration(seconds: 5));
      }
      expect(liveRequests(cloud), closed, reason: 'bei geschlossenem Reiter keine Abfrage mehr');

      await openTab(tester, 'Optionen');
      await tick(tester, const Duration(seconds: 10));
      expect(liveRequests(cloud), closed);

      await openLiveTab(tester);
      expect(wakelock.calls, [true, false, true]);
      expect(liveRequests(cloud), greaterThan(closed), reason: 'beim Öffnen sofort');
      await shutdownApp(tester, c);
      expect(wakelock.calls.last, false, reason: 'App weg: Bildschirm darf wieder ausgehen');
    });

    testWidgets('App im Hintergrund: keine Abfragen; zurück: weiter', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      await openLiveTab(tester);
      await tick(tester);
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(wakelock.calls.last, false);
      await tick(tester, const Duration(milliseconds: 100)); // laufende Abfrage darf enden
      final n = liveRequests(cloud);
      for (var i = 0; i < 6; i++) {
        await tick(tester, const Duration(seconds: 5));
      }
      expect(liveRequests(cloud), n, reason: 'im Hintergrund keine Abfrage');

      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tick(tester, const Duration(milliseconds: 100));
      expect(wakelock.calls.last, true);
      expect(liveRequests(cloud), greaterThan(n));
      await shutdownApp(tester, c);
    });

    testWidgets('Verbindungsdaten in den Optionen sind von hier aus erreichbar', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      await openLiveTab(tester);
      // Bei falschem Geheimnis führt der Knopf zu den Optionen.
      cloud.override = (req) => req.url.path == '/v1/live'
          ? http.Response('{"error":"unauthorized"}', 401, headers: {'content-type': 'application/json', 'x-dartlab-cloud': '1'})
          : null;
      c.read(liveViewerProvider.notifier).retryNow();
      await tick(tester, const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('live-to-settings')));
      await tester.pumpAndSettle();
      expect(c.read(routerProvider).routeInformationProvider.value.uri.path, '/einstellungen');
      expect(find.byKey(const Key('lite-settings')), findsOneWidget);
      await shutdownApp(tester, c);
    });
  });

  group('Zustände der Ansicht', () {
    testWidgets('noch nichts gesendet: "Ben spielt gerade nicht"', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      await openLiveTab(tester);
      expect(find.byKey(const Key('live-idle')), findsOneWidget);
      expect(find.text('Ben spielt gerade nicht'), findsOneWidget);
      expect(find.byKey(const Key('live-pill-live')), findsNothing);
      expect(tester.takeException(), isNull);
      await shutdownApp(tester, c);
    });

    testWidgets('X01-Match gegen den Bot läuft: Stand, Titel, Pill "Live"; folgt neuen Paketen', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      await bensPacket(tester, cloud, liveMatch);
      await openLiveTab(tester);
      await tick(tester, const Duration(milliseconds: 100));
      expect(find.byKey(const Key('live-playing')), findsOneWidget);
      expect(find.text('501 · X01-Match'), findsOneWidget);
      expect(find.byKey(const Key('live-subtitle')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('screen-score-Ben'))).data, '81');
      expect(tester.widget<Text>(find.byKey(const Key('screen-score-CPU 60'))).data, '146');
      expect(find.byKey(const Key('live-pill-live')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await bensPacket(tester, cloud, liveMatchNext);
      await tick(tester);
      expect(tester.widget<Text>(find.byKey(const Key('screen-score-Ben'))).data, '61');
      await shutdownApp(tester, c);
    });

    testWidgets('X01 solo und Training', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      await bensPacket(tester, cloud, liveSolo);
      await openLiveTab(tester);
      await tick(tester, const Duration(milliseconds: 100));
      expect(find.text('X01-Solo'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('screen-score-Ben'))).data, '170');
      expect(tester.takeException(), isNull);

      await bensPacket(tester, cloud, liveTraining);
      await tick(tester);
      expect(find.text('Around the Clock'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('screen-score-Ben'))).data, '7');
      expect(tester.takeException(), isNull);
      await shutdownApp(tester, c);
    });

    testWidgets('Spielende (idle-Paket): zurück zu "Ben spielt gerade nicht"', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      await bensPacket(tester, cloud, liveMatch);
      await openLiveTab(tester);
      await tick(tester, const Duration(milliseconds: 100));
      expect(find.byKey(const Key('live-playing')), findsOneWidget);
      await bensPacket(tester, cloud, ScreenState.idle);
      await tick(tester);
      expect(find.byKey(const Key('live-idle')), findsOneWidget);
      expect(find.byKey(const Key('live-playing')), findsNothing);
      await shutdownApp(tester, c);
    });

    testWidgets('Paket älter als eine Minute: Ben spielt nicht (z. B. App beendet)', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      await bensPacket(tester, cloud, liveMatch);
      await openLiveTab(tester);
      await tick(tester, const Duration(milliseconds: 100));
      expect(find.byKey(const Key('live-playing')), findsOneWidget);
      cloud.liveAge = const Duration(seconds: 75);
      await tick(tester);
      expect(find.byKey(const Key('live-idle')), findsOneWidget);
      await shutdownApp(tester, c);
    });

    testWidgets('Verbindung verloren: letzter Stand abgeblendet, Karte mit Knopf; danach Erholung', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      await bensPacket(tester, cloud, liveMatch);
      await openLiveTab(tester);
      await tick(tester, const Duration(milliseconds: 100));
      cloud.override = (req) => req.url.path == '/v1/live' ? http.Response('', 502) : null;
      await tick(tester);
      expect(find.byKey(const Key('live-lost')), findsOneWidget);
      expect(find.text('Verbindung verloren'), findsOneWidget);
      expect(find.byKey(const Key('live-retry')), findsOneWidget);
      expect(find.byKey(const Key('live-pill-lost')), findsOneWidget);
      // Der letzte Stand liegt abgeblendet dahinter.
      expect(find.byKey(const Key('screen-score-Ben')), findsOneWidget);
      expect(tester.widget<Opacity>(find.ancestor(of: find.byKey(const Key('screen-score-Ben')), matching: find.byType(Opacity)).first).opacity, lessThan(0.5));
      expect(tester.takeException(), isNull);

      cloud.override = null;
      await tester.tap(find.byKey(const Key('live-retry')));
      await tick(tester, const Duration(milliseconds: 100));
      expect(find.byKey(const Key('live-lost')), findsNothing);
      expect(find.byKey(const Key('live-playing')), findsOneWidget);
      await shutdownApp(tester, c);
    });

    testWidgets('Verbindung verloren ohne vorherigen Stand: nur der Hinweis', (tester) async {
      cloud.override = (req) => req.url.path == '/v1/live' ? http.Response('', 503) : null;
      final c = await openLite(tester, cloud, wakelock);
      await openLiveTab(tester);
      await tick(tester, const Duration(milliseconds: 100));
      expect(find.byKey(const Key('live-lost')), findsOneWidget);
      expect(find.byKey(const Key('screen-score-Ben')), findsNothing);
      expect(tester.takeException(), isNull);
      await shutdownApp(tester, c);
    });

    testWidgets('alter Cloud-Speicher: "kennt Live noch nicht" statt Absturz', (tester) async {
      cloud.liveSupported = false;
      final c = await openLite(tester, cloud, wakelock);
      await openLiveTab(tester);
      await tick(tester, const Duration(milliseconds: 100));
      expect(find.byKey(const Key('live-old-worker')), findsOneWidget);
      expect(find.text('Der Cloud-Speicher kennt Live noch nicht'), findsOneWidget);
      expect(find.textContaining('Ben muss seinen Cloud-Speicher'), findsOneWidget);
      expect(cloud.requests.where((r) => r.startsWith('GET /v1/live')), isEmpty);
      expect(tester.takeException(), isNull);
      await shutdownApp(tester, c);
    });

    testWidgets('falsches Geheimnis: eigener Hinweis mit Weg zu den Optionen', (tester) async {
      cloud.override = (req) => req.url.path == '/v1/live'
          ? http.Response('{"error":"no-vault"}', 404, headers: {'content-type': 'application/json', 'x-dartlab-cloud': '1'})
          : null;
      final c = await openLite(tester, cloud, wakelock);
      await openLiveTab(tester);
      await tick(tester, const Duration(milliseconds: 100));
      expect(find.byKey(const Key('live-wrong-secret')), findsOneWidget);
      expect(find.text('Geheimnis passt nicht'), findsOneWidget);
      expect(find.byKey(const Key('live-to-settings')), findsOneWidget);
      await shutdownApp(tester, c);
    });

    testWidgets('Paket mit fremdem Schlüssel: Geheimnis passt nicht', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      await tester.runAsync(() async {
        final other = CloudSecret.tryParse('0123456789ABCDEFGHJKMNPQRS')!;
        final sink = (await CloudLiveSink.create(url, other.text, client: cloud.client()))!;
        await sink.send(liveMatch);
        cloud.vault((await liteSecret.keys()).token).live = cloud.vault((await other.keys()).token).live;
      });
      await openLiveTab(tester);
      await tick(tester, const Duration(milliseconds: 100));
      expect(find.byKey(const Key('live-wrong-secret')), findsOneWidget);
      await shutdownApp(tester, c);
    });
  });

  group('Nur lesen', () {
    testWidgets('der Live-Reiter schickt nie etwas, die Optionen haben keinen Sende-Schalter', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      final putsBefore = (cloud.metaPuts, cloud.sessionPuts, cloud.livePuts);
      await bensPacket(tester, cloud, liveMatch);
      cloud.livePuts = 0;
      cloud.requests.clear();
      await openLiveTab(tester);
      for (var i = 0; i < 4; i++) {
        await tick(tester);
      }
      expect(cloud.livePuts, 0);
      expect(cloud.requests, isNotEmpty);
      expect(cloud.requests.where((r) => r.contains('/v1/live')).every((r) => r.startsWith('GET ')), isTrue, reason: '${cloud.requests}');
      expect((cloud.metaPuts, cloud.sessionPuts), (putsBefore.$1, putsBefore.$2));

      await openTab(tester, 'Optionen');
      expect(find.byKey(const Key('sync-live-switch'), skipOffstage: false), findsNothing);
      expect(find.textContaining('Live übers Internet', skipOffstage: false), findsNothing);
      await shutdownApp(tester, c);
    });
  });

  group('Layout', () {
    for (final size in [const Size(360, 800), const Size(320, 640), const Size(412, 915), const Size(800, 360), const Size(1280, 800)]) {
      testWidgets('kein Überlauf bei ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final c = await openLite(tester, cloud, wakelock, size: size);
        for (final s in [liveMatch, liveSolo, liveTraining]) {
          await bensPacket(tester, cloud, s);
          await openLiveTab(tester);
          await tick(tester);
          expect(find.byKey(const Key('live-playing')), findsOneWidget, reason: s.title);
          expect(tester.takeException(), isNull, reason: s.title);
        }
        cloud.override = (req) => req.url.path == '/v1/live' ? http.Response('', 502) : null;
        await tick(tester);
        expect(find.byKey(const Key('live-lost')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shutdownApp(tester, c);
      });
    }
  });

  group('Scheibe', () {
    // Nur Felder, keine Koordinaten (manuelle Eingabe im Training).
    const ohneKoordinaten = ScreenState(
      kind: ScreenKind.training,
      title: 'Around the Clock',
      subtitle: 'Ben',
      players: [ScreenPlayer(name: 'Ben', score: '7', scoreLabel: 'Ziel', active: true, darts: 21)],
      visit: ['S6', 'S7'],
      hits: [ScreenHit('S6'), ScreenHit('S7')],
      hitSerial: 21,
      progress: 6 / 21,
      progressLabel: '6/21',
    );
    const mitLiveKind = ScreenState(
      kind: ScreenKind.live,
      title: 'Live-Mitschreiben',
      players: [ScreenPlayer(name: 'Ben', score: '301', scoreLabel: 'Rest', active: true), ScreenPlayer(name: 'Gegner', score: '251', scoreLabel: 'Rest')],
      visit: ['T20'],
      hits: [ScreenHit('T20')],
      hitSerial: 3,
    );
    final states = {
      'Match': liveMatch,
      'X01 solo': liveSolo,
      'Training mit Koordinaten': liveTraining,
      'Training ohne Koordinaten': ohneKoordinaten,
      'Live-Mitschreiben ohne Koordinaten': mitLiveKind,
    };

    for (final size in [const Size(360, 800), const Size(320, 640), const Size(412, 915), const Size(800, 360)]) {
      testWidgets('jedes laufende Spiel zeigt die Scheibe, ohne Überlauf bei ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final c = await openLite(tester, cloud, wakelock, size: size);
        for (final e in states.entries) {
          await bensPacket(tester, cloud, e.value);
          await openLiveTab(tester);
          await tick(tester);
          expect(find.byKey(const Key('live-playing')), findsOneWidget, reason: e.key);
          expect(find.byKey(const Key('screen-board')), findsOneWidget, reason: e.key);
          expect(tester.takeException(), isNull, reason: e.key);
          // Der Dart ohne Koordinaten hebt trotzdem sein Feld hervor.
          final board = tester.widget<DartboardView>(find.byKey(const Key('screen-board')));
          expect(board.lastSegment, Segment.tryParse(e.value.hits.last.segment), reason: e.key);
          final lastHit = e.value.hits.last;
          if (lastHit.x == null && lastHit.segment != 'MISS') {
            expect(board.highlighted, contains(Segment.tryParse(lastHit.segment)), reason: '${e.key}: Feld bleibt hervorgehoben');
          }
        }
        await shutdownApp(tester, c);
      });
    }

    testWidgets('wenn es eng wird, scrollt die Anzeige (Solo mit Kennzahlen, 360x640)', (tester) async {
      final c = await openLite(tester, cloud, wakelock, size: const Size(360, 640));
      await bensPacket(tester, cloud, liveSolo);
      await openLiveTab(tester);
      await tick(tester);
      expect(find.byKey(const Key('screen-scroll')), findsOneWidget);
      expect(find.byKey(const Key('screen-board')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('screen-board')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await shutdownApp(tester, c);
    });

    testWidgets('Leerlauf zeigt keine Scheibe', (tester) async {
      final c = await openLite(tester, cloud, wakelock);
      await bensPacket(tester, cloud, ScreenState.idle);
      await openLiveTab(tester);
      await tick(tester, const Duration(seconds: 5));
      expect(find.byKey(const Key('screen-board')), findsNothing);
      await shutdownApp(tester, c);
    });
  });
}
