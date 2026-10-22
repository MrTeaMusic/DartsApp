import 'package:dartlab/core/design/dart_look.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/lite_app.dart';
import '../helpers/pump_app.dart';

DartLookId shownLook(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).first)).extension<DartLook>()!.id;

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('Look der Lite-Variante', () {
    testWidgets('Einrichtung: Arena, auch wenn ein anderer Look gespeichert ist', (tester) async {
      final c = await pumpLite(tester, prefs: {'settings.look': 'clean'});
      expect(c.read(settingsProvider).look, DartLookId.arena);
      expect(shownLook(tester), DartLookId.arena);
      // Immer dunkel, auch wenn die Einstellung „hell“ sagt.
      expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.dark);
    });

    testWidgets('ohne gespeicherten Look: Arena (nicht TV)', (tester) async {
      final c = await pumpLite(tester);
      expect(c.read(settingsProvider).look, DartLookId.arena);
      expect(shownLook(tester), DartLookId.arena);
    });

    testWidgets('Statistik und Optionen: Arena, ohne Look-Auswahl', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      expect(shownLook(tester), DartLookId.arena);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Optionen')));
      await tester.pumpAndSettle();
      expect(shownLook(tester), DartLookId.arena);
      for (final id in DartLookId.values) {
        expect(find.byKey(Key('look-${id.name}'), skipOffstage: false), findsNothing, reason: id.name);
      }
      expect(find.text('Darstellung'), findsNothing);
      await shutdownApp(tester, c);
    });
  });

  group('Reiterleiste der Statistik (360 breit)', () {
    testWidgets('startet bei Offset 0, der erste Reiter hat links Rand', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      final bar = find.descendant(of: find.byType(TabBar), matching: find.byType(Scrollable)).first;
      expect(tester.state<ScrollableState>(bar).position.pixels, 0);
      final first = tester.getTopLeft(find.byKey(const Key('stats-tab-overview'))).dx;
      expect(first, greaterThan(0), reason: 'Reiter „Überblick“ nicht angeschnitten');
      expect(first, lessThanOrEqualTo(40));
      await shutdownApp(tester, c);
    });
  });

  group('Hauptapp', () {
    testWidgets('bleibt bei TV als Standard', (tester) async {
      final c = await pumpApp(tester);
      expect(c.read(settingsProvider).look, DartLookId.tv);
      expect(shownLook(tester), DartLookId.tv);
    });

    testWidgets('behält den gespeicherten Look', (tester) async {
      final c = await pumpApp(tester, prefs: {'settings.look': 'lab'});
      expect(c.read(settingsProvider).look, DartLookId.lab);
    });
  });
}
