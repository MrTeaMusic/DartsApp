import 'package:dartlab/features/caller/domain/caller_phrases.dart';
import 'package:dartlab/features/matches/domain/match_call_planner.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/x01_match.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

void throwMatch(X01Match m, List<String> darts) {
  for (final n in darts) {
    m.throwDart(d(n));
  }
}

void main() {
  test('Punkte der Aufnahme, Rest des nächsten Spielers nur auf einem Finish', () {
    final m = X01Match(format: const MatchFormat(startScore: 301, legsToWin: 1), playerCount: 2);
    throwMatch(m, ['T20', 'T20', 'S20']);
    expect(MatchCallPlanner.forClosedVisit(m), [const ScoreCall(140)]);
    m.endVisit();
    throwMatch(m, ['T20', 'T20', 'T20']);
    // Spieler 0 steht auf 161: auscheckbar.
    expect(MatchCallPlanner.forClosedVisit(m), [const ScoreCall(180), const RequireCall(161)]);
  });

  test('Bust und „You require“', () {
    final m = X01Match(format: const MatchFormat(startScore: 40, legsToWin: 1), playerCount: 2);
    throwMatch(m, ['S20', 'S19']);
    expect(MatchCallPlanner.forClosedVisit(m), [const BustCall(), const RequireCall(40)]);
  });

  test('Game shot: Leg, Satz, Match', () {
    final legs = X01Match(format: const MatchFormat(startScore: 40, legsToWin: 2), playerCount: 2);
    throwMatch(legs, ['D20']);
    expect(MatchCallPlanner.forClosedVisit(legs), [const GameShotCall(GameShotKind.leg)]);
    legs.endVisit();
    throwMatch(legs, ['S1', 'S1', 'S1']);
    legs.endVisit();
    throwMatch(legs, ['D20']);
    expect(MatchCallPlanner.forClosedVisit(legs), [const GameShotCall(GameShotKind.match)]);

    final sets = X01Match(format: const MatchFormat(startScore: 40, legsToWin: 1, setsToWin: 2), playerCount: 2);
    throwMatch(sets, ['D20']);
    expect(MatchCallPlanner.forClosedVisit(sets), [const GameShotCall(GameShotKind.set)]);
  });

  test('Kein Rest ohne Eröffnung bei Double-In', () {
    final m = X01Match(format: const MatchFormat(startScore: 101, doubleIn: true, legsToWin: 1), playerCount: 2);
    expect(MatchCallPlanner.requireFor(m, 0), isNull);
    m.throwDart(d('D10'));
    expect(MatchCallPlanner.requireFor(m, 0), const RequireCall(81));
  });

  test('Per Takeout beendete Aufnahme', () {
    final m = X01Match(format: const MatchFormat(legsToWin: 1), playerCount: 2);
    m.throwDart(d('T20'));
    m.endVisit();
    expect(MatchCallPlanner.forEndedVisit(m, 0), [const ScoreCall(60)]);
  });
}
