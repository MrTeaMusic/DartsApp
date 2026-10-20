import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/domain/games/bull_drill.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:dartlab/features/matches/presentation/match_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/darts.dart';
import '../helpers/pump_app.dart';

Future<void> frames(WidgetTester tester, [int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder inRow(String key, String text) => find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

/// Aufnahme-Zeilen werden nur aus den Aufzeichnungen abgeleitet: die Tests
/// geben Darts direkt in die Controller (wie eine Quelle es täte).
void main() {
  Future<ProviderContainer> startMatch(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    String look = 'tv',
    int players = 2,
    int start = 301,
    int legs = 2,
  }) async {
    final c = await pumpApp(tester, size: size, prefs: {'settings.look': look, 'settings.playView': 'look'});
    await c.read(matchControllerProvider.notifier).start(
      MatchSetup(
        format: MatchFormat(startScore: start, legsToWin: legs),
        players: [for (var i = 0; i < players; i++) MatchPlayer.human(['Ben', 'Gast', 'Anna'][i])],
      ),
    );
    c.read(routerProvider).go(MatchRoutes.play);
    await frames(tester);
    // Die Quelle meldet beim Start ein TurnReset: abwarten, bevor Darts kommen.
    await tester.pump();
    return c;
  }

  void throwDarts(ProviderContainer c, List<String> names, {bool takeout = false}) {
    final controller = c.read(matchControllerProvider.notifier);
    for (final n in names) {
      controller.handle(DartThrown(d(n)));
    }
    if (takeout) controller.handle(TakeoutFinished(DateTime.now()));
  }

  group('Match: Aufnahmen unter dem Namen', () {
    testWidgets('1 gegen 1: Zeilen erscheinen nach der Aufnahme, Startzeile zuerst', (tester) async {
      final c = await startMatch(tester);
      // Noch nichts geworfen: nur die Startzeile.
      for (final p in [0, 1]) {
        expect(find.byKey(Key('match-visits-$p')), findsOneWidget);
        expect(inRow('match-visits-$p-start', '301'), findsOneWidget);
      }
      // Eine laufende Aufnahme steht noch nicht in der Tabelle.
      throwDarts(c, ['T20', 'T20']);
      await tester.pump();
      expect(find.byKey(const Key('match-visits-0-row-0')), findsNothing);
      throwDarts(c, ['S5']);
      await tester.pump();
      expect(inRow('match-visits-0-row-0', '125'), findsOneWidget);
      expect(inRow('match-visits-0-row-0', '176'), findsOneWidget);
      // Der Rest der Karte stimmt mit der Tabelle überein.
      expect(tester.widget<Text>(find.byKey(const Key('match-remaining-0'))).data, '176');

      c.read(matchControllerProvider.notifier).handle(TakeoutFinished(DateTime.now()));
      throwDarts(c, ['S20', 'S1', 'S5'], takeout: true);
      await tester.pump();
      expect(inRow('match-visits-1-row-1', '26'), findsOneWidget);
      expect(inRow('match-visits-1-row-1', '275'), findsOneWidget);
      // Jeder Spieler hat seine eigene Tabelle.
      expect(find.byKey(const Key('match-visits-1-row-0')), findsNothing);
      expect(find.byKey(const Key('match-visits-0-row-1')), findsNothing);

      // Dritte Aufnahme des ersten Spielers: neueste Zeile oben.
      throwDarts(c, ['S20', 'S20', 'S19']);
      await tester.pump();
      final y2 = tester.getTopLeft(find.byKey(const Key('match-visits-0-row-2'))).dy;
      final y0 = tester.getTopLeft(find.byKey(const Key('match-visits-0-row-0'))).dy;
      expect(y2 < y0, isTrue);
      expect(inRow('match-visits-0-row-2', '117'), findsOneWidget);
    });

    testWidgets('Rückgängig nimmt die Zeile wieder zurück', (tester) async {
      final c = await startMatch(tester);
      throwDarts(c, ['T20', 'S20', 'S1']);
      await tester.pump();
      expect(inRow('match-visits-0-row-0', '81'), findsOneWidget);
      c.read(matchControllerProvider.notifier).undo();
      await tester.pump();
      expect(find.byKey(const Key('match-visits-0-row-0')), findsNothing);
      throwDarts(c, ['S2']);
      await tester.pump();
      expect(inRow('match-visits-0-row-0', '82'), findsOneWidget);
      expect(inRow('match-visits-0-row-0', '219'), findsOneWidget);
    });

    testWidgets('Korrektur eines Darts rechnet die Zeile neu', (tester) async {
      final c = await startMatch(tester);
      throwDarts(c, ['S20', 'S20', 'S20'], takeout: true);
      throwDarts(c, ['S1', 'S1', 'S1'], takeout: true);
      await tester.pump();
      expect(inRow('match-visits-0-row-0', '60'), findsOneWidget);
      c.read(matchControllerProvider.notifier).correct(0, Segment.triple(20));
      await tester.pump();
      expect(inRow('match-visits-0-row-0', '100'), findsOneWidget);
      expect(inRow('match-visits-0-row-0', '201'), findsOneWidget);
    });

    testWidgets('Bust: rote 0 mit Marke, Rest bleibt; Checkout: Zeile mit Pokal', (tester) async {
      final c = await startMatch(tester, start: 101, legs: 2);
      throwDarts(c, ['T20', 'S20', 'S1'], takeout: true); // 81, Rest 20
      throwDarts(c, ['S1', 'S1', 'S1'], takeout: true);
      throwDarts(c, ['S10', 'S15'], takeout: true); // Bust
      await tester.pump();
      expect(inRow('match-visits-0-row-2', '0'), findsOneWidget);
      expect(inRow('match-visits-0-row-2', '20'), findsOneWidget);
      expect(find.byKey(const Key('visit-bust-2')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('match-remaining-0'))).data, '20');

      throwDarts(c, ['S1', 'S1', 'S1'], takeout: true);
      throwDarts(c, ['S10', 'D5'], takeout: false); // Checkout der 20
      await tester.pump();
      expect(inRow('match-visits-0-row-4', '20'), findsWidgets);
      expect(
        find.descendant(of: find.byKey(const Key('match-visits-0-row-4')), matching: find.byIcon(Icons.emoji_events_rounded)),
        findsOneWidget,
      );
      // Das Leg ist gewonnen, die Tabelle zeigt es weiter, die Karten stehen wieder auf 101.
      expect(tester.widget<Text>(find.byKey(const Key('match-remaining-0'))).data, '101');
      expect(find.byKey(const Key('match-visits-0-row-4')), findsOneWidget);
      // Erster Dart im nächsten Leg: die Tabelle beginnt von vorn.
      c.read(matchControllerProvider.notifier).handle(TakeoutFinished(DateTime.now()));
      throwDarts(c, ['T20', 'S1', 'S1']);
      await tester.pump();
      expect(find.byKey(const Key('match-visits-0-row-4')), findsNothing);
      expect(find.byKey(const Key('match-visits-1-row-5')), findsOneWidget);
      expect(inRow('match-visits-0-start', '101'), findsOneWidget);
    });

    for (final look in ['tv', 'clean', 'lab']) {
      testWidgets('drei Spieler auf dem Telefon ($look): kein Überlauf', (tester) async {
        final c = await startMatch(tester, look: look, players: 3);
        throwDarts(c, ['T20', 'T20', 'T20'], takeout: true);
        throwDarts(c, ['S1', 'S1', 'S1'], takeout: true);
        throwDarts(c, ['S19', 'S19', 'S19'], takeout: true);
        throwDarts(c, ['T20', 'S1', 'S1'], takeout: true);
        throwDarts(c, ['T20', 'S1'], takeout: true);
        await tester.pump();
        for (var p = 0; p < 3; p++) {
          expect(find.byKey(Key('match-visits-$p')), findsOneWidget);
        }
        expect(inRow('match-visits-0-row-0', '180'), findsOneWidget);
        expect(inRow('match-visits-0-row-3', '62'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('nach dem Match: Telefon behält die Tabellen, breit zeigt dafür die Ergebnis-Karte', (tester) async {
      final c = await startMatch(tester, start: 101, legs: 1);
      throwDarts(c, ['T20', 'S9', 'D16']);
      await frames(tester);
      expect(c.read(matchControllerProvider)!.ended, isTrue);
      expect(inRow('match-visits-0-row-0', '101'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('match-visits-0-row-0')), matching: find.byIcon(Icons.emoji_events_rounded)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('nach dem Match breit: Knöpfe ohne Scrollen sichtbar', (tester) async {
      final c = await startMatch(tester, size: const Size(1280, 900), start: 101, legs: 1);
      throwDarts(c, ['T20', 'S9', 'D16']);
      await frames(tester);
      expect(c.read(matchControllerProvider)!.ended, isTrue);
      expect(find.byKey(const Key('match-visits-0')), findsNothing);
      expect(find.byKey(const Key('match-final-score')), findsOneWidget);
      expect(tester.getRect(find.byKey(const Key('match-done'))).bottom, lessThanOrEqualTo(900));
    });

    testWidgets('breit (1440x900): beide Tabellen neben dem Board', (tester) async {
      final c = await startMatch(tester, size: const Size(1440, 900));
      throwDarts(c, ['T20', 'T20', 'S5'], takeout: true);
      throwDarts(c, ['S20', 'S1', 'S5'], takeout: true);
      await tester.pump();
      expect(inRow('match-visits-0-row-0', '125'), findsOneWidget);
      expect(inRow('match-visits-1-row-1', '26'), findsOneWidget);
      expect(find.byKey(const Key('match-board')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('breit (1440x900) mit Doppel-Zoom: Rückgängig/Weiter bleiben ohne Scrollen sichtbar', (tester) async {
      final c = await startMatch(tester, size: const Size(1440, 900), start: 101);
      throwDarts(c, ['T20', 'S19', 'S20'], takeout: true); // Ben: 2 Rest
      throwDarts(c, ['T20', 'S19', 'S20'], takeout: true); // Gast: 2 Rest
      await tester.pump();
      expect(find.byKey(const Key('double-zoom')), findsOneWidget);
      for (final key in ['match-undo', 'match-next', 'match-corrections']) {
        expect(tester.getRect(find.byKey(Key(key))).bottom, lessThanOrEqualTo(900), reason: key);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('X01-Solo: Aufnahmen im Stand', () {
    Future<ProviderContainer> startSolo(WidgetTester tester, {Size size = const Size(390, 844), String look = 'tv'}) async {
      final c = await pumpApp(tester, size: size, prefs: {'settings.look': look, 'settings.playView': 'look'});
      await c.read(activeGameProvider.notifier).start(X01Solo.definition, {'startScore': 101, 'legs': 1}, seed: 1);
      c.read(routerProvider).go(Routes.play);
      await frames(tester);
      await tester.pump();
      return c;
    }

    void soloDarts(ProviderContainer c, List<String> names, {bool takeout = false}) {
      final controller = c.read(activeGameProvider.notifier);
      for (final n in names) {
        controller.handle(DartThrown(d(n)));
      }
      if (takeout) controller.handle(TakeoutFinished(DateTime.now()));
    }

    testWidgets('Zeilen mit Punkten, Darts und Rest; Rückgängig nimmt sie zurück', (tester) async {
      final c = await startSolo(tester);
      expect(find.byKey(const Key('solo-visits')), findsOneWidget);
      expect(inRow('solo-visits-start', '101'), findsOneWidget);
      soloDarts(c, ['T20', 'S20', 'S1']);
      await tester.pump();
      expect(inRow('solo-visits-row-0', '81'), findsOneWidget);
      expect(inRow('solo-visits-row-0', '20'), findsOneWidget);
      final darts = tester.widget<RichText>(
        find.descendant(of: find.byKey(const Key('solo-visits-row-0')), matching: find.byType(RichText)).at(1),
      );
      expect(darts.text.toPlainText().replaceAll(RegExp(r'\s+'), ' '), 'T20 · S20 · S1');

      c.read(activeGameProvider.notifier).undo();
      await tester.pump();
      expect(find.byKey(const Key('solo-visits-row-0')), findsNothing);
      soloDarts(c, ['S2']);
      await tester.pump();
      expect(inRow('solo-visits-row-0', '82'), findsOneWidget);
      expect(inRow('solo-visits-row-0', '19'), findsOneWidget);
    });

    testWidgets('Bust und Checkout im Solo', (tester) async {
      final c = await startSolo(tester);
      soloDarts(c, ['T20', 'S20', 'S1'], takeout: true); // 20 Rest
      soloDarts(c, ['S10', 'S15'], takeout: true); // Bust
      soloDarts(c, ['S10', 'D5']); // Checkout
      await tester.pump();
      expect(inRow('solo-visits-row-1', '0'), findsOneWidget);
      expect(find.byKey(const Key('visit-bust-1')), findsOneWidget);
      expect(inRow('solo-visits-row-2', '20'), findsWidgets);
      expect(
        find.descendant(of: find.byKey(const Key('solo-visits-row-2')), matching: find.byIcon(Icons.emoji_events_rounded)),
        findsOneWidget,
      );
      expect(c.read(activeGameProvider)!.ended, isTrue);
    });

    for (final look in ['tv', 'clean', 'lab']) {
      for (final size in [const Size(390, 844), const Size(1440, 900)]) {
        testWidgets('${size.width.toInt()} breit ($look): kein Überlauf', (tester) async {
          final c = await startSolo(tester, size: size, look: look);
          soloDarts(c, ['T20', 'T20', 'S5'], takeout: true);
          soloDarts(c, ['S20', 'T19', 'S20'], takeout: true);
          soloDarts(c, ['S1', 'S1', 'S1'], takeout: true);
          await tester.pump();
          expect(find.byKey(const Key('solo-visits-row-2')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('breit (1440x900) mit Doppel-Zoom: Knöpfe bleiben ohne Scrollen sichtbar', (tester) async {
      final c = await startSolo(tester, size: const Size(1440, 900));
      soloDarts(c, ['T20', 'S19', 'S20'], takeout: true); // 2 Rest
      await tester.pump();
      expect(find.byKey(const Key('double-zoom')), findsOneWidget);
      for (final key in ['game-undo', 'game-next', 'end-game']) {
        expect(tester.getRect(find.byKey(Key(key))).bottom, lessThanOrEqualTo(900), reason: key);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('andere Trainingsspiele haben keine Tabelle', (tester) async {
      final c = await pumpApp(tester);
      await c.read(activeGameProvider.notifier).start(BullDrill.definition, const {}, seed: 1);
      c.read(routerProvider).go(Routes.play);
      await frames(tester);
      expect(find.byKey(const Key('solo-visits')), findsNothing);
    });
  });
}
