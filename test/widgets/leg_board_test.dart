import 'dart:ui' as ui;

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/design/dart_icon.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/matches/domain/match_result.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/history_seed.dart';
import '../helpers/leg_seed.dart';
import '../helpers/lite_app.dart';
import '../helpers/pump_app.dart';

// Aufnahmenverlauf je Leg: Diagramm, Zwei-Spalten-Tabelle, verpasste Doppel.
// Daten: von Hand gebautes Match (Ben gegen Anna), siehe leg_seed.dart.

const _phone = Size(360, 800);
const _desktop = Size(1280, 800);

Finder _inDetail(Finder f) => find.descendant(of: find.byKey(const Key('session-detail')), matching: f);

Future<void> _scrollTo(WidgetTester tester, Key key) async {
  final list = _inDetail(find.byType(Scrollable)).first;
  // Von oben: Abschnitte außerhalb des Bildschirms sind nicht gebaut.
  tester.state<ScrollableState>(list).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.byKey(key), 300, scrollable: list);
  await Scrollable.ensureVisible(tester.element(find.byKey(key)), alignment: 0.3, duration: Duration.zero);
  await tester.pumpAndSettle();
}

Future<(ProviderContainer, int)> _open(
  WidgetTester tester, {
  Size size = _phone,
  String look = 'tv',
  bool withOpponent = true,
}) async {
  final c = await pumpApp(tester, size: size, prefs: {'settings.look': look});
  final me = await c.read(profileRepositoryProvider).resolve(null);
  await c.read(profileRepositoryProvider).rename(me, 'Ben');
  final id = await seedHandMadeMatch(c.read(gameRepositoryProvider), me, DateTime.now(), withOpponent: withOpponent);
  await tester.pumpAndSettle();
  c.read(routerProvider).go(Routes.session(id));
  await tester.pumpAndSettle();
  return (c, id);
}

