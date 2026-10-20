import 'package:dartlab/core/design/app_theme.dart';
import 'package:dartlab/core/design/components/components.dart';
import 'package:dartlab/core/design/dart_look.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/matches/domain/visit_history.dart';
import 'package:dartlab/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

VisitRow row(int visit, int points, int remaining, {bool bust = false, bool checkout = false, List<String>? darts}) =>
    VisitRow(
      player: 0,
      leg: 1,
      visit: visit,
      darts: [for (final n in darts ?? ['S20']) Segment.tryParse(n)!],
      points: points,
      remaining: remaining,
      bust: bust,
      checkout: checkout,
    );

Widget host(DartLookId look, Widget child, {double width = 200, Brightness brightness = Brightness.dark}) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppTheme.build(look, brightness),
  home: Scaffold(
    body: Center(child: SizedBox(width: width, child: child)),
  ),
);

Finder inRow(String key, String text) => find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

void main() {
  for (final look in DartLookId.values) {
    group('VisitTable (${look.name})', () {
      testWidgets('zeigt Aufnahmen, neueste oben, Startzeile unten', (tester) async {
        await tester.pumpWidget(
          host(look, VisitTable(rows: [row(0, 60, 441), row(1, 125, 316)], startScore: 501)),
        );
        expect(find.byKey(const Key('visits')), findsOneWidget);
        expect(inRow('visits-row-0', '60'), findsOneWidget);
        expect(inRow('visits-row-0', '441'), findsOneWidget);
        expect(inRow('visits-row-1', '125'), findsOneWidget);
        expect(inRow('visits-row-1', '316'), findsOneWidget);
        expect(inRow('visits-start', '501'), findsOneWidget);
        // Neueste zuerst: die Zeile der zweiten Aufnahme steht über der ersten.
        final y1 = tester.getTopLeft(find.byKey(const Key('visits-row-1'))).dy;
        final y0 = tester.getTopLeft(find.byKey(const Key('visits-row-0'))).dy;
        final ys = tester.getTopLeft(find.byKey(const Key('visits-start'))).dy;
        expect(y1 < y0 && y0 < ys, isTrue);
      });

      testWidgets('ohne Aufnahmen nur die Startzeile, Höhe bleibt gleich', (tester) async {
        await tester.pumpWidget(host(look, const VisitTable(rows: [], startScore: 301, maxRows: 5)));
        expect(find.byKey(const Key('visits-start')), findsOneWidget);
        final empty = tester.getSize(find.byKey(const Key('visits')));
        await tester.pumpWidget(
          host(look, VisitTable(rows: [row(0, 60, 241), row(1, 60, 181)], startScore: 301, maxRows: 5)),
        );
        expect(tester.getSize(find.byKey(const Key('visits'))), empty);
        final context = tester.element(find.byKey(const Key('visits')));
        expect(empty.height, VisitTable.heightFor(context.look, 5));
      });

      testWidgets('zu viele Aufnahmen: die ältesten fallen heraus, Startzeile auch', (tester) async {
        final rows = [for (var i = 0; i < 8; i++) row(i, 41, 501 - 41 * (i + 1))];
        await tester.pumpWidget(host(look, VisitTable(rows: rows, startScore: 501, maxRows: 5)));
        for (var i = 7; i >= 3; i--) {
          expect(find.byKey(Key('visits-row-$i')), findsOneWidget, reason: 'Aufnahme $i');
        }
        for (var i = 0; i < 3; i++) {
          expect(find.byKey(Key('visits-row-$i')), findsNothing, reason: 'Aufnahme $i');
        }
        expect(find.byKey(const Key('visits-start')), findsNothing);
      });

      testWidgets('Bust: rote 0 mit Bust-Marke, Rest unverändert', (tester) async {
        await tester.pumpWidget(
          host(look, VisitTable(rows: [row(0, 60, 441), row(1, 0, 441, bust: true)], startScore: 501)),
        );
        expect(inRow('visits-row-1', '0'), findsOneWidget);
        expect(inRow('visits-row-1', '441'), findsOneWidget);
        expect(find.byKey(const Key('visit-bust-1')), findsOneWidget);
        expect(find.byKey(const Key('visit-bust-0')), findsNothing);
      });

      testWidgets('dense: ohne Bust-Marke, aber mit roter 0', (tester) async {
        await tester.pumpWidget(
          host(look, VisitTable(rows: [row(0, 0, 441, bust: true)], startScore: 501, dense: true), width: 90),
        );
        expect(find.byKey(const Key('visit-bust-0')), findsNothing);
        expect(inRow('visits-row-0', '0'), findsOneWidget);
      });

      testWidgets('Checkout: Zeile mit Rest 0 und Pokal', (tester) async {
        await tester.pumpWidget(
          host(look, VisitTable(rows: [row(0, 60, 41), row(1, 41, 0, checkout: true)], startScore: 101)),
        );
        expect(inRow('visits-row-1', '41'), findsOneWidget);
        expect(inRow('visits-row-1', '0'), findsOneWidget);
        expect(
          find.descendant(of: find.byKey(const Key('visits-row-1')), matching: find.byIcon(Icons.emoji_events_rounded)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: find.byKey(const Key('visits-row-0')), matching: find.byIcon(Icons.emoji_events_rounded)),
          findsNothing,
        );
      });

      testWidgets('Darts-Spalte zeigt die einzelnen Felder', (tester) async {
        await tester.pumpWidget(
          host(
            look,
            VisitTable(
              rows: [
                row(0, 66, 435, darts: ['T20', 'S5', 'S1']),
              ],
              startScore: 501,
              showDarts: true,
            ),
            width: 360,
          ),
        );
        final text = tester.widget<RichText>(
          find.descendant(of: find.byKey(const Key('visits-row-0')), matching: find.byType(RichText)).at(1),
        );
        expect(text.text.toPlainText(), contains('T20'));
        expect(text.text.toPlainText(), contains('S5'));
        expect(text.text.toPlainText(), contains('S1'));
      });

      testWidgets('schmal und mit Bust, Checkout und 100+ ohne Überlauf', (tester) async {
        final rows = [
          row(0, 140, 361),
          row(1, 0, 361, bust: true),
          row(2, 361, 0, checkout: true),
        ];
        for (final width in [70.0, 90.0, 140.0, 260.0]) {
          await tester.pumpWidget(host(look, VisitTable(rows: rows, startScore: 501, dense: width < 100), width: width));
          expect(tester.takeException(), isNull, reason: 'Breite $width');
        }
      });

      testWidgets('hell und dunkel', (tester) async {
        if (!look.supportsLight) return;
        for (final b in Brightness.values) {
          await tester.pumpWidget(host(look, VisitTable(rows: [row(0, 60, 441)], startScore: 501), brightness: b));
          expect(find.byKey(const Key('visits-row-0')), findsOneWidget);
        }
      });
    });
  }
}
