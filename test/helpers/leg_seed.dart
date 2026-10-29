import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/matches/domain/match_result.dart';

import 'darts.dart';

/// Match 101, Double-Out, zwei Legs, von Hand gebaut (Ben gegen Anna, beide
/// erfunden), damit die Zahlen im Test nachzurechnen sind:
///
/// * Leg 1 (Anna beginnt, Ben gewinnt): Anna 60 (Rest 41), dann S5 S5 S5 mit
///   einem Dart auf D18 daneben. Ben 81 (Rest 20), dann S10 (daneben auf D10)
///   und D5 (Checkout).
/// * Leg 2 (Ben beginnt, Anna gewinnt): Ben Bust (T20 T20), dann S1 S1 S1;
///   Anna 81 (Rest 20), dann D10 (Checkout).
///
/// Ohne [withOpponent] fehlen die Aufnahmen von Anna, wie bei Matches, die vor
/// dem Aufnahmenverlauf gespeichert wurden.
Future<int> seedHandMadeMatch(GameRepository repo, int me, DateTime start, {bool withOpponent = true}) async {
  final sid = await repo.startSession(
    playerId: me,
    gameId: matchGameId,
    config: {
      'startScore': 101,
      'outMode': 'double',
      'legsToWin': 2,
      'opponents': ['Anna'],
      'vsBot': true,
    },
    seed: 0,
    startedAt: start,
  );
  var seq = 0;
  Future<void> visit(int index, List<String> names, {int uncounted = 0}) async {
    for (final (i, n) in names.indexed) {
      await repo.addThrow(
        sessionId: sid,
        playerId: me,
        gameId: matchGameId,
        seq: seq++,
        visitIndex: index,
        counted: i < names.length - uncounted,
        dart: d(n),
      );
    }
  }

  await visit(1, ['T20', 'S20', 'S1']);
  await visit(3, ['S10', 'D5']);
  await visit(4, ['T20', 'T20', 'S1'], uncounted: 1);
  await visit(6, ['S1', 'S1', 'S1']);
  await repo.endSession(
    sid,
    finished: true,
    endedAt: start.add(const Duration(minutes: 9)),
    result: GameResult(
      metrics: const {'won': 1, 'legsWon': 1, 'legsLost': 1, 'legs': 2, 'darts': 10, 'checkoutDarts': 2, 'average': 41.2},
      summary: const [],
      details: {
        'opponents': ['Anna'],
        'format': {'startScore': 101, 'outMode': 'double', 'doubleIn': false, 'legsToWin': 2, 'setsToWin': 0},
        'player': 0,
        'players': [
          {'name': 'Ben', 'bot': false, 'legs': 1, 'darts': 10, 'average': 41.2},
          {'name': 'Anna', 'bot': true, 'legs': 1, 'darts': 10, 'average': 39.0},
        ],
        'legs': [
          {
            'winner': 0,
            'set': 1,
            'darts': 5,
            'checkout': 20,
            'visit': 3,
            if (withOpponent)
              'opp': [
                ['S20', 'S20', 'S20'],
                ['S5', 'S5', 'S5'],
              ],
          },
          {
            'winner': 1,
            'set': 1,
            'darts': 4,
            'checkout': 20,
            'visit': 7,
            if (withOpponent)
              'opp': [
                ['T20', 'S20', 'S1'],
                ['D10'],
              ],
          },
        ],
      },
    ),
  );
  return sid;
}