void main() {
  testWidgets('Match: Diagramm und Tabelle je Leg mit beiden Spielern, Rest und Checkout', (tester) async {
    await _open(tester);
    await _scrollTo(tester, const Key('session-leg-1'));
    expect(find.byKey(const Key('session-leg-1-chart')), findsOneWidget);
    // Kopf: beide Namen und der Startwert.
    final table = find.byKey(const Key('session-leg-1'));
    expect(find.descendant(of: table, matching: find.text('Ben')), findsOneWidget);
    expect(find.descendant(of: table, matching: find.text('Anna')), findsOneWidget);
    expect(find.descendant(of: table, matching: find.text('101')), findsNWidgets(2));
    // Zeile 1: Ben 81, Rest 20; Anna 60, Rest 41. Zeile 2: Ben D5 zum Checkout, Rest 0.
    final ben1 = find.byKey(const Key('leg-1-p0-v1'));
    expect(find.descendant(of: ben1, matching: find.text('81')), findsOneWidget);
    expect(find.descendant(of: ben1, matching: find.text('20')), findsOneWidget);
    expect(find.descendant(of: ben1, matching: find.textContaining('T20')), findsOneWidget);
    final anna1 = find.byKey(const Key('leg-1-p1-v1'));
    expect(find.descendant(of: anna1, matching: find.text('60')), findsOneWidget);
    expect(find.descendant(of: anna1, matching: find.text('41')), findsOneWidget);
    final ben2 = find.byKey(const Key('leg-1-p0-v2'));
    expect(find.descendant(of: ben2, matching: find.text('0')), findsOneWidget, reason: 'Checkout endet auf Rest 0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Verpasste Doppel: Marke in der Aufnahme, Doppelquote und Doppel im Überblick', (tester) async {
    await _open(tester);
    await _scrollTo(tester, const Key('session-leg-1'));
    // Ben verfehlt D10, Anna D18; jeder Dart zählt einmal.
    expect(find.descendant(of: find.byKey(const Key('leg-1-p0-v2')), matching: find.byKey(const Key('missed-double-D10'))), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('leg-1-p1-v2')), matching: find.byKey(const Key('missed-double-D18'))), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('leg-1-p0-v1')), matching: find.byType(Tooltip)), findsNothing,
        reason: 'ohne Doppel-Versuch keine Marke');
    expect(find.byKey(const Key('leg-1-doubles')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('leg-1-doubles')), matching: find.text('Doppel 1/2')), findsOneWidget);

    await _scrollTo(tester, const Key('session-doubles'));
    final summary = find.byKey(const Key('session-doubles'));
    expect(find.descendant(of: summary, matching: find.text('Doppelquote: 1 von 2 · 50,0 %')), findsNWidgets(2), reason: 'Ben und Anna');
    for (final chip in ['D10 0/1', 'D5 1/1', 'D18 0/1', 'D10 1/1']) {
      expect(find.descendant(of: summary, matching: find.text(chip)), findsWidgets, reason: chip);
    }
    expect(find.byKey(const Key('double-chip-5')), findsOneWidget);
    expect(find.text('Doppelquote: 1 von 2 · 50,0 %'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Leg-Auswahl: Alle Legs, einzelnes Leg und zurück', (tester) async {
    await _open(tester);
    await _scrollTo(tester, const Key('leg-picker'));
    expect(find.byKey(const Key('leg-pick-all')), findsOneWidget);
    expect(find.byKey(const Key('leg-pick-1')), findsOneWidget);
    expect(find.byKey(const Key('leg-pick-2')), findsOneWidget);
    // Alle Legs: beide Tabellen sind da (die zweite wird beim Scrollen gebaut).
    await _scrollTo(tester, const Key('session-leg-2'));
    expect(find.byKey(const Key('session-leg-2')), findsOneWidget);

    await _scrollTo(tester, const Key('leg-picker'));
    await tester.tap(find.byKey(const Key('leg-pick-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-leg-1')), findsNothing);
    expect(find.byKey(const Key('session-leg-2')), findsOneWidget);
    // Leg 2: Bens Bust steht rot als „Bust“, der Rest bleibt 101.
    final bust = find.byKey(const Key('leg-2-p0-v1'));
    await _scrollTo(tester, const Key('leg-2-p0-v1'));
    expect(find.descendant(of: bust, matching: find.text('Bust')), findsOneWidget);
    expect(find.descendant(of: bust, matching: find.text('101')), findsOneWidget);

    await _scrollTo(tester, const Key('leg-picker'));
    await tester.tap(find.byKey(const Key('leg-pick-all')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, const Key('session-leg-1'));
    expect(find.byKey(const Key('session-leg-1')), findsOneWidget);
  });

  testWidgets('Ältere Matches ohne Gegnerwürfe: nur der eigene Verlauf mit Hinweis, Doppelzeile ohne Gegner', (tester) async {
    await _open(tester, withOpponent: false);
    await _scrollTo(tester, const Key('session-leg-1'));
    expect(find.byKey(const Key('session-legs-note')), findsOneWidget);
    expect(find.byKey(const Key('leg-1-p1-v1')), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('session-leg-1')), matching: find.text('Anna')), findsNothing);
    await _scrollTo(tester, const Key('session-doubles'));
    expect(find.byKey(const Key('session-doubles-p0')), findsOneWidget);
    expect(find.byKey(const Key('session-doubles-p1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Training ohne Doppel-Versuche: keine Doppelzeile; Tabelle mit einer Spalte', (tester) async {
    final c = await pumpApp(tester, size: _phone);
    final me = await c.read(profileRepositoryProvider).resolve(null);
    final ids = await seedHistory(c.read(gameRepositoryProvider), me, DateTime.now());
    await tester.pumpAndSettle();
    c.read(routerProvider).go(Routes.session(ids.x01));
    await tester.pumpAndSettle();
    await _scrollTo(tester, const Key('session-leg-0'));
    expect(find.byKey(const Key('session-leg-0')), findsOneWidget);
    expect(find.byKey(const Key('leg-0-p1-v1')), findsNothing);
    expect(find.byKey(const Key('leg-0-p0-v1')), findsOneWidget);
    // Cricket hat keinen Aufnahmenverlauf mit Rest, die Aufnahmenliste bleibt.
    c.read(routerProvider).go(Routes.session(ids.cricket));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-leg-0')), findsNothing);
    await _scrollTo(tester, const Key('session-visits'));
    expect(tester.takeException(), isNull);
  });

  for (final look in ['tv', 'arena', 'clean', 'lab']) {
    for (final size in [_phone, _desktop]) {
      testWidgets('Look $look ${size.width.toInt()} px: Legs ohne Überlauf', (tester) async {
        await _open(tester, size: size, look: look);
        for (final key in ['session-doubles', 'leg-picker', 'session-leg-1', 'session-leg-1-chart', 'session-leg-2', 'leg-legend']) {
          await _scrollTo(tester, Key(key));
          expect(tester.takeException(), isNull, reason: key);
        }
        // Kein Text läuft aus seiner Zelle: jede Zelle ist so breit wie ihre Spalte.
        final cell = tester.getSize(find.byKey(const Key('leg-1-p0-v1')));
        expect(cell.width, greaterThan(100));
        expect(cell.width, lessThan(size.width / 2));
      });
    }
  }

  testWidgets('Lite zeigt den Aufnahmenverlauf ebenfalls, ohne Löschen', (tester) async {
    final (:c, :cloud, :ben) = await pumpLiteWithBen(tester, prepare: (ben) async {
      await seedHandMadeMatch(ben.device.games, await ben.device.me(), DateTime.now());
    });
    final rows = await tester.runAsync(() => c.read(appDatabaseProvider).select(c.read(appDatabaseProvider).sessions).get());
    final id = rows!.firstWhere((r) => r.gameId == matchGameId && r.configJson.contains('Anna')).id;
    c.read(routerProvider).go(Routes.session(id));
    await settleLite(tester, ms: 200);
    await _scrollTo(tester, const Key('session-leg-1'));
    expect(find.byKey(const Key('session-leg-1-chart')), findsOneWidget);
    expect(find.byKey(const Key('leg-1-p1-v1')), findsOneWidget, reason: 'Gegnerwürfe kommen über den Abgleich mit');
    expect(find.descendant(of: find.byKey(const Key('leg-1-p0-v2')), matching: find.byKey(const Key('missed-double-D10'))), findsOneWidget);
    expect(find.byKey(const Key('session-delete-action')), findsNothing);
    expect(find.byKey(const Key('session-delete')), findsNothing);
    await shutdownApp(tester, c);
  });

  testWidgets('Dart-Symbol: in jeder Größe, AppIcon wählt es über AppIcons.dart', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Wrap(children: [
          for (final s in [16.0, 18.0, 20.0, 24.0, 32.0, 48.0, 160.0]) DartIcon(size: s, color: Colors.white),
          const AppIcon(AppIcons.dart, size: 20),
          const AppIcon(Icons.adjust_rounded, size: 20),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(DartIcon), findsNWidgets(8));
    expect(tester.getSize(find.byType(DartIcon).first), const Size(16, 16));
    expect(find.byIcon(Icons.adjust_rounded), findsOneWidget);
  });

  testWidgets('Dart-Symbol: Spitze unten links, Flight oben rechts und bleibt im Quadrat', (tester) async {
    for (final size in [16, 20, 24, 48]) {
      final rec = ui.PictureRecorder();
      DartIconPainter(Colors.white).paint(ui.Canvas(rec), Size(size.toDouble(), size.toDouble()));
      final data = await tester.runAsync(() async {
        final img = await rec.endRecording().toImage(size, size);
        return img.toByteData();
      });
      final bytes = data!;
      int alpha(int x, int y) => bytes.getUint8((y * size + x) * 4 + 3);
      int mass(int x0, int y0, int x1, int y1) {
        var m = 0;
        for (var y = y0; y < y1; y++) {
          for (var x = x0; x < x1; x++) {
            m += alpha(x, y);
          }
        }
        return m;
      }

      final h = size ~/ 2;
      final reason = '$size px';
      // Leere Ecken: der Dart liegt auf der Diagonalen von unten links nach oben rechts.
      expect(mass(0, 0, size ~/ 4, size ~/ 4), 0, reason: 'oben links leer, $reason');
      expect(mass(size - size ~/ 4, size - size ~/ 4, size, size), 0, reason: 'unten rechts leer, $reason');
      // Spitze unten links, Flight oben rechts sind gezeichnet.
      expect(mass(0, h, h, size), greaterThan(0), reason: 'unten links, $reason');
      expect(mass(h, 0, size, h), greaterThan(0), reason: 'oben rechts, $reason');
      // Die Flight ist die größte Fläche des Darts (klassische Proportionen).
      expect(mass(h, 0, size, h), greaterThan(mass(0, h, h, size)), reason: 'Flight größer als der Spitzenteil, $reason');
    }
  });
}
