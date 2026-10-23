import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/autodarts_import/presentation/autodarts_import_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/autodarts_match_fixture.dart';
import '../helpers/lite_app.dart';
import '../helpers/pump_app.dart';

// Alle Match-Daten sind synthetisch (siehe autodarts_match_fixture.dart).

final _supported = importReceiverSupportedProvider.overrideWithValue(true);

Future<void> _openCard(WidgetTester tester) async {
  await tester.tap(find.text('Optionen').first);
  await tester.pumpAndSettle();
  final card = find.byKey(const Key('import-card'));
  await tester.scrollUntilVisible(card, 300, scrollable: find.byType(Scrollable).last);
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
}

Future<void> _real(WidgetTester tester, [int ms = 300]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pumpAndSettle();
}

/// Schaltet den Empfänger aus und wartet, bis er gestoppt ist (sonst bleibt
/// sein Leerlauf-Timer nach dem Test hängen).
Future<void> _stopReceiver(WidgetTester tester, ProviderContainer c) async {
  await c.read(settingsProvider.notifier).update((x) => x.copyWith(autodartsImportEnabled: false));
  await _real(tester);
  await _real(tester);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}


/// Führt [client] in der echten Zone aus (echte Sockets) und pumpt dabei die
/// Test-Zone, in der der Empfänger seine Anfragen verarbeitet.
Future<T> _outside<T>(WidgetTester tester, Future<T> Function() client) async {
  late T result;
  Object? error;
  var done = false;
  Zone.root.run(() {
    client().then<void>((v) => result = v, onError: (Object e) => error = e).whenComplete(() => done = true);
  });
  for (var i = 0; i < 300 && !done; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(done, isTrue, reason: 'Anfrage nicht fertig');
  if (error != null) throw error!;
  await tester.pumpAndSettle();
  return result;
}

Future<int> _status(String method, Uri uri, {String? key, String? body}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, uri);
    if (key != null) req.headers.set('X-DartLab-Key', key);
    if (body != null) {
      req.headers.set('content-type', 'application/json');
      req.add(utf8.encode(body));
    }
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    client.close(force: true);
  }
}

String _json(Map<String, Object?> m) => jsonEncode(m);

