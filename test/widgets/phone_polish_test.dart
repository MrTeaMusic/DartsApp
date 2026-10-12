import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/matches/presentation/match_routes.dart';
import 'package:dartlab/features/matches/presentation/tournament_bracket.dart';
import 'package:dartlab/features/matches/presentation/tournament_controller.dart';
import 'package:dartlab/features/plans/presentation/plan_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

Future<void> frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Turnier mit festem Los (u. a. „Michael van Gerwen“ im Achtelfinale).
Future<void> createTournament(ProviderContainer c) => c
    .read(tournamentControllerProvider.notifier)
    .create(humanName: 'Ich', difficulty: 0.5, bestOf: const [3, 3, 5, 7], seed: 3);

void main() {
  test('Kurzform für Namen: Initiale des Vornamens und Rest', () {
    expect(shortPlayerName('Michael van Gerwen'), 'M. van Gerwen');
    expect(shortPlayerName('Dimitri Van den Bergh'), 'D. Van den Bergh');
    expect(shortPlayerName('  Luke   Littler '), 'L. Littler');
    expect(shortPlayerName('Ich'), 'Ich');
    expect(shortPlayerName('Élodie Durand'), 'É. Durand');
  });

  testWidgets('Turnierbaum am Telefon: lange Namen als Kurzform, voller Name im Tooltip', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844), prefs: {'settings.look': 'clean'});
    await createTournament(c);
    c.read(routerProvider).go(MatchRoutes.tournament);
    await tester.pumpAndSettle();

    expect(find.text('M. van Gerwen'), findsOneWidget);
    expect(find.text('Michael van Gerwen'), findsNothing);
    expect(find.byTooltip('Michael van Gerwen'), findsOneWidget);
    // Kurze Namen bleiben voll ausgeschrieben.
    expect(find.text('Ich'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Name im Baum: voll, wenn er passt, sonst Kurzform', (tester) async {
    Future<void> pumpName(double width) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            child: const BracketName('Michael van Gerwen', style: TextStyle(fontSize: 10)),
          ),
        ),
      ),
    );
    // Testschrift: jedes Zeichen so breit wie die Schriftgröße.
    await pumpName(400);
    expect(find.text('Michael van Gerwen'), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
    await pumpName(150);
    expect(find.text('M. van Gerwen'), findsOneWidget);
    expect(find.byTooltip('Michael van Gerwen'), findsOneWidget);
  });

  testWidgets('Turnierbaum scrollt nach einer beendeten Runde zur neuen Runde', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844), prefs: {'settings.look': 'clean'});
    await createTournament(c);
    // Ausgeschieden im Achtelfinale, Rest der Runde simuliert.
    final t = c.read(tournamentControllerProvider)!;
    final m = t.humanMatch!;
    final h = t.humanIndex;
    t.record(m, winner: m.a == h ? m.b! : m.a!, scoreA: m.a == h ? 1 : 2, scoreB: m.a == h ? 2 : 1);
    await c.read(tournamentControllerProvider.notifier).simulateRound();
    expect(t.currentRound, 1);

    c.read(routerProvider).go(MatchRoutes.tournament);
    await tester.pumpAndSettle();
    ScrollController scroll() =>
        tester.widget<SingleChildScrollView>(find.byKey(const Key('tournament-bracket-scroll'))).controller!;
    expect(scroll().offset, 0);
    final left = tester.getTopLeft(find.byKey(const Key('tournament-match-r0-m0'))).dx;

    await tester.tap(find.byKey(const Key('tournament-sim-round')));
    await tester.pumpAndSettle();
    expect(t.currentRound, 2);
    // Viertelfinale (Vorrunde) steht jetzt dort, wo vorher das Achtelfinale stand.
    expect(scroll().offset, greaterThan(100));
    expect(tester.getTopLeft(find.byKey(const Key('tournament-match-r1-m0'))).dx, moreOrLessEquals(left, epsilon: 1));
    expect(tester.takeException(), isNull);
  });

  for (final (width, full) in const [(390.0, true), (700.0, false)]) {
    testWidgets('„Spielen“ bei ${width.toInt()} px: ${full ? 'ganze Breite' : 'eigene Breite, rechtsbündig'}', (
      tester,
    ) async {
      final c = await pumpApp(tester, size: Size(width, 900), prefs: {'settings.look': 'clean'});
      await createTournament(c);
      c.read(routerProvider).go(MatchRoutes.tournament);
      await tester.pumpAndSettle();
      final play = tester.getRect(find.byKey(const Key('tournament-play')));
      if (full) {
        expect(play.width, greaterThan(width * 0.7));
      } else {
        expect(play.width, lessThan(320));
        expect(play.right, greaterThan(width * 0.8));
      }
    });
  }

  testWidgets('Plan für mich am Telefon: Schritt-Titel brechen auf zwei Zeilen um', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    c.read(routerProvider).go(PlanRoutes.auto);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('auto-plan-step-0')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final titles = find.descendant(
      of: find.byKey(const Key('auto-plan-step-0')),
      matching: find.byWidgetPredicate((w) => w is Text && w.maxLines == 2),
    );
    expect(titles, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: titles, matching: find.byType(RichText)),
    );
    // Zwei Zeilen statt einer gekürzten.
    final fontSize = paragraph.text.style!.fontSize!;
    expect(paragraph.size.height, greaterThan(fontSize * 1.5));
  });
}
