import 'dart:async';

import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/settings/presentation/settings_screen.dart';
import 'package:dartlab/features/sync/domain/sync_role.dart';
import 'package:dartlab/features/sync/presentation/sync_controller.dart';
import 'package:dartlab/features/second_screen/data/screen_client.dart';
import 'package:dartlab/features/second_screen/domain/screen_state.dart';
import 'package:dartlab/features/second_screen/presentation/screen_viewer_controller.dart';
import 'package:dartlab/features/second_screen/presentation/second_screen_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

class FakeLink implements ScreenLink {
  final controller = StreamController<ScreenState>();
  bool closed = false;

  @override
  Stream<ScreenState> get states => controller.stream;

  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) await controller.close();
  }
}

/// Verbindet nach Drehbuch: jede Anfrage nimmt die nächste Antwort.
class FakeHub {
  final List<Object> script = [];
  final calls = <String>[];
  FakeLink? link;

  Future<ScreenLink> connect({required String host, required int port, required String key}) async {
    calls.add('$host:$port/$key');
    final next = script.isEmpty ? const ScreenConnectException(ScreenFailure.unreachable) : script.removeAt(0);
    if (next is ScreenConnectException) throw next;
    return link = next as FakeLink;
  }
}

/// Abgleich, der nichts tut (sonst liefen im Widget-Test Timer und HTTP).
class NoSync extends SyncController {
  @override
  SyncState build() => const SyncState(role: SyncRole.client);
}

class FakeWakelock implements ScreenWakelock {
  final List<bool> calls = [];
  @override
  Future<void> set(bool on) async => calls.add(on);
}

/// Adresse und Code des PCs. Der zweite Bildschirm braucht keinen laufenden
/// Abgleich (der würde im Widget-Test Timer und HTTP starten).
const viewer = {'sync.host': '192.168.178.20', 'sync.key': '123456'};

ScreenState match({String? banner, String benScore = '121'}) => ScreenState(
      kind: ScreenKind.match,
      title: '501 · X01-Match',
      subtitle: 'First to 3 Legs (Best of 5) · Leg 2',
      status: 'Ben ist dran',
      players: [
        ScreenPlayer(name: 'Ben', score: benScore, scoreLabel: 'Rest', active: true, legs: 1, average: '58,2', lastVisit: 100),
        const ScreenPlayer(name: 'CPU 60', score: '230', scoreLabel: 'Rest', bot: true, legs: 0, average: '61,0', lastVisit: 45),
      ],
      visit: const ['T20'],
      visitScore: 60,
      route: const ['T17', 'D5'],
      lastVisit: const ['S5', 'T20', 'S20'],
      lastVisitScore: 85,
      hits: const [ScreenHit('T20', x: 0, y: 0.6)],
      hitSerial: 13,
      banner: banner,
      bannerTone: ScreenTone.positive,
    );

