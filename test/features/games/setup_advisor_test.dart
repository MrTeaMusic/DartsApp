import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/games/domain/games/checkout/setup_advisor.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/x01_match.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

List<String> names(SetupPlan p) => [for (final s in p.darts) s.name];

void main() {
  group('SetupAdvisor', () {
    test('kein Vorschlag, solange ein Finish geht', () {
      expect(SetupAdvisor.suggest(170, darts: 3, out: OutMode.double), isNull);
      expect(SetupAdvisor.suggest(100, darts: 2, out: OutMode.double), isNull);
      expect(SetupAdvisor.suggest(40, darts: 1, out: OutMode.double), isNull);
    });

    test('Klassiker: auf ein Lieblings-Double stellen', () {
      final p169 = SetupAdvisor.suggest(169, darts: 3, out: OutMode.double)!;
      expect(names(p169), ['T20', 'T20', 'S17']);
      expect(p169.leave, 32);

      final p120 = SetupAdvisor.suggest(120, darts: 2, out: OutMode.double)!;
      expect(names(p120), ['T20', 'S20']);
      expect(p120.leave, 40);

      final p41 = SetupAdvisor.suggest(41, darts: 1, out: OutMode.double)!;
      expect(names(p41), ['S9']);
      expect(p41.leave, 32);

      expect(SetupAdvisor.suggest(3, darts: 1, out: OutMode.double)!.leave, 2);
    });

    test('Bogey-Reste werden umgangen, über 170 wird auf ein kurzes Finish gestellt', () {
      expect(names(SetupAdvisor.suggest(159, darts: 3, out: OutMode.double)!), ['T20', 'T20', 'S7']);
      final p = SetupAdvisor.suggest(230, darts: 3, out: OutMode.double)!;
      expect(names(p), ['T20', 'T20', 'T20']);
      expect(p.leave, 50);
      expect(SetupAdvisor.suggest(200, darts: 2, out: OutMode.double)!.leave, 80);
    });

    test('reines Punkten (es bleibt höchstens ein Drei-Dart-Finish): kein Vorschlag', () {
      expect(SetupAdvisor.suggest(301, darts: 3, out: OutMode.double), isNull);
      expect(SetupAdvisor.suggest(351, darts: 3, out: OutMode.double), isNull);
      expect(SetupAdvisor.suggest(501, darts: 3, out: OutMode.double), isNull);
    });

    test('jeder Vorschlag lässt einen checkbaren Rest ohne Bust', () {
      for (final out in OutMode.values) {
        for (var darts = 1; darts <= 3; darts++) {
          for (var r = 2; r <= 170 + 60 * darts; r++) {
            final p = SetupAdvisor.suggest(r, darts: darts, out: out);
            if (p == null) continue;
            expect(p.darts.length, darts);
            expect(r - p.darts.fold(0, (a, s) => a + s.score), p.leave);
            expect(p.leave, greaterThanOrEqualTo(out == OutMode.straight ? 1 : 2), reason: '$r/$darts $out');
            if (r - 60 * darts <= 110) {
              expect(CheckoutRules.isCheckout(p.leave, darts: 3, out: out), isTrue, reason: '$r/$darts $out → ${p.leave}');
            }
          }
        }
      }
    });
  });

  group('X01 Solo', () {
    test('Stell-Vorschlag erscheint, sobald kein Finish mehr geht', () {
      final g = X01Solo(seed: 1, startScore: 169)..prepare();
      expect(g.display.suggestion, isNull);
      expect(g.display.setup!.leave, 32);
      g.throwDart(d('T20'));
      // 109 mit zwei Darts: auf 32 stellen.
      expect(g.display.suggestion, isNull);
      expect(names(g.display.setup!), ['T20', 'S17']);
      expect(g.display.setup!.leave, 32);
    });

    test('kein Stell-Vorschlag, wenn ein Checkout geht oder Vorschläge aus sind', () {
      final g = X01Solo(seed: 1, startScore: 121)..prepare();
      expect(g.display.suggestion, isNotNull);
      expect(g.display.setup, isNull);
      final off = X01Solo(seed: 1, startScore: 169, showSuggestion: false)..prepare();
      expect(off.display.setup, isNull);
    });
  });

  test('Match: Stell-Vorschlag für den Spieler am Zug', () {
    final m = X01Match(format: const MatchFormat(startScore: 169, legsToWin: 1), playerCount: 2);
    expect(m.suggestion, isNull);
    expect(m.setup!.leave, 32);
    expect(m.setup!.darts.first, Segment.triple(20));
  });
}