void main() {
  // flutter_test ersetzt HttpClient durch eine Attrappe (immer 400); wir sprechen mit dem echten lokalen Server.
  setUp(() => HttpOverrides.global = null);

  testWidgets('Empfänger ist standardmäßig aus, ohne Code und ohne Server', (tester) async {
    final c = await pumpApp(tester, overrides: [_supported]);
    await _openCard(tester);
    final sw = tester.widget<SwitchListTile>(find.byKey(const Key('import-receiver-switch')));
    expect(sw.value, isFalse);
    expect(find.byKey(const Key('import-code')), findsNothing);
    expect(find.byKey(const Key('import-status')), findsNothing);
    expect(c.read(autodartsImportControllerProvider).running, isFalse);
    expect(c.read(settingsProvider).autodartsImportEnabled, isFalse);
    // Der ruhige Hinweis steht immer da.
    expect(find.byKey(const Key('import-tos')), findsOneWidget);
    expect(find.textContaining('AGB von Autodarts verbieten Drittsoftware'), findsOneWidget);
    expect(find.textContaining('auf eigenes Risiko'), findsOneWidget);
  });

  testWidgets('Einschalten: sechsstelliger Code, Server läuft, Ausschalten stoppt ihn', (tester) async {
    final c = await pumpApp(tester, prefs: {'import.port': 0}, overrides: [_supported]);
    await _openCard(tester);
    await _tap(tester, find.byKey(const Key('import-receiver-switch')));
    await _real(tester);
    await _real(tester);

    final key = c.read(settingsProvider).autodartsImportKey;
    expect(key, matches(RegExp(r'^\d{6}$')));
    expect(find.text(key), findsOneWidget);
    expect(find.textContaining('Läuft auf 127.0.0.1:'), findsOneWidget);
    expect(find.text('Noch nichts empfangen.'), findsOneWidget);
    final port = c.read(autodartsImportControllerProvider).port!;

    // Der Server antwortet wirklich (und nur mit Code).
    final ping = Uri.parse('http://127.0.0.1:$port/import/ping');
    expect(await _outside(tester, () => _status('GET', ping, key: key)), 200);
    expect(await _outside(tester, () => _status('GET', ping, key: '000000')), 401);

    // Neuer Code ersetzt den alten, der Server läuft mit dem neuen weiter.
    await _tap(tester, find.byKey(const Key('import-code-new')));
    await _real(tester);
    await _real(tester);
    expect(c.read(settingsProvider).autodartsImportKey, isNot(key));

    await _tap(tester, find.byKey(const Key('import-receiver-switch')));
    await _real(tester);
    expect(c.read(autodartsImportControllerProvider).running, isFalse);
    expect(find.byKey(const Key('import-code')), findsNothing);
    final after = await tester.runAsync(() async {
      try {
        final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1));
        await s.close();
        return true;
      } on SocketException {
        return false;
      }
    });
    expect(after, isFalse, reason: 'Port ist nach dem Ausschalten frei');
  });

  testWidgets('Port belegt: klare Meldung statt Absturz', (tester) async {
    final blocker = await tester.runAsync(() => ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    addTearDown(() => blocker!.close());
    final c = await pumpApp(
      tester,
      prefs: {'import.enabled': true, 'import.key': '123456', 'import.port': blocker!.port},
      overrides: [_supported],
    );
    await _openCard(tester);
    await _real(tester);
    expect(c.read(autodartsImportControllerProvider).problem, ReceiverProblem.portBusy);
    expect(find.textContaining('ist belegt'), findsOneWidget);
    expect(find.textContaining('${blocker.port}'), findsWidgets);
  });

  testWidgets('Port ändern startet den Empfänger auf dem neuen Port; ungültiger Port wird abgelehnt', (tester) async {
    final c = await pumpApp(tester, prefs: {'import.enabled': true, 'import.key': '123456', 'import.port': 0}, overrides: [_supported]);
    await _openCard(tester);
    await _real(tester);
    expect(c.read(autodartsImportControllerProvider).running, isTrue);

    final field = find.descendant(of: find.byKey(const Key('import-port-field')), matching: find.byType(TextFormField));
    await tester.enterText(field, '80');
    await tester.pumpAndSettle();
    expect(find.text('1024 bis 65535'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('import-port-apply')));
    expect(c.read(settingsProvider).autodartsImportPort, 0, reason: 'unverändert');

    await tester.enterText(field, '39191');
    await _tap(tester, find.byKey(const Key('import-port-apply')));
    await _real(tester);
    expect(c.read(settingsProvider).autodartsImportPort, 39191);
    // Im Test kann der Port durch einen anderen Prozess belegt sein; entweder läuft er oder es kommt die Meldung.
    final s = c.read(autodartsImportControllerProvider);
    expect(s.running || s.problem == ReceiverProblem.portBusy, isTrue);
    await _stopReceiver(tester, c);
  });

  testWidgets('Auf dem Handy: kein Empfänger (auch nicht bei gesetztem Schalter), aber Name und JSON-Einfügen', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844), prefs: {'import.enabled': true, 'import.key': '123456', 'import.port': 0});
    await _openCard(tester);
    expect(find.byKey(const Key('import-receiver-switch')), findsNothing);
    expect(find.byKey(const Key('import-desktop-only')), findsOneWidget);
    expect(find.byKey(const Key('import-my-name')), findsOneWidget);
    expect(find.byKey(const Key('import-paste')), findsOneWidget);
    expect(c.read(autodartsImportControllerProvider).running, isFalse);
  });

  testWidgets('„Mein Autodarts-Name“ wird gespeichert', (tester) async {
    final c = await pumpApp(tester, overrides: [_supported]);
    await _openCard(tester);
    await tester.enterText(find.byKey(const Key('import-my-name')), '  Ben  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).autodartsMyName, 'Ben');
  });

  testWidgets('JSON einfügen: Vorschau, Importieren, Verlauf zeigt Gegner', (tester) async {
    final c = await pumpApp(tester, prefs: {'import.myName': 'Ben'}, overrides: [_supported]);
    await _openCard(tester);
    await _tap(tester, find.byKey(const Key('import-paste')));
    expect(find.byKey(const Key('import-json-dialog')), findsOneWidget);
    expect(find.text('Noch nichts eingefügt.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('import-json-import'))).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('import-json-field')), _json(syntheticMatch()));
    await _real(tester, 400);
    expect(find.byKey(const Key('import-preview-title')), findsOneWidget);
    expect(find.textContaining('Ben vs Gegner · 3:2'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('import-json-import')));
    await _real(tester);
    expect(find.byKey(const Key('import-json-dialog')), findsNothing);
    expect(find.textContaining('Importiert: Gegner, 3:2'), findsOneWidget);
    expect(find.textContaining('Letzter Import: Gegner, 3:2'), findsOneWidget);
    expect(await c.read(appDatabaseProvider).select(c.read(appDatabaseProvider).sessions).get(), hasLength(1));

    // Zweites Mal: bereits importiert → Ersetzen statt Doppel.
    await _tap(tester, find.byKey(const Key('import-paste')));
    await tester.enterText(find.byKey(const Key('import-json-field')), _json(syntheticMatch()));
    await _real(tester, 400);
    expect(find.text('Dieses Match ist schon importiert.'), findsOneWidget);
    expect(find.text('Ersetzen'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('import-json-close')));

    // Verlauf: Eintrag mit Gegner.
    c.read(routerProvider).go(Routes.stats);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stats-history')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Gegner'), findsWidgets);
    expect(find.textContaining('3:2'), findsWidgets);
  });

  testWidgets('JSON einfügen: Fehlerfall zeigt Grund, Importieren bleibt aus', (tester) async {
    await pumpApp(tester, overrides: [_supported]);
    await _openCard(tester);
    await _tap(tester, find.byKey(const Key('import-paste')));

    await tester.enterText(find.byKey(const Key('import-json-field')), '{"a":');
    await _real(tester, 400);
    expect(find.text('Kein gültiges JSON.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('import-json-import'))).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('import-json-field')), _json(syntheticMatch(variant: 'Cricket')));
    await _real(tester, 400);
    expect(find.textContaining('X01'), findsWidgets);
    expect(tester.widget<FilledButton>(find.byKey(const Key('import-json-import'))).onPressed, isNull);
  });

  testWidgets('Name unbekannt: „Welcher Spieler bist du?“, Antwort importiert und merkt den Namen', (tester) async {
    final c = await pumpApp(tester, overrides: [_supported]);
    await _openCard(tester);
    await _tap(tester, find.byKey(const Key('import-paste')));
    await tester.enterText(find.byKey(const Key('import-json-field')), _json(syntheticMatch()));
    await _real(tester, 400);
    expect(find.text('Wer du bist, fragt DartLab beim Importieren.'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('import-json-import')));
    expect(find.byKey(const Key('import-who-dialog')), findsOneWidget);
    expect(find.text('Welcher Spieler bist du?'), findsOneWidget);
    expect(find.byKey(const Key('import-who-0')), findsOneWidget);
    expect(find.byKey(const Key('import-who-1')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('import-who-0')));
    await _real(tester);

    expect(c.read(settingsProvider).autodartsMyName, 'Ben');
    final db = c.read(appDatabaseProvider);
    expect(await db.select(db.sessions).get(), hasLength(1));
  });

  testWidgets('Empfangenes Match ohne bekannten Namen: Frage erscheint von selbst, „Später“ lässt sie in den Optionen', (tester) async {
    final c = await pumpApp(tester, prefs: {'import.enabled': true, 'import.key': '123456', 'import.port': 0}, overrides: [_supported]);
    await _real(tester);
    final port = c.read(autodartsImportControllerProvider).port!;
    expect(
      await _outside(tester, () => _status('POST', Uri.parse('http://127.0.0.1:$port/import/autodarts?id=abc'), key: '123456', body: _json(syntheticMatch()))),
      200,
    );
    await _real(tester);
    expect(find.byKey(const Key('import-who-dialog')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('import-who-later')));
    expect(find.byKey(const Key('import-who-dialog')), findsNothing);
    expect(c.read(autodartsImportControllerProvider).pending, hasLength(1));

    await _openCard(tester);
    expect(find.byKey(const Key('import-pending')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('import-pending-answer')));
    expect(find.byKey(const Key('import-who-dialog')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('import-who-1')));
    await _real(tester);
    expect(c.read(autodartsImportControllerProvider).pending, isEmpty);
    expect(c.read(settingsProvider).autodartsMyName, 'Gegner');
    expect(find.textContaining('Letzter Import: Ben, 2:3'), findsOneWidget);
    await _stopReceiver(tester, c);
  });

  group('Lite', () {
    testWidgets('startet nie einen Empfänger, auch nicht bei eingeschaltetem Schalter', (tester) async {
      final c = await pumpLite(tester, prefs: {'import.enabled': true, 'import.key': '123456', 'import.port': 0});
      await _real(tester);
      expect(c.read(importReceiverSupportedProvider), isFalse);
      expect(c.read(autodartsImportControllerProvider).running, isFalse);
      expect(c.read(autodartsImportControllerProvider).problem, isNull);
    });
  });
}
