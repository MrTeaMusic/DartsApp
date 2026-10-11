import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/domain/engine/game_definition.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/games/domain/engine/game_session.dart';
import 'package:dartlab/features/games/domain/engine/training_game.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/domain/games/scoring_drills.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

/// Minimalspiel zum Testen der Aufnahme-Logik: zählt Punkte, beendet die
/// Aufnahme bei einem Miss vorzeitig.
class _ProbeGame extends TrainingGame {
  _ProbeGame() : super(seed: 1);
  final visitsEnded = <List<String>>[];
  int points = 0;

  @override
  void handleDart(DartThrow dart) {
    points += dart.score;
    if (dart.segment.isMiss) closeVisit();
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) => visitsEnded.add([for (final d in visitDarts) d.segment.name]);

  @override
  Set<Segment> get targets => const {};
  @override
  GameDisplay get display => GameDisplay(headline: '$points', headlineKey: 'points');
  @override
  GameResult get result => GameResult(metrics: {'points': points}, summary: const []);
}

void main() {
  group('TrainingGame Aufnahmen', () {
    test('drei Darts schließen die Aufnahme, der vierte beginnt die nächste', () {
      final g = _ProbeGame();
      throwAll(g, ['S1', 'S2', 'S3', 'S4']);
      expect(g.visitsEnded, [
        ['S1', 'S2', 'S3'],
      ]);
      expect(g.visitIndex, 1);
      expect(g.visit.map((d) => d.segment.name), ['S4']);
    });

    test('vorzeitig geschlossene Aufnahme ignoriert restliche Darts', () {
      final g = _ProbeGame();
      throwAll(g, ['S5', 'MISS', 'T20']);
      expect(g.points, 5);
      expect(g.ignoredDarts, 1);
      expect(g.acceptsDarts, isTrue, reason: 'nach drei körperlichen Darts beginnt eine neue Aufnahme');
      throwAll(g, ['S1']);
      expect(g.points, 6);
      expect(g.visitIndex, 1);
    });

    test('endVisit (Takeout) beendet auch unvollständige Aufnahmen', () {
      final g = _ProbeGame();
      throwAll(g, ['S5']);
      g.endVisit();
      g.endVisit(); // doppelt ohne Wirkung
      throwAll(g, ['S6']);
      expect(g.visitsEnded, [
        ['S5'],
      ]);
      expect(g.visitIndex, 1);
    });

    test('nach Bust und Takeout zählt der nächste Dart sofort', () {
      final g = _ProbeGame();
      throwAll(g, ['MISS']);
      expect(g.acceptsDarts, isFalse);
      g.endVisit();
      expect(g.acceptsDarts, isTrue);
      throwAll(g, ['S9']);
      expect(g.points, 9);
    });
  });

  group('GameSession', () {
    GameSession session() => GameSession(definition: HighscoreHunt.definition, config: const {'visits': 3}, seed: 7);

    test('Rückgängig spielt alle Eingaben neu ab', () {
      final s = session();
      for (final n in ['T20', 'T20', 'T20', 'S1']) {
        s.addDart(d(n));
      }
      expect((s.game as HighscoreHunt).total, 181);
      expect(s.undoLastDart(), isTrue);
      expect((s.game as HighscoreHunt).total, 180);
      expect((s.game as HighscoreHunt).visitScores, [180]);
      expect(s.game.events, isEmpty);
    });

    test('Rückgängig entfernt auch ein nachfolgendes Aufnahme-Ende', () {
      final s = session();
      s.addDart(d('S20'));
      s.endVisit();
      expect((s.game as HighscoreHunt).visitScores, [20]);
      s.undoLastDart();
      expect((s.game as HighscoreHunt).visitScores, isEmpty);
      expect(s.inputs, isEmpty);
      expect(s.undoLastDart(), isFalse);
    });

    test('Korrektur ersetzt einen Dart der letzten Aufnahme', () {
      final s = session();
      for (final n in ['S20', 'S20', 'S20', 'S1', 'S5']) {
        s.addDart(d(n));
      }
      expect(s.correctDart(1, d('T5')), isTrue);
      expect((s.game as HighscoreHunt).total, 60 + 1 + 15);
      expect(s.correctDart(5, d('T5')), isFalse);
    });

    test('Config wird mit Standardwerten aufgefüllt', () {
      final s = GameSession(definition: TargetPractice.definition, config: const {}, seed: 1);
      expect(s.config['number'], 20);
      expect(s.config['visits'], 10);
    });
  });

  test('Katalog: eindeutige IDs, jedes Spiel startet mit Standard-Config', () {
    final ids = GameCatalog.all.map((g) => g.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final def in GameCatalog.all) {
      final game = def.start(const {}, 42)..prepare();
      expect(game.display.headline, isNotEmpty, reason: def.id);
      expect(game.finished, isFalse);
      for (final o in def.options) {
        expect(def.defaults.containsKey(o.key), isTrue, reason: '${def.id}.${o.key} ohne Standardwert');
      }
    }
    expect(GameCatalog.byId('checkout'), isNotNull);
    expect(GameCatalog.byId('gibt-es-nicht'), isNull);
  });

  test('ConfigRead liest tolerant', () {
    final c = <String, Object?>{'a': 3.6, 'b': '7', 'c': true, 'l': [1, 2.0, 'x']};
    expect(c.intOf('a', 0), 4);
    expect(c.intOf('b', 0), 7);
    expect(c.intOf('x', 9), 9);
    expect(c.boolOf('c', false), isTrue);
    expect(c.stringOf('c', 'f'), 'f');
    expect(c.intListOf('l'), [1, 2]);
  });
}