/// Seite verlassen, damit Verbindung und Wiederholungs-Timer enden.
Future<void> leave(WidgetTester tester, ProviderContainer c) async {
  c.read(routerProvider).go(Routes.home);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late FakeHub hub;
  late FakeWakelock wakelock;

  setUp(() {
    hub = FakeHub();
    wakelock = FakeWakelock();
    ScreenViewerController.backoff = const [Duration(seconds: 1), Duration(seconds: 2)];
    ScreenViewerController.slowRetry = const Duration(seconds: 3);
  });

  Future<ProviderContainer> open(WidgetTester tester, {Map<String, Object> prefs = viewer, Size size = const Size(1280, 800)}) async {
    final c = await pumpApp(tester, size: size, prefs: prefs, overrides: [
      screenConnectorProvider.overrideWithValue(hub.connect),
      screenWakelockProvider.overrideWithValue(wakelock),
    ]);
    c.read(routerProvider).go(secondScreenRoute);
    await tester.pump();
    await tester.pump();
    return c;
  }

  testWidgets('ohne eingerichteten PC: Hinweis und Weg zu den Optionen', (tester) async {
    await open(tester, prefs: const {});
    expect(find.byKey(const Key('screen-not-configured')), findsOneWidget);
    expect(hub.calls, isEmpty);
    await tester.tap(find.byKey(const Key('screen-to-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    // Seite zu: Bildschirm darf wieder ausgehen.
    expect(wakelock.calls, [true, false]);
  });

  testWidgets('verbindet, wartet auf ein Spiel und zeigt dann den Spielstand', (tester) async {
    final link = FakeLink();
    hub.script.add(link);
    final c = await open(tester);
    expect(hub.calls, ['192.168.178.20:3190/123456']);
    expect(wakelock.calls, [true]);

    link.controller.add(ScreenState.idle);
    await tester.pump();
    expect(find.byKey(const Key('screen-idle')), findsOneWidget);
    expect(find.text('Warte auf Spiel am PC'), findsOneWidget);
    expect(find.byKey(const Key('screen-pill-connected')), findsOneWidget);

    link.controller.add(match(banner: 'Leg an Ben (81 gecheckt)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('screen-idle')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('screen-score-Ben'))).data, '121');
    expect(tester.widget<Text>(find.byKey(const Key('screen-score-CPU 60'))).data, '230');
    expect(find.text('501 · X01-Match'), findsOneWidget);
    expect(find.byKey(const Key('screen-banner')), findsOneWidget);
    expect(find.textContaining('T17 · D5'), findsOneWidget);
    expect(find.byKey(const Key('screen-board')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('screen-visit-score'))).data, '60');

    // Neuer Stand ersetzt den alten.
    link.controller.add(match(benScore: '61'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<Text>(find.byKey(const Key('screen-score-Ben'))).data, '61');
    expect(find.byKey(const Key('screen-banner')), findsNothing);
    await leave(tester, c);
  });

  testWidgets('Verbindung weg: Hinweis über dem letzten Stand, verbindet von selbst neu', (tester) async {
    final first = FakeLink();
    final second = FakeLink();
    hub.script.addAll([first, const ScreenConnectException(ScreenFailure.unreachable), second]);
    final c = await open(tester);
    first.controller.add(match());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('screen-score-Ben')), findsOneWidget);

    // PC weg.
    await first.controller.close();
    await tester.pump();
    expect(find.byKey(const Key('screen-lost')), findsOneWidget);
    expect(find.text('Verbindung verloren'), findsOneWidget);
    expect(find.byKey(const Key('screen-pill-lost')), findsOneWidget);
    // Der letzte Stand bleibt blass dahinter stehen.
    expect(find.byKey(const Key('screen-score-Ben')), findsOneWidget);

    // Erster neuer Versuch nach 1 s schlägt fehl, der nächste nach 2 s klappt.
    await tester.pump(const Duration(seconds: 1));
    expect(hub.calls, hasLength(2));
    expect(find.byKey(const Key('screen-lost')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(hub.calls, hasLength(3));
    second.controller.add(ScreenState.idle);
    await tester.pump();
    expect(find.byKey(const Key('screen-lost')), findsNothing);
    expect(find.byKey(const Key('screen-idle')), findsOneWidget);
    expect(find.byKey(const Key('screen-pill-connected')), findsOneWidget);
    await leave(tester, c);
  });

  testWidgets('nie verbunden: „Verbindung verloren“ mit Knopf für sofortigen Versuch', (tester) async {
    final link = FakeLink();
    hub.script.addAll([const ScreenConnectException(ScreenFailure.unreachable), link]);
    final c = await open(tester, size: const Size(390, 844));
    await tester.pump();
    expect(find.byKey(const Key('screen-lost')), findsOneWidget);
    await tester.tap(find.byKey(const Key('screen-retry')));
    await tester.pump();
    expect(hub.calls, hasLength(2));
    link.controller.add(match());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('screen-score-Ben')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await leave(tester, c);
  });

  testWidgets('falscher Code und alter Hub werden erklärt', (tester) async {
    hub.script.addAll([
      const ScreenConnectException(ScreenFailure.wrongKey),
      const ScreenConnectException(ScreenFailure.hubTooOld),
    ]);
    final c = await open(tester);
    await tester.pump();
    expect(find.byKey(const Key('screen-wrong-key')), findsOneWidget);
    expect(find.byKey(const Key('screen-to-settings')), findsOneWidget);
    // Langsamer neuer Versuch (der Code könnte am PC geändert werden).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.byKey(const Key('screen-hub-old')), findsOneWidget);
    await leave(tester, c);
  });

  testWidgets('Schließen gibt die Verbindung und den Bildschirm frei', (tester) async {
    final link = FakeLink();
    hub.script.add(link);
    await open(tester);
    link.controller.add(ScreenState.idle);
    await tester.pump();
    await tester.tap(find.byKey(const Key('screen-close')));
    await tester.pumpAndSettle();
    expect(find.byType(SecondScreenPage), findsNothing);
    expect(link.closed, isTrue);
    expect(wakelock.calls, [true, false]);
  });

  testWidgets('Startseite: Einstieg nur auf Geräten, die mit dem PC verbunden sind', (tester) async {
    final link = FakeLink();
    hub.script.add(link);
    final c = await pumpApp(tester, prefs: {...viewer, 'sync.role': 'client'}, overrides: [
      screenConnectorProvider.overrideWithValue(hub.connect),
      screenWakelockProvider.overrideWithValue(wakelock),
      syncControllerProvider.overrideWith(NoSync.new),
    ]);
    expect(find.byKey(const Key('home-open-screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-open-screen')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SecondScreenPage), findsOneWidget);
    expect(hub.calls, hasLength(1));
    await leave(tester, c);
  });

  testWidgets('Startseite: kein Einstieg ohne Verbindung zum PC', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('home-open-screen')), findsNothing);
  });
}
