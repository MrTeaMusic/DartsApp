import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/games/domain/engine/game_session.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/domain/games/around_the_clock.dart';
import 'package:dartlab/features/games/domain/games/bobs_27.dart';
import 'package:dartlab/features/games/domain/games/cricket.dart';
import 'package:dartlab/features/games/domain/games/one_twenty_one.dart';
import 'package:dartlab/features/games/domain/games/own_games.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

void main() {
  group('Cricket', () {
    test('Marks bis zum Schließen, Überschuss verfällt, MPR', () {
      final g = CricketTraining(seed: 1)..prepare();
      throwAll(g, ['S20']);
      expect(g.events.single.type, GameEventType.hit);
      throwAll(g, ['D20']);
      expect(g.isClosed(20), isTrue);
      throwAll(g, ['T20']);
      expect(g.countedMarks, 3);
      throwAll(g, ['T19', 'S1', 'T20']);
      expect(g.marks[20], 3, reason: 'geschlossene Zahl bekommt nichts mehr');
      expect(g.countedMarks, 6);
      expect(g.mpr, 3);
    });

    test('Schließen meldet Ereignis, alles zu beendet das Spiel', () {
      final g = CricketTraining(seed: 1)..prepare();
      throwAll(g, ['T20']);
      expect(g.events.single.type, GameEventType.closed);
      throwAll(g, ['T19', 'T18', 'T17', 'T16', 'T15', 'BULL', '25']);
      expect(g.finished, isTrue);
      expect(g.result.metrics['darts'], 8);
      expect(g.result.metrics['closedNumbers'], 7);
    });

    test('der Reihe nach zählt nur die aktuelle Zahl', () {
      final g = CricketTraining(seed: 1, order: CricketOrder.sequential, includeBull: false)..prepare();
      throwAll(g, ['T19']);
      expect(g.marks[19], 0);
      throwAll(g, ['T20', 'T19']);
      expect(g.marks[19], 3);
      expect(g.active, [18]);
      expect(g.targets, contains(Segment.triple(18)));
      expect(g.targets, isNot(contains(Segment.triple(17))));
    });

    test('einstellbare Marks zum Schließen', () {
      final g = CricketTraining(seed: 1, marksToClose: 1, includeBull: false)..prepare();
      throwAll(g, ['T20', 'S19', 'S18', 'S17', 'S16', 'S15']);
      expect(g.finished, isTrue);
      expect(g.countedMarks, 6);
    });
  });

  group('121', () {
    test('Checkout steigt um eins und gibt die Aufnahme frei', () {
      final g = OneTwentyOne(seed: 1)..prepare();
      expect(g.target, 121);
      throwAll(g, ['T20', 'T11', 'D14']);
      expect(g.events.first.type, GameEventType.checkout);
      expect(g.target, 122);
      expect(g.safe, 121);
      expect(g.highest, 121);
      g.endVisit(); // Takeout; im Simulator gibt der Controller die Aufnahme frei.
      throwAll(g, ['T20']);
      expect(g.remaining, 62);
    });

    test('Fehlversuch: zurück zum letzten Erfolg', () {
      final g = OneTwentyOne(seed: 1, visitsPerTarget: 1, start: 50)..prepare();
      throwAll(g, ['BULL']);
      expect(g.target, 51);
      g.endVisit();
      throwAll(g, ['MISS', 'MISS', 'MISS']);
      expect(g.history.last.success, isFalse);
      expect(g.target, 50);
      expect(g.remaining, 50);
    });

    test('Fehlversuch: gleich bleiben oder eins runter', () {
      final stay = OneTwentyOne(seed: 1, visitsPerTarget: 1, start: 50, failRule: FailRule.stay)..prepare();
      throwAll(stay, ['BULL']);
      stay.endVisit();
      throwAll(stay, ['MISS', 'MISS', 'MISS']);
      expect(stay.target, 51);
      final down = OneTwentyOne(seed: 1, visitsPerTarget: 1, start: 50, failRule: FailRule.down)..prepare();
      throwAll(down, ['BULL']);
      down.endVisit();
      throwAll(down, ['S11', 'D20']);
      down.endVisit();
      expect(down.target, 52);
      throwAll(down, ['MISS', 'MISS', 'MISS']);
      expect(down.target, 51);
      throwAll(down, ['MISS', 'MISS', 'MISS', 'MISS', 'MISS', 'MISS']);
      expect(down.target, 50, reason: 'nie unter den Startwert');
    });

    test('Bust setzt auf den Aufnahmestart zurück, 9 Darts pro Ziel', () {
      final g = OneTwentyOne(seed: 1)..prepare();
      throwAll(g, ['T20', 'T20', 'S1']);
      expect(g.remaining, 121, reason: 'Rest 1 ist Bust, der dritte Dart zählt nicht mehr');
      expect(g.ignoredDarts, 1);
      throwAll(g, ['T20', 'S1', 'MISS', 'MISS', 'MISS', 'MISS']);
      expect(g.history.single.success, isFalse);
      expect(g.target, 121);
    });

    test('Ende nach der eingestellten Zahl an Zielen', () {
      final g = OneTwentyOne(seed: 1, visitsPerTarget: 1, rounds: 2, start: 40)..prepare();
      throwAll(g, ['D20']);
      g.endVisit();
      throwAll(g, ['MISS', 'MISS', 'MISS']);
      expect(g.finished, isTrue);
      expect(g.result.metrics['checkouts'], 1);
      expect(g.result.metrics['highestCheckout'], 40);
    });
  });

  group("Bob's 27", () {
    test('Treffer bringen, leere Aufnahme kostet den Double-Wert', () {
      final g = Bobs27(seed: 1)..prepare();
      throwAll(g, ['D1', 'D1', 'S1']);
      expect(g.score, 31);
      expect(g.current, 2);
      throwAll(g, ['S2', 'T2', 'MISS']);
      expect(g.score, 27);
      expect(g.events.single.type, GameEventType.failed);
      expect(g.targets, {Segment.double(3)});
    });

    test('unter 0 ist Schluss', () {
      final g = Bobs27(seed: 1, startScore: 5)..prepare();
      throwAll(g, ['MISS', 'MISS', 'MISS']);
      expect(g.score, 3);
      throwAll(g, ['MISS', 'MISS', 'MISS']);
      expect(g.score, -1);
      expect(g.finished, isTrue);
      expect(g.survived, isFalse);
      expect(g.result.metrics['completed'], 0);
    });

    test('Bull am Ende zählt 50, ganzes Spiel geschafft', () {
      final g = Bobs27(seed: 1, allowNegative: true)..prepare();
      for (var n = 1; n <= 20; n++) {
        throwAll(g, ['D$n', 'MISS', 'MISS']);
      }
      expect(g.current, 25);
      throwAll(g, ['BULL', '25', 'MISS']);
      expect(g.finished, isTrue);
      expect(g.score, 27 + 420 + 50);
      expect(g.survived, isTrue);
    });
  });

  group('Drei-Treffer-Runde', () {
    test('Treffer sammeln sich über Aufnahmen, Dart zählt auf die aktuelle Zahl', () {
      final g = ThreeHitsRound(seed: 1)..prepare();
      throwAll(g, ['S1', 'MISS', 'T1']);
      expect(g.progressHits, 2);
      throwAll(g, ['D1', 'S2', 'S2']);
      expect(g.current, 2, reason: 'nach dem dritten Treffer zählt der nächste Dart schon auf die 2');
      expect(g.progressHits, 2);
      expect(g.dartsPerNumber, [4]);
    });

    test('Multiplikator zählt optional mehrfach, Überschuss verfällt', () {
      final g = ThreeHitsRound(seed: 1, multiplierCounts: true)..prepare();
      throwAll(g, ['T1']);
      expect(g.current, 2);
      throwAll(g, ['D2', 'T2']);
      expect(g.current, 3);
      expect(g.progressHits, 0);
    });

    test('Ende nach Bull, Wertung in Darts', () {
      final g = ThreeHitsRound(seed: 1, hitsRequired: 1, order: NumberOrder.clockwise)..prepare();
      expect(g.sequence.take(3), [20, 1, 18]);
      for (final n in g.sequence.take(20)) {
        throwAll(g, ['S$n']);
      }
      throwAll(g, ['MISS', '25']);
      expect(g.finished, isTrue);
      expect(g.result.metrics['darts'], 22);
    });
  });

  group('Around the World mit Überspringen', () {
    test('Punkte pro Zahl, ab 4 Punkten wird die nächste übersprungen', () {
      final g = SkipAroundTheWorld(seed: 1)..prepare();
      throwAll(g, ['S1', 'T1', 'MISS']);
      expect(g.points, 4);
      expect(g.events.last.type, GameEventType.skipped);
      expect(g.current, 3);
      expect(g.pointsByNumber[2], isNull);
      throwAll(g, ['T3', 'S2', 'MISS']);
      expect(g.points, 7);
      expect(g.current, 4);
      expect(g.skips, 1);
    });

    test('Takeout beendet die Aufnahme auch mit weniger Darts', () {
      final g = SkipAroundTheWorld(seed: 1)..prepare();
      throwAll(g, ['D1']);
      g.endVisit();
      expect(g.current, 2);
      expect(g.pointsByNumber[1], 2);
    });

    test('von 19 auf Bull springen, Bull selbst wird nicht übersprungen', () {
      final g = SkipAroundTheWorld(seed: 1)..prepare();
      for (var n = 1; n <= 18; n++) {
        throwAll(g, ['MISS', 'MISS', 'MISS']);
      }
      expect(g.current, 19);
      throwAll(g, ['T19', 'S19', 'MISS']);
      expect(g.current, 25);
      throwAll(g, ['BULL', 'BULL', 'MISS']);
      expect(g.finished, isTrue);
      expect(g.points, 4 + 4);
    });

    test('von 20 aus: Bull bleibt, außer Überspringen ist erlaubt', () {
      void toTwenty(SkipAroundTheWorld g) {
        for (var n = 1; n <= 19; n++) {
          throwAll(g, ['MISS', 'MISS', 'MISS']);
        }
        throwAll(g, ['T20', 'S20', 'MISS']);
      }

      final normal = SkipAroundTheWorld(seed: 1)..prepare();
      toTwenty(normal);
      expect(normal.current, 25);
      expect(normal.finished, isFalse);

      final skippable = SkipAroundTheWorld(seed: 1, bullSkippable: true)..prepare();
      toTwenty(skippable);
      expect(skippable.finished, isTrue);
      expect(skippable.skips, 1);
    });
  });

  test('alle Phase-3-Spiele stehen im Katalog und laufen über GameSession', () {
    for (final id in ['cricket', 'one_twenty_one', 'bobs_27', 'three_hits', 'skip_world']) {
      final def = GameCatalog.byId(id)!;
      final s = GameSession(definition: def, config: def.resolve(const {}), seed: 3);
      for (var i = 0; i < 4; i++) {
        s.addDart(d('S1'));
      }
      expect(s.undoLastDart(), isTrue);
      expect(s.game.dartsThrown, 3, reason: id);
      expect(s.game.display.headline, isNotEmpty);
      expect(s.game.result.metrics, isNotEmpty);
    }
  });
}
