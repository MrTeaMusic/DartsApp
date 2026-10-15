import 'dart:math' as math;

import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/training_game.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:dartlab/features/matches/domain/bot_calibration.dart';
import 'package:dartlab/features/matches/domain/dart_bot.dart';
import 'package:dartlab/features/stats/domain/scatter_stats.dart';

import 'online_seed.dart';

/// Werfer wie im Simulator (Normalverteilung um den Zielpunkt), aber mit
/// fester Tendenz je Feld und seitlich etwas mehr Streuung als in der Höhe.
class BiasedThrower {
  BiasedThrower({
    double average = 55,
    this.horizontal = 1.25,
    this.vertical = 0.85,
    Map<String, (double, double)>? bias,
    math.Random? random,
  })  : sigma = BotCalibration.sigmaFor(average),
        finishSigma = BotCalibration.finishSigmaFor(average),
        bias = bias ?? defaultBias,
        random = random ?? math.Random(1);

  /// Tendenz je Feld in mm, in den Achsen des Felds (rechts, oben); Schlüssel
  /// „T20“, „T19“, „D“ (alle Doppel), „BULL“, „*“ (Rest).
  static const Map<String, (double, double)> defaultBias = {
    'T20': (-4, -5),
    'T19': (1.5, -4),
    'D': (5, -1.5),
    'BULL': (2, -3),
    '*': (-2, -3),
  };

  final double sigma;
  final double finishSigma;
  final double horizontal;
  final double vertical;
  final Map<String, (double, double)> bias;
  final math.Random random;

  double _gaussian() {
    final u1 = 1.0 - random.nextDouble();
    final u2 = random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  BoardPoint offsetFor(Segment target) {
    final key = target.isBull ? 'BULL' : (target.isDouble ? 'D' : target.name);
    final (t, r) = bias[key] ?? bias['*'] ?? (0, 0);
    final f = FieldFrame.of(target);
    const mm = BoardGeometry.boardRadiusMm;
    return BoardPoint((t * f.tangential.x + r * f.radial.x) / mm, (t * f.tangential.y + r * f.radial.y) / mm);
  }

  DartThrow throwAt(Segment target, {required DateTime at, bool finishing = false}) {
    final s = finishing || target.isDouble ? finishSigma : sigma;
    final aim = BoardGeometry.centerOf(target) + offsetFor(target);
    final p = aim + BoardPoint(_gaussian() * s * horizontal, _gaussian() * s * vertical);
    return DartThrow(segment: BoardGeometry.segmentAt(p), position: p, timestamp: at, source: DartSourceKind.simulator);
  }
}

/// Spielt ein Trainingsspiel mit [thrower] durch und speichert es wie der
/// Spiel-Controller (wie `seedTraining`, aber mit Tendenz).
Future<int> seedBiasedTraining(
  GameRepository repo,
  int player,
  String gameId,
  Map<String, Object?> config,
  DateTime start,
  BiasedThrower thrower, {
  int seed = 1,
  int? stopAfter,
}) async {
  final game = GameCatalog.byId(gameId)!.start(config, seed)..prepare();
  final sid = await repo.startSession(playerId: player, gameId: gameId, config: config, seed: seed, startedAt: start);
  for (var seq = 0; !game.finished && seq < (stopAfter ?? 400); seq++) {
    if (game.visitClosed && game.physicalDartsInVisit > 0 && game.physicalDartsInVisit < TrainingGame.dartsPerVisit) {
      game.endVisit();
    }
    final Segment target;
    var finishing = false;
    if (game is X01Solo) {
      target = DartBot.aim(game.remaining, game.dartsLeftInVisit, OutMode.double, opened: game.opened);
      finishing = game.remaining <= DartBot.finishZone;
    } else {
      final t = game.targets.toList()..sort((a, b) => b.score.compareTo(a.score));
      target = t.isEmpty ? Segment.triple(20) : t.first;
    }
    final dart = thrower.throwAt(target, at: start.add(Duration(seconds: seq * 9)), finishing: finishing);
    final before = game.dartsThrown;
    game.throwDart(dart);
    await repo.addThrow(
      sessionId: sid,
      playerId: player,
      gameId: gameId,
      seq: seq,
      visitIndex: game.visitIndex,
      counted: game.dartsThrown > before,
      dart: dart,
    );
  }
  await repo.endSession(sid, result: game.result, finished: game.finished, endedAt: start.add(const Duration(minutes: 15)));
  return sid;
}

/// Vier Wochen Training eines 55er-Spielers mit Simulator-Positionen: leicht
/// links unten auf T20, rechts auf den Doppeln. T20 und die Doppel kommen
/// mit angezeigtem Ziel (exakt), T19 nur aus X01, Cricket und den
/// Online-Matches (geschätzt).
/// [scale] < 1 spielt weniger Sessions (Widget-Tests).
Future<void> seedScatter(GameRepository repo, int player, DateTime now, {double scale = 1}) async {
  final thrower = BiasedThrower(random: math.Random(7));
  DateTime at(int daysAgo, int hour) => DateTime(now.year, now.month, now.day - daysAgo, hour);
  final rounds = math.max(1, (8 * scale).round());
  for (var i = 0; i < rounds; i++) {
    final day = i * 3;
    await seedBiasedTraining(repo, player, 'target_practice', const {'number': 20, 'visits': 20}, at(day, 17), thrower, seed: 10 + i);
    await seedBiasedTraining(repo, player, 'checkout', const {'mode': 'random', 'min': 2, 'max': 40, 'attempts': 15},
        at(day + 1, 18), thrower, seed: 20 + i);
    await seedBiasedTraining(repo, player, 'x01', const {'startScore': 501, 'legs': 2}, at(day + 2, 19), thrower, seed: 30 + i);
    await seedBiasedTraining(repo, player, 'cricket', const {}, at(day + 2, 20), thrower, seed: 50 + i);
    if (i.isEven) {
      await seedBiasedTraining(repo, player, 'bull_drill', const {'visits': 10}, at(day + 1, 19), thrower, seed: 40 + i);
      await seedOnlineMatch(repo, player, at(day, 21),
          seed: 60 + i, legs: 4, opponentMin: 6, opponentMax: 11,
          throwAt: (target, t, finishing) => thrower.throwAt(target, at: t, finishing: finishing));
    }
  }
}
