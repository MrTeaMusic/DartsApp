import 'package:dartlab/core/design/arena/arena_palette.dart';
import 'package:dartlab/core/design/arena/arena_screen.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
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

const phone = Size(390, 844);
const tablet = Size(1180, 820);
const desktop = Size(1440, 900);
const fullHd = Size(1920, 1080);

/// Die Arena ist die Standard-Spielansicht; ohne Einstellung wird sie gezeigt.
void main() {
  Future<ProviderContainer> startMatch(
    WidgetTester tester, {
    Size size = desktop,
    int players = 2,
    int start = 501,
    int legs = 3,
    Map<String, Object> prefs = const {},
  }) async {
    final c = await pumpApp(tester, size: size, prefs: prefs);
    await c.read(matchControllerProvider.notifier).start(
      MatchSetup(
        format: MatchFormat(startScore: start, legsToWin: legs),
        players: [for (var i = 0; i < players; i++) MatchPlayer.human(['Ben', 'Gast', 'Anna', 'Tom'][i])],
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

  group('Einstellung', () {
    test('PlayView.byName: bekannte Namen, sonst Arena', () {
      expect(PlayView.byName('look'), PlayView.look);
      expect(PlayView.byName('arena'), PlayView.arena);
      expect(PlayView.byName(null), PlayView.arena);
      expect(PlayView.byName('quatsch'), PlayView.arena);
    });

    testWidgets('Standard ist Arena; Umschalten wird gespeichert', (tester) async {
      final c = await pumpApp(tester);
      expect(c.read(settingsProvider).playView, PlayView.arena);
      c.read(routerProvider).go(Routes.settings);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('playview-selector')), 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playview-hint')), findsOneWidget);
      await tester.tap(find.text('Wie das gewählte Design'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).playView, PlayView.look);
      expect(c.read(sharedPreferencesProvider).getString('settings.playView'), 'look');
    });

    testWidgets('Gespeicherte Wahl "look": die bisherige Ansicht mit Aufnahmen-Tabelle', (tester) async {
      await startMatch(tester, prefs: {'settings.playView': 'look'});
      expect(find.byKey(const Key('match-visits-0')), findsOneWidget);
      expect(find.byType(ArenaScreen), findsNothing);
    });
  });

  group('Match in der Arena', () {
    testWidgets('1 gegen 1 (1440x900): Maße wie im Vorbild, Startzeile zuerst', (tester) async {
      await startMatch(tester);
      expect(find.byType(ArenaScreen), findsOneWidget);
      final left = tester.getRect(find.byKey(const Key('match-active-0-true')));
      final right = tester.getRect(find.byKey(const Key('match-active-1-false')));
      expect(left.width / desktop.width, closeTo(0.265, 0.01));
      expect(right.width / desktop.width, closeTo(0.265, 0.01));
      expect(left.height / desktop.height, closeTo(0.687, 0.02));
      // Tafeln sitzen links und rechts, in der Mitte steht das Board.
      expect(left.left, lessThan(30));
      expect(right.right, greaterThan(desktop.width - 30));
      final board = tester.getRect(find.byKey(const Key('match-board')));
      expect(board.center.dx, closeTo(desktop.width / 2, 2));
      expect(board.left, greaterThan(left.right));
      expect(board.right, lessThan(right.left));
      // Leer: nur die Startzeile mit 501.
      for (final p in [0, 1]) {
        expect(inRow('match-visits-$p-start', '501'), findsOneWidget);
        expect(find.byKey(Key('match-visits-$p-row-0')), findsNothing);
        expect(tester.widget<Text>(find.byKey(Key('match-remaining-$p'))).data, '501');
      }
      expect(find.byKey(const Key('match-undo')), findsOneWidget);
      expect(find.byKey(const Key('match-next')), findsOneWidget);
      expect(find.byKey(const Key('leave-match')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Zeilen erscheinen, Rückgängig nimmt sie zurück, Bust ist markiert', (tester) async {
      final c = await startMatch(tester, start: 101);
      throwDarts(c, ['T20', 'S20', 'S1']);
      await tester.pump();
      expect(inRow('match-visits-0-row-0', '81'), findsOneWidget);
      expect(inRow('match-visits-0-row-0', '20'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('match-remaining-0'))).data, '20');
      expect(tester.widget<Text>(find.byKey(const Key('match-visits-0-last'))).data, '81');

      c.read(matchControllerProvider.notifier).undo();
      await tester.pump();
      expect(find.byKey(const Key('match-visits-0-row-0')), findsNothing);
      throwDarts(c, ['S1'], takeout: true); // Rückgängig nahm nur den letzten Dart
      throwDarts(c, ['S1', 'S1', 'S1'], takeout: true);
      throwDarts(c, ['S10', 'S15'], takeout: true); // Bust (20 Rest)
      await tester.pump();
      expect(inRow('match-visits-0-row-2', '0'), findsOneWidget);
      expect(find.byKey(const Key('visit-bust-2')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('match-remaining-0'))).data, '20');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Neuere Zeilen stehen unten, bei vielen Aufnahmen bleibt die Tabelle im Rahmen', (tester) async {
      final c = await startMatch(tester, start: 9999, legs: 2);
      for (var i = 0; i < 14; i++) {
        throwDarts(c, ['S20', 'S20', 'S20'], takeout: true);
        throwDarts(c, ['S1', 'S1', 'S1'], takeout: true);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Die letzte Zeile ist da, die älteste ist aus dem Bild gerutscht.
      expect(find.byKey(const Key('match-visits-0-row-26')), findsOneWidget);
      expect(find.byKey(const Key('match-visits-0-start')), findsNothing);
      final panel = tester.getRect(find.byKey(const Key('match-active-0-true')));
      expect(tester.getRect(find.byKey(const Key('match-visits-0-row-26'))).bottom, lessThanOrEqualTo(panel.bottom));
    });

    for (final size in [phone, tablet, desktop, fullHd]) {
      for (final players in [2, 3]) {
        testWidgets('${size.width.toInt()}x${size.height.toInt()} mit $players Spielern: kein Überlauf, alles sichtbar', (tester) async {
          final c = await startMatch(tester, size: size, players: players);
          throwDarts(c, ['T20', 'T19', 'S5'], takeout: true);
          throwDarts(c, ['S1', 'S1', 'S1']);
          await tester.pump();
          expect(tester.takeException(), isNull);
          for (var i = 0; i < players; i++) {
            expect(find.byKey(Key('match-remaining-$i')), findsOneWidget);
            final r = tester.getRect(find.byKey(Key('match-remaining-$i')));
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(size.width));
          }
          // Board und Schalter liegen im Bild (Telefon darf scrollen).
          final board = tester.getRect(find.byKey(const Key('match-board')));
          expect(board.width, greaterThan(180));
          expect(board.left, greaterThanOrEqualTo(0));
          expect(board.right, lessThanOrEqualTo(size.width));
          if (size != phone) {
            expect(board.bottom, lessThanOrEqualTo(size.height));
            expect(tester.getRect(find.byKey(const Key('match-undo'))).bottom, lessThanOrEqualTo(size.height));
          }
        });
      }
    }

    testWidgets('3 Spieler am Rechner: Tafeln links und rechts übereinander', (tester) async {
      await startMatch(tester, players: 3);
      final a = tester.getRect(find.byKey(const Key('match-active-0-true')));
      final b = tester.getRect(find.byKey(const Key('match-active-1-false')));
      final c3 = tester.getRect(find.byKey(const Key('match-active-2-false')));
      // Links ein Spieler, rechts zwei übereinander.
      expect(a.left, lessThan(desktop.width / 2));
      expect(b.left, greaterThan(desktop.width / 2));
      expect(c3.left, greaterThan(desktop.width / 2));
      expect(c3.top, greaterThan(b.top));
    });

    testWidgets('Am Telefon stehen zwei Tafeln nebeneinander über dem Board', (tester) async {
      await startMatch(tester, size: phone);
      final a = tester.getRect(find.byKey(const Key('match-active-0-true')));
      final b = tester.getRect(find.byKey(const Key('match-active-1-false')));
      expect(a.top, closeTo(b.top, 1));
      expect(b.left, greaterThan(a.right - 1));
      expect(tester.getRect(find.byKey(const Key('match-board'))).top, greaterThan(a.bottom));
    });

    testWidgets('Leg gewonnen und Match zu Ende: Ergebnis statt Board', (tester) async {
      final c = await startMatch(tester, start: 40, legs: 1);
      throwDarts(c, ['D20']);
      await tester.pump();
      await frames(tester, 12);
      expect(tester.takeException(), isNull);
      expect(c.read(matchControllerProvider)!.ended, isTrue);
      expect(find.byKey(const Key('match-done')), findsOneWidget);
    });
  });

  group('X01-Solo in der Arena', () {
    Future<ProviderContainer> startSolo(WidgetTester tester, {Size size = desktop}) async {
      final c = await pumpApp(tester, size: size);
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

    testWidgets('Eine Tafel links, rechte Seite leer; Zeilen und Rückgängig', (tester) async {
      final c = await startSolo(tester);
      expect(find.byType(ArenaScreen), findsOneWidget);
      final panel = tester.getRect(find.byKey(const Key('solo-remaining')));
      expect(panel.center.dx, lessThan(desktop.width / 2));
      expect(find.byKey(const Key('solo-visits-start')), findsOneWidget);
      soloDarts(c, ['T20', 'S20', 'S1']);
      await tester.pump();
      expect(inRow('solo-visits-row-0', '81'), findsOneWidget);
      expect(inRow('solo-visits-row-0', '20'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('solo-remaining'))).data, '20');
      c.read(activeGameProvider.notifier).undo();
      await tester.pump();
      expect(find.byKey(const Key('solo-visits-row-0')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final size in [phone, tablet, fullHd]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}: kein Überlauf', (tester) async {
        final c = await startSolo(tester, size: size);
        soloDarts(c, ['T20', 'T20', 'S5'], takeout: true);
        soloDarts(c, ['S1']);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('solo-remaining')), findsOneWidget);
      });
    }

    testWidgets('Am Telefon füllt die einzelne Tafel die Breite', (tester) async {
      await startSolo(tester, size: phone);
      final r = tester.getRect(find.byKey(const Key('solo-remaining')));
      expect(r.center.dx, closeTo(phone.width / 2, 40));
    });
  });

  group('ArenaScreen', () {
    test('isWide: Querformat ab 5:4 und 640 px Breite', () {
      expect(ArenaScreen.isWide(const Size(1440, 900)), isTrue);
      expect(ArenaScreen.isWide(const Size(1180, 820)), isTrue);
      expect(ArenaScreen.isWide(const Size(390, 844)), isFalse);
      expect(ArenaScreen.isWide(const Size(820, 1180)), isFalse);
      expect(ArenaScreen.isWide(const Size(800, 700)), isFalse);
      expect(ArenaScreen.isWide(const Size(600, 300)), isFalse);
    });

    test('Palette: Werte aus dem Vorbild', () {
      expect(ArenaPalette.background, const Color(0xFF001137));
      expect(ArenaPalette.surface, const Color(0xFF17181C));
      expect(ArenaPalette.gradientStart, const Color(0xFF802E90));
      expect(ArenaPalette.gradientEnd, const Color(0xFFD63756));
      // Das Schema nutzt ein helleres Blau (Kontrast auf #17181C); Schalter setzen ArenaPalette.blue selbst.
      expect(ArenaPalette.theme.colorScheme.primary, const Color(0xFF1F6BFF));
      expect(identical(ArenaPalette.theme, ArenaPalette.theme), isTrue);
    });
  });
}
