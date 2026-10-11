import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/games/domain/engine/game_session.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/domain/games/catch_40.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_calculator.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/games/domain/games/doubles_420.dart';
import 'package:dartlab/features/games/domain/games/doubles_ladder.dart';
import 'package:dartlab/features/games/domain/games/exact_score.dart';
import 'package:dartlab/features/games/domain/games/frustration.dart';
import 'package:dartlab/features/games/domain/games/golf.dart';
import 'package:dartlab/features/games/domain/games/halve_it.dart';
import 'package:dartlab/features/games/domain/games/jdc_challenge.dart';
import 'package:dartlab/features/games/domain/games/setup_shot.dart';
import 'package:dartlab/features/games/domain/games/shanghai.dart';
import 'package:dartlab/features/games/domain/games/switch_drill.dart';
import 'package:dartlab/features/games/domain/games/three_in_a_bed.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:dartlab/features/stats/domain/game_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

bool hasEvent(List<GameEvent> events, GameEventType t) => events.any((e) => e.type == t);

void main() {
  group('CheckoutRules', () {
    test('Bust-Regeln je Out-Modus', () {
      final t20 = Segment.triple(20);
      expect(CheckoutRules.isBust(40, t20, OutMode.double), isTrue);
      expect(CheckoutRules.isBust(41, Segment.single(20), OutMode.double), isFalse);
      expect(CheckoutRules.isBust(21, Segment.single(20), OutMode.double), isTrue, reason: 'Rest 1');
      expect(CheckoutRules.isBust(21, Segment.single(20), OutMode.master), isTrue, reason: 'Rest 1');
      expect(CheckoutRules.isBust(21, Segment.single(20), OutMode.straight), isFalse);
      expect(CheckoutRules.isBust(60, t20, OutMode.master), isFalse);
      expect(CheckoutRules.isBust(60, t20, OutMode.double), isTrue);
      expect(CheckoutRules.isBust(20, Segment.single(20), OutMode.straight), isFalse);
      expect(CheckoutRules.isBust(50, Segment.bull, OutMode.double), isFalse);
    });

    test('Master-Out-Vorschlag erlaubt Triple als letzten Dart', () {
      expect(CheckoutCalculator.suggest(60, darts: 1, doubleOut: true), isNull);
      expect(CheckoutRules.suggest(60, darts: 1, out: OutMode.master), [Segment.triple(20)]);
      expect(CheckoutRules.suggest(1, darts: 3, out: OutMode.master), isNull);
      // Double-Out bleibt unverändert.
      expect(CheckoutCalculator.suggest(40, darts: 1), [Segment.double(20)]);
    });
  });

  group('X01-Solo', () {
    test('9-Darter mit Double-Out', () {
      final g = X01Solo(seed: 1)..prepare();
      throwAll(g, ['T20', 'T20', 'T20', 'T20', 'T20', 'T20', 'T20', 'T19', 'D12']);
      expect(hasEvent(g.events, GameEventType.checkout), isTrue);
      expect(g.finished, isTrue);
      expect(g.result.metrics['darts'], 9);
      expect(g.result.metrics['average'], 167.0);
      expect(g.result.metrics['bestLegDarts'], 9);
      expect(g.result.metrics['highestFinish'], 141);
      expect(g.result.metrics['count180'], 2);
      expect(g.result.metrics['count140'], 1);
      expect(g.result.metrics['first9Average'], 167.0);
    });

    test('Bust über 0', () {
      final g = X01Solo(seed: 1, startScore: 40)..prepare();
      g.throwDart(d('T20'));
      expect(g.remaining, 40);
      expect(hasEvent(g.events, GameEventType.bust), isTrue);
      expect(g.visitClosed, isTrue);
      g.throwDart(d('S1'));
      expect(g.ignoredDarts, 1);
    });

    test('Rest 1 ist Bust', () {
      final g = X01Solo(seed: 1, startScore: 41)..prepare();
      throwAll(g, ['S20', 'S20']);
      expect(hasEvent(g.events, GameEventType.bust), isTrue);
      expect(g.remaining, 41);
      expect(g.result.metrics['busts'], 1);
      expect(g.result.metrics['average'], 0);
    });

    test('Master-Out checkt mit Triple, Double-Out bustet', () {
      final master = X01Solo(seed: 1, startScore: 60, outMode: OutMode.master)..prepare();
      master.throwDart(d('T20'));
      expect(hasEvent(master.events, GameEventType.checkout), isTrue);
      expect(master.finished, isTrue);

      final dbl = X01Solo(seed: 1, startScore: 60)..prepare();
      dbl.throwDart(d('T20'));
      expect(hasEvent(dbl.events, GameEventType.bust), isTrue);
      expect(dbl.remaining, 60);
    });

    test('Double-In: Punkte erst ab dem ersten Double', () {
      final g = X01Solo(seed: 1, doubleIn: true)..prepare();
      expect(g.targets, contains(Segment.double(7)));
      expect(g.display.headlineKey, 'doubleToStart');
      throwAll(g, ['S20', 'S20', 'D20']);
      expect(g.remaining, 461);
      expect(g.result.metrics['darts'], 3);
    });

    test('Bust nach dem Double-In-Dart setzt auch den Einstieg zurück', () {
      final g = X01Solo(seed: 1, startScore: 30, doubleIn: true)..prepare();
      g.throwDart(d('D20'));
      expect(g.opened, isFalse);
      expect(g.remaining, 30);
    });

    test('Zwei Legs: nach dem Checkout wieder Startwert', () {
      final g = X01Solo(seed: 1, startScore: 40, legs: 2)..prepare();
      g.throwDart(d('D20'));
      expect(hasEvent(g.events, GameEventType.legComplete), isTrue);
      expect(g.finished, isFalse);
      expect(g.remaining, 40);
      g.endVisit();
      g.throwDart(d('S5'));
      expect(g.remaining, 35);
      expect(g.legDarts, 1);
      expect(g.display.progressLabel, 'Leg 2/2');
    });

    test('Dart-Limit ohne Checkout verliert das Leg', () {
      final g = X01Solo(seed: 1, dartLimit: 9)..prepare();
      throwAll(g, List.filled(9, 'T20'));
      expect(hasEvent(g.events, GameEventType.failed), isTrue);
      expect(g.result.metrics['legsWon'], 0);
      expect(g.finished, isTrue);
    });

    test('Vorschlag folgt dem Rest und den Darts der Aufnahme', () {
      final g = X01Solo(seed: 1, startScore: 170)..prepare();
      expect(g.display.suggestion, [Segment.triple(20), Segment.triple(20), Segment.bull]);
      g.throwDart(d('T20'));
      expect(g.display.suggestion, [Segment.triple(20), Segment.bull]);
      g.throwDart(d('S20'));
      expect(g.display.suggestion, isNull, reason: '90 ist mit einem Dart nicht checkbar');
      g.throwDart(d('S10'));
      // Neue Aufnahme: 80 mit drei Darts.
      expect(g.display.suggestion, [Segment.triple(20), Segment.double(10)]);
      expect(X01Solo(seed: 1, showSuggestion: false).display.suggestion, isNull);
    });

    test('Checkout-Darts und Quote', () {
      final g = X01Solo(seed: 1, startScore: 40)..prepare();
      throwAll(g, ['S20', 'D10']);
      expect(g.result.metrics['checkoutDarts'], 2);
      expect(g.result.metrics['checkoutRate'], 0.5);
    });
  });

  group('Halve-It', () {
    test('Bermuda-Ablauf', () {
      final g = HalveIt(seed: 1)..prepare();
      throwAll(g, ['S12', 'S12', 'S12']);
      expect(g.score, 36);
      throwAll(g, ['MISS', 'MISS', 'MISS']);
      expect(g.score, 18);
      expect(hasEvent(g.events, GameEventType.halved), isTrue);
      throwAll(g, ['MISS', 'MISS', 'S14']);
      expect(g.score, 32);
      expect(g.current.kind, RoundTargetKind.anyDouble);
      throwAll(g, ['D5', 'MISS', 'T5']);
      expect(g.score, 42);
      expect(g.result.metrics['halvings'], 1);
      expect(g.result.metrics['cleanRounds'], 3);
      expect(g.display.progressLabel, '5/13');
    });

    test('Rundung', () {
      final up = HalveIt(seed: 1, roundUp: true, startScore: 37)..prepare();
      throwAll(up, ['MISS', 'MISS', 'MISS']);
      expect(up.score, 19);
      final down = HalveIt(seed: 1, startScore: 37)..prepare();
      throwAll(down, ['MISS', 'MISS', 'MISS']);
      expect(down.score, 18);
    });

    test('Vorzeitiges Ende ohne Treffer halbiert, Bull-Runde zählt normal', () {
      final g = HalveIt(seed: 1, preset: 'short', startScore: 40)..prepare();
      g.throwDart(d('MISS'));
      g.endVisit();
      expect(g.score, 20);
      expect(g.sequence.length, 9);
      expect(HalveIt.presets['bermuda']!.length, 13);
      expect(RoundTarget.bull.matches(Segment.bull), isTrue);
      expect(RoundTarget.bullseye.matches(Segment.outerBull), isFalse);
    });
  });

  group('Catch 40', () {
    test('2-Dart-Checkout = 3 Punkte', () {
      final g = Catch40(seed: 1)..prepare();
      throwAll(g, ['T15', 'D8']);
      expect(g.results.single.points, 3);
      expect(g.target, 62);
      expect(g.remaining, 62);
    });

    test('Bust bei Rest 1', () {
      final g = Catch40(seed: 1)..prepare();
      g.throwDart(d('T20'));
      expect(hasEvent(g.events, GameEventType.bust), isTrue);
      expect(g.remaining, 61);
    });

    test('99 in 3 Darts = 3 Punkte, 100 in 3 Darts = 2', () {
      final g = Catch40(seed: 1, min: 99, max: 100)..prepare();
      throwAll(g, ['T19', 'S10', 'D16']);
      expect(g.results.last.points, 3);
      throwAll(g, ['T20', 'S20', 'D10']);
      expect(g.results.last.points, 2);
      expect(g.finished, isTrue);
      expect(g.result.metrics['points'], 5);
      expect(g.result.metrics['maxPoints'], 6);
    });

    test('6 Fehlwürfe = 0 Punkte, nächstes Ziel', () {
      final g = Catch40(seed: 1)..prepare();
      throwAll(g, List.filled(6, 'MISS'));
      expect(g.results.single.points, 0);
      expect(g.target, 62);
    });

    test('Nicht checkbare Werte werden übersprungen, Vorschlag aktualisiert', () {
      final g = Catch40(seed: 1, min: 158, max: 170)..prepare();
      expect(g.pool, isNot(contains(159)));
      expect(g.pool.length * 3, g.maxPoints);
      final h = Catch40(seed: 1)..prepare();
      expect(h.display.suggestion, CheckoutCalculator.suggest(61, darts: 3));
      h.throwDart(d('T15'));
      expect(h.display.suggestion, [Segment.double(8)]);
    });
  });

  group('JDC-Challenge', () {
    test('Shanghai bringt 100 Bonus', () {
      final g = JdcChallenge(seed: 1)..prepare();
      throwAll(g, ['S10', 'D10', 'T10']);
      expect(g.score, 160);
      expect(hasEvent(g.events, GameEventType.shanghai), isTrue);
      expect(g.currentNumber, 11);
    });

    test('Drei Triples sind kein Shanghai', () {
      final g = JdcChallenge(seed: 1)..prepare();
      throwAll(g, ['T10', 'T10', 'T10']);
      expect(g.score, 90);
      expect(g.shanghais, 0);
    });

    test('Teil 2: Ziel wechselt pro Dart', () {
      final g = JdcChallenge(seed: 1)..prepare();
      throwAll(g, List.filled(18, 'MISS'));
      expect(g.part, 2);
      expect(g.currentDouble, Segment.double(1));
      throwAll(g, ['D1', 'D5', 'D3']);
      expect(g.partScores[1], 100);
      expect(g.currentDouble, Segment.double(4));
    });

    test('Teil 2 komplett = 1100, danach Ziel 15 mit neuer Aufnahme', () {
      final g = JdcChallenge(seed: 1)..prepare();
      throwAll(g, List.filled(18, 'MISS'));
      // Ein vorzeitiges Ende kostet in Teil 2 kein Double.
      g.throwDart(d('D1'));
      g.endVisit();
      throwAll(g, [for (var n = 2; n <= 20; n++) 'D$n', 'BULL']);
      expect(g.result.metrics['part2'], 1100);
      expect(hasEvent(g.events, GameEventType.partComplete), isTrue);
      expect(g.part, 3);
      expect(g.currentNumber, 15);
      expect(g.visitClosed, isTrue);
      g.endVisit();
      throwAll(g, ['S15', 'D15', 'T15']);
      expect(g.partScores[2], 190);
      throwAll(g, List.filled(15, 'MISS'));
      expect(g.finished, isTrue);
      expect(g.result.metrics['doubleRate'], 1.0);
    });
  });

  group('Shanghai', () {
    test('Shanghai beendet das Spiel', () {
      final g = Shanghai(seed: 1)..prepare();
      throwAll(g, ['S1', 'D1', 'T1']);
      expect(g.score, 6);
      expect(hasEvent(g.events, GameEventType.shanghai), isTrue);
      expect(g.finished, isTrue);
      expect(g.result.metrics['completed'], 1);
    });

    test('Shanghai mit Bonus', () {
      final g = Shanghai(seed: 1, shanghaiWins: false)..prepare();
      throwAll(g, ['S1', 'D1', 'T1']);
      expect(g.score, 106);
      expect(g.current, 2);
      throwAll(g, ['T2', 'T2', 'T2']);
      expect(g.score, 124);
      expect(g.shanghais, 1);
    });

    test('S1 T1 MISS ist kein Shanghai', () {
      final g = Shanghai(seed: 1)..prepare();
      throwAll(g, ['S1', 'T1', 'MISS']);
      expect(g.score, 4);
      expect(g.shanghais, 0);
      expect(g.finished, isFalse);
    });
  });

  group('Darts-Golf', () {
    test('Klassisch, letzter Dart zählt', () {
      final g = DartsGolf(seed: 1, classic: true)..prepare();
      g.throwDart(d('D1'));
      g.endVisit();
      expect(g.holeStrokes, [1]);
      throwAll(g, ['S2', 'T2']);
      g.endVisit();
      expect(g.holeStrokes.last, 2);
      throwAll(g, ['MISS', 'MISS', 'MISS']);
      expect(g.holeStrokes.last, 5);
      expect(g.strokes, 8);
      expect(g.toPar, -1);
      expect(g.result.metrics['holesInOne'], 1);
    });

    test('last vs. best', () {
      for (final (best, expected) in [(false, 5), (true, 1)]) {
        final g = DartsGolf(seed: 1, classic: true, countBest: best)..prepare();
        for (final n in ['D1', 'D2', 'D3']) {
          g.throwDart(d(n));
          g.endVisit();
        }
        expect(g.hole, 4);
        throwAll(g, ['D4', 'MISS']);
        expect(g.display.stats.last.value, '$expected');
        g.endVisit();
        expect(g.holeStrokes.last, expected);
      }
    });

    test('Falsche Zahl = 5, inneres Single nur klassisch 3', () {
      final g = DartsGolf(seed: 1, classic: true)..prepare();
      expect(g.strokesFor(Segment.single(5), 6), 5);
      expect(g.strokesFor(Segment.single(6, inner: true), 6), 3);
      expect(g.strokesFor(Segment.single(6), 6), 4);
      final s = DartsGolf(seed: 1)..prepare();
      expect(s.strokesFor(Segment.single(6, inner: true), 6), 4);
      expect(s.strokesFor(Segment.triple(6), 6), 3);
    });
  });

  group('420', () {
    test('Treffer ziehen ab', () {
      final g = Doubles420(seed: 1)..prepare();
      throwAll(g, ['D1', 'D1', 'MISS']);
      expect(g.score, 416);
      expect(g.currentSegment, Segment.double(2));
      throwAll(g, ['D2', 'D2', 'D2']);
      expect(g.score, 404);
    });

    test('Jedes Double einmal = 0', () {
      final g = Doubles420(seed: 1)..prepare();
      for (var n = 1; n <= 20; n++) {
        throwAll(g, ['D$n', 'MISS', 'MISS']);
      }
      expect(g.score, 0);
      expect(g.finished, isTrue);
      expect(g.result.metrics['missedDoubles'], 0);
      expect(Doubles420(seed: 1, includeBull: true).score, 470);
    });
  });

  group('Frustration', () {
    test('80 + Double', () {
      final g = Frustration(seed: 1)..prepare();
      g.throwDart(d('S20'));
      expect(g.targets, {Segment.triple(20)});
      g.throwDart(d('T20'));
      expect(g.targets, {Segment.double(1)});
      expect(g.display.suggestion, [Segment.double(1)]);
      g.throwDart(d('D1'));
      expect(g.currentSegment, Segment.double(2));
      expect(g.visits, 1);
    });

    test('79 reicht nicht, dritter Dart zählt nicht', () {
      final g = Frustration(seed: 1)..prepare();
      throwAll(g, ['S20', 'T20', 'D1']);
      throwAll(g, ['T20', 'S19']);
      expect(g.visitClosed, isTrue);
      g.throwDart(d('D2'));
      expect(g.ignoredDarts, 1);
      expect(g.currentSegment, Segment.double(2));
    });

    test('Falsches Double = kein Fortschritt', () {
      final g = Frustration(seed: 1)..prepare();
      throwAll(g, ['S20', 'T20', 'D1']);
      throwAll(g, ['T20', 'S20', 'D3']);
      expect(g.currentSegment, Segment.double(2));
      expect(g.result.metrics['doubleRate'], 0.5);
      expect(g.result.metrics['setupRate'], 1.0);
    });
  });

  group('Ziel-Wechsel', () {
    test('167', () {
      final g = SwitchDrill(seed: 1)..prepare();
      expect(g.targets, {Segment.triple(20)});
      g.throwDart(d('T20'));
      expect(g.targets, {Segment.triple(19)});
      throwAll(g, ['T19', 'BULL']);
      expect(g.hits, 3);
      expect(g.perfectRounds, 1);
      throwAll(g, ['T19', 'T20', 'BULL']);
      expect(g.hits, 4);
      throwAll(g, ['T20', '25', 'MISS']);
      expect(g.hits, 5);
      expect(g.result.metrics['hitRateTarget0'], 2 / 3);
    });
  });

  group('Doppel-Leiter', () {
    test('pro', () {
      final g = DoublesLadder(seed: 1, pro: true)..prepare();
      throwAll(g, ['D1', 'D1', 'D1']);
      expect(g.currentSegment, Segment.double(2));
      throwAll(g, ['D2', 'MISS', 'MISS']);
      expect(g.currentSegment, Segment.double(1));
      expect(hasEvent(g.events, GameEventType.levelDown), isTrue);
      throwAll(g, ['MISS', 'MISS', 'MISS']);
      expect(g.currentSegment, Segment.double(1));
      expect(g.result.metrics['highestLevel'], 2);
    });

    test('normal', () {
      final g = DoublesLadder(seed: 1)..prepare();
      throwAll(g, ['D1', 'D1', 'MISS']);
      expect(g.currentSegment, Segment.double(2));
    });

    test('Fertig über die letzte Stufe oder nach maxVisits', () {
      final g = DoublesLadder(seed: 1, includeBull: false)..prepare();
      for (var n = 1; n <= 20; n++) {
        throwAll(g, ['D$n', 'D$n', 'MISS']);
      }
      expect(g.finished, isTrue);
      expect(g.result.metrics['completed'], 1);
      final h = DoublesLadder(seed: 1, maxVisits: 10)..prepare();
      throwAll(h, List.filled(30, 'MISS'));
      expect(h.finished, isTrue);
      expect(h.visits, 10);
    });
  });

  group('Genau 100', () {
    test('Erfolg mit 3 Darts', () {
      final g = ExactScore(seed: 1)..prepare();
      throwAll(g, ['T20', 'S20', 'S20']);
      expect(g.results.single.success, isTrue);
      expect(g.results.single.darts, 3);
    });

    test('Überworfen: fail', () {
      final g = ExactScore(seed: 1)..prepare();
      throwAll(g, ['T20', 'T20']);
      expect(g.results.single.success, isFalse);
      expect(g.results.single.gap, 20);
      expect(g.score, 0);
      expect(g.visitClosed, isTrue);
    });

    test('Überworfen: bust', () {
      final g = ExactScore(seed: 1, bustOnOvershoot: true)..prepare();
      throwAll(g, ['T20', 'T20']);
      expect(g.score, 0);
      expect(g.visitClosed, isTrue);
      expect(g.results, isEmpty);
      expect(g.display.stats[1].value, '2');
    });

    test('Vorschlag für den genauen Rest', () {
      final g = ExactScore(seed: 1)..prepare();
      throwAll(g, ['T20', 'T20', 'T20']);
      throwAll(g, ['T20', 'T20', 'S20']);
      // Neuer Versuch nach Überwurf, dann 40 Rest mit 2 Darts.
      throwAll(g, ['T20']);
      expect(g.display.suggestion, isNotNull);
      expect(g.display.suggestion!.fold<int>(0, (s, x) => s + x.score), 40);
    });
  });

  group('Drei im Bett', () {
    test('wedge und segment', () {
      final wedge = ThreeInABed(seed: 1)..prepare();
      throwAll(wedge, ['S1', 'S1', 'D1']);
      expect(wedge.current, 2);
      final strict = ThreeInABed(seed: 1, strict: true)..prepare();
      throwAll(strict, ['S1', 'S1', 'D1']);
      expect(strict.current, 1);
      throwAll(strict, ['T1', 'T1', 'T1']);
      expect(strict.current, 2);
    });

    test('Kurze Aufnahme ist Fehlversuch', () {
      final g = ThreeInABed(seed: 1)..prepare();
      throwAll(g, ['S1', 'S1']);
      g.endVisit();
      expect(g.current, 1);
      expect(g.visits, 1);
    });
  });

  group('Stellen', () {
    test('Ideal, Erfolg, Fehlschlag', () {
      final classic = SetupShot(seed: 1, leavesKey: 'classic', fixedRests: const [57, 57, 72])..prepare();
      expect(classic.rest, 57);
      expect(classic.display.suggestion, [Segment.single(17)]);
      classic.throwDart(d('S17'));
      expect(hasEvent(classic.events, GameEventType.best), isTrue);
      expect(classic.tasks.last.success, isTrue);
      classic.throwDart(d('S20'));
      expect(classic.tasks.last.success, isFalse);
      classic.throwDart(d('T16'));
      expect(classic.tasks.last.success, isFalse);

      final good = SetupShot(seed: 1, fixedRests: const [72])..prepare();
      good.throwDart(d('T16'));
      expect(good.tasks.last.success, isTrue);
      expect(good.result.metrics['ideal'], 0);
    });

    test('Pool enthält keine checkbaren Werte', () {
      final g = SetupShot(seed: 1, leavesKey: 'classic', max: 100)..prepare();
      expect(g.pool, isNot(contains(50)));
      expect(g.pool.every((r) => r > 40), isTrue);
      for (var i = 0; i < 30; i++) {
        expect(g.pool, contains(g.rest));
        g.throwDart(d('MISS'));
      }
      expect(g.finished, isTrue);
    });
  });

  test('alle neuen Spiele stehen im Katalog, laufen über GameSession und haben eine Hauptkennzahl', () {
    const ids = [
      'x01', 'halve_it', 'catch_40', 'jdc_challenge', 'shanghai', 'golf', 'doubles_420', 'frustration', //
      'switch_drill', 'doubles_ladder', 'exact_score', 'three_in_a_bed', 'setup_shot',
    ];
    expect(GameCatalog.all.length, 24);
    for (final id in ids) {
      final def = GameCatalog.byId(id)!;
      final s = GameSession(definition: def, config: def.resolve(const {}), seed: 3);
      // Frustration schließt die Aufnahme ohne 80 Punkte nach dem 2. Dart.
      final dart = id == 'frustration' ? 'T20' : 'S1';
      for (var i = 0; i < 4; i++) {
        s.addDart(d(dart));
      }
      expect(s.undoLastDart(), isTrue);
      expect(s.game.dartsThrown, 3, reason: id);
      expect(s.game.display.headline, isNotEmpty);
      expect(s.game.result.metrics, isNotEmpty);
      final pm = PrimaryMetric.byGame[id];
      expect(pm, isNotNull, reason: id);
      expect(s.game.result.metrics.containsKey(pm!.key), isTrue, reason: id);
    }
  });
}
