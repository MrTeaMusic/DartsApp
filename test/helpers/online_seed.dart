import 'dart:math' as math;

import 'package:dartlab/features/autodarts_live/domain/live_recorder.dart';
import 'package:dartlab/features/autodarts_live/domain/live_stats.dart';
import 'package:dartlab/features/autodarts_live/domain/live_x01.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_controller.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/matches/domain/dart_bot.dart';

/// Ein Online-Match, wie Autodarts Live es mit „X01 mitzählen“ speichert:
/// Die eigenen Darts wirft ein Bot mit [average]; der Gegner checkt nach
/// 5–9 eigenen Aufnahmen (dann „Leg verloren“), sofern man nicht vorher
/// checkt. Doppel in [nervous] verfehlt man zusätzlich mit der angegebenen
/// Wahrscheinlichkeit (Dart landet im Single daneben).
///
/// [x01] = false speichert eine Session ohne X01 (`autodarts_live`).
Future<int> seedOnlineMatch(
  GameRepository repo,
  int player,
  DateTime start, {
  double average = 55,
  int legs = 4,
  int seed = 1,
  Map<int, double> nervous = const {},
  bool x01 = true,
  int opponentMin = 5,
  int opponentMax = 9,
}) async {
  final rnd = math.Random(seed);
  final bot = DartBot.forAverage(average, random: math.Random(seed * 13 + 1));
  final darts = <RecordedDart>[];
  final marks = <LegMark>[];
  var t = start;
  var visit = 0;
  for (var leg = 0; leg < legs; leg++) {
    var remaining = 501;
    final opponentVisits = opponentMin + rnd.nextInt(opponentMax - opponentMin + 1);
    var won = false;
    for (var v = 0; v < 40 && !won; v++) {
      final before = remaining;
      for (var d = 0; d < 3; d++) {
        final target = DartBot.aim(remaining, 3 - d, OutMode.double);
        t = t.add(const Duration(seconds: 6));
        final finishing = remaining <= DartBot.finishZone;
        var dart = bot.throwAt(target, at: t, sigma: finishing ? bot.finishSigma : null);
        final miss = target.isDouble ? nervous[target.number] : null;
        if (miss != null && dart.segment == target && rnd.nextDouble() < miss) {
          final s = target.number == 25 ? Segment.outerBull : Segment.single(target.number);
          dart = DartThrow(segment: s, position: BoardGeometry.centerOf(s), timestamp: t, source: DartSourceKind.autodartsLocal);
        }
        darts.add((dart: dart, visitIndex: visit));
        final seg = dart.segment;
        if (CheckoutRules.isBust(remaining, seg, OutMode.double)) {
          remaining = before;
          break;
        }
        remaining -= seg.score;
        if (remaining == 0) {
          won = true;
          break;
        }
      }
      visit++;
      t = t.add(const Duration(seconds: 40));
      if (!won && v + 1 >= opponentVisits) {
        marks.add((at: darts.length, kind: LegMarkKind.lost));
        break;
      }
    }
  }
  const config = LiveX01Config();
  final gameId = x01 ? autodartsLiveX01GameId : autodartsLiveGameId;
  final sid = await repo.startSession(
    playerId: player,
    gameId: gameId,
    config: {'source': 'autodartsLocal', 'mode': 'listen', 'pauseMinutes': 20, if (x01) 'x01': config.toJson()},
    seed: 0,
    startedAt: start,
  );
  final counted = x01 ? replayLive(config, darts, marks, visitOpen: false).counted : null;
  for (final (i, d) in darts.indexed) {
    await repo.addThrow(
      sessionId: sid,
      playerId: player,
      gameId: gameId,
      seq: i,
      visitIndex: d.visitIndex,
      counted: counted?[i] ?? true,
      dart: d.dart,
    );
  }
  await repo.endSession(sid, result: liveSessionResult(darts, x01 ? config : null, marks), finished: true, endedAt: t);
  return sid;
}
