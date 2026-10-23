import 'dart:convert';

import 'package:dartlab/features/autodarts_import/domain/autodarts_match_mapping.dart';
import 'package:dartlab/features/autodarts_import/domain/imported_match.dart';
import 'package:dartlab/features/autodarts_import/domain/import_plan.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/autodarts_match_fixture.dart';

// Alle Daten sind synthetisch (siehe autodarts_match_fixture.dart).

ImportedMatch read(Map<String, Object?> json) => parseAutodartsMatch(jsonDecode(jsonEncode(json)));

final _now = DateTime.utc(2026, 10, 21, 12);

void main() {
  final match = read(syntheticMatch());

  group('Ben ist Spieler 0', () {
    final plan = buildImportPlan(match, me: 0, now: _now);

    test('Legs, Sieg und Aufnahmen', () {
      expect(plan.legsMe, 3);
      expect(plan.legsOpponent, 2);
      expect(plan.won, isTrue);
      expect(plan.finished, isTrue);
      expect(plan.myPlayer.name, 'Ben');
      expect(plan.opponent.name, 'Gegner');
      expect(plan.warnings, isEmpty);
      expect(plan.result.metrics['legsWon'], 3);
      expect(plan.result.metrics['legsLost'], 2);
      expect(plan.result.metrics['legs'], 5);
      expect(plan.result.metrics['won'], 1);
    });

    test('nur Bens Darts werden gespeichert, nie die des Gegners', () {
      final ownFromData = [
        for (final t in match.legs.expand((l) => l.turns))
          if (t.player == 0) ...t.darts,
      ];
      expect(plan.darts, hasLength(ownFromData.length));
      expect([for (final d in plan.darts) d.segment], [for (final d in ownFromData) d.segment]);
      expect(plan.ownVisits, plan.darts.last.visitIndex + 1);
      final oppDarts = [
        for (final t in match.legs.expand((l) => l.turns))
          if (t.player == 1) ...t.darts,
      ];
      expect(oppDarts, isNotEmpty);
      expect(plan.darts.length, lessThan(ownFromData.length + oppDarts.length));
    });

    test('Positionen von Ben bleiben erhalten, Fehlwürfe haben eine', () {
      expect(plan.darts.where((d) => d.position != null), hasLength(plan.darts.length));
    });

    test('verlorene Legs sind als Marken nach Bens Darts des Legs eingetragen', () {
      expect(plan.marks, hasLength(2));
      final ends = <int>[];
      var n = 0;
      for (final leg in match.legs) {
        for (final t in leg.turns) {
          if (t.player == 0) n += t.darts.length;
        }
        ends.add(n);
      }
      expect([for (final m in plan.marks) m.at], [ends[1], ends[3]]);
    });

    test('Bust in Leg 3 steht in den Kennzahlen, alle geworfenen Darts zählen', () {
      expect(plan.result.metrics['busts'], 1);
      expect(plan.darts.every((d) => d.counted), isTrue);
    });

    test('Zeiten laufen nie rückwärts und liegen im Matchzeitraum', () {
      for (var i = 1; i < plan.darts.length; i++) {
        expect(plan.darts[i].at.isBefore(plan.darts[i - 1].at), isFalse);
      }
      expect(plan.startedAt.isAfter(plan.endedAt), isFalse);
      expect(plan.startedAt.toUtc().year, 2026);
    });

    test('Gegner nur im Ergebnis: Name, Statistik, Aufnahmen je Leg', () {
      final d = plan.result.details;
      expect(d['opponents'], ['Gegner']);
      expect(d['mode'], 'import');
      expect(d['player'], 0);
      expect(d['won'], isTrue);
      final players = d['players']! as List;
      expect((players[1] as Map)['name'], 'Gegner');
      expect((players[1] as Map)['darts'], greaterThan(30));
      final legs = d['matchLegs']! as List;
      expect(legs, hasLength(5));
      expect([for (final l in legs) (l as Map)['winner']], [0, 1, 0, 1, 0]);
      expect(((legs[1] as Map)['opp']! as List), isNotEmpty);
    });

    test('Konfiguration trägt die Autodarts-Id und keine Darts des Gegners', () {
      final imp = plan.config['import']! as Map;
      expect(imp['id'], 'synthetic-0001');
      expect(imp['me'], 'Ben');
      expect(imp['opponent'], 'Gegner');
      expect(plan.config['mode'], 'import');
    });
  });

  group('Ben ist Spieler 1', () {
    test('gespiegelt: 2:3 aus Sicht des Gegners, Verlierer', () {
      final plan = buildImportPlan(match, me: 1, now: _now);
      expect(plan.legsMe, 2);
      expect(plan.legsOpponent, 3);
      expect(plan.won, isFalse);
      expect(plan.myPlayer.name, 'Gegner');
      expect(plan.result.metrics['won'], 0);
      expect(plan.marks, hasLength(3));
    });
  });

  group('Sonderfälle', () {
    test('ohne Koordinaten: keine Positionen, sonst gleich', () {
      final plan = buildImportPlan(read(syntheticMatch(coords: false)), me: 0, now: _now);
      expect(plan.darts.where((d) => d.position != null), isEmpty);
      expect(plan.legsMe, 3);
    });

    test('fehlender Sieger wird nachgerechnet', () {
      final json = syntheticMatch();
      for (final g in json['games']! as List) {
        (g as Map<String, Object?>).remove('winnerPlayerId');
      }
      final plan = buildImportPlan(read(json), me: 0, now: _now);
      expect(plan.legsMe, 3);
      expect(plan.legsOpponent, 2);
      expect(plan.warnings, isEmpty);
    });

    test('Sieger laut Daten und Nachrechnen unterscheiden sich: Hinweis, Daten gelten', () {
      final json = syntheticMatch();
      ((json['games']! as List).first as Map<String, Object?>)['winnerPlayerId'] = 'p-opp';
      final plan = buildImportPlan(read(json), me: 0, now: _now);
      expect(plan.warnings.any((w) => w.contains('Leg 1')), isTrue);
      expect(plan.legsMe, 2);
      expect(plan.legsOpponent, 3);
    });

    test('offenes Match: nicht beendet, kein Sieger', () {
      final json = syntheticMatch(finished: false, finishedAt: null);
      (json['games']! as List).removeLast();
      final plan = buildImportPlan(read(json), me: 0, now: _now);
      expect(plan.finished, isFalse);
      expect(plan.won, isNull);
      expect(plan.result.metrics.containsKey('won'), isFalse);
    });

    test('Double-In: Hinweis im Plan', () {
      final json = syntheticMatch();
      (json['settings']! as Map<String, Object?>)['inMode'] = 'Double';
      final plan = buildImportPlan(read(json), me: 0, now: _now);
      expect(plan.warnings.single, contains('Double-In'));
    });

    test('301 mit Straight-Out wird übernommen', () {
      final plan = buildImportPlan(read(syntheticMatch(start: 301, outMode: 'Straight', winners: const [0, 0])), me: 0, now: _now);
      expect(plan.x01.startScore, 301);
      expect(plan.legsMe, 2);
      expect(plan.darts.first.segment, isA<Segment>());
    });
  });

  group('Wer bin ich?', () {
    test('Name ohne Groß-/Kleinschreibung', () {
      expect(identifyMe(match, 'ben'), 0);
      expect(identifyMe(match, '  GEGNER '), 1);
    });
    test('unbekannt oder leer: nachfragen', () {
      expect(identifyMe(match, ''), isNull);
      expect(identifyMe(match, 'Niemand'), isNull);
    });
    test('gleicher Name bei beiden: nachfragen', () {
      final m = read(syntheticMatch(ben: 'Max', opponent: 'max'));
      expect(identifyMe(m, 'Max'), isNull);
    });
  });
}
