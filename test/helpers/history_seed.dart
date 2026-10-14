import 'dart:math' as math;

import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/training_game.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:dartlab/features/matches/domain/dart_bot.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_result.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';

/// Spielt ein Trainingsspiel mit einem Bot-Werfer durch und speichert es
/// wie der Spiel-Controller. [stopAfter] bricht nach so vielen Darts ab.
Future<int> seedTraining(
  GameRepository repo,
  int player,
  String gameId,
  Map<String, Object?> config,
  DateTime start, {
  double average = 62,
  int seed = 1,
  int? stopAfter,
  Duration length = const Duration(minutes: 14),
}) async {
  final bot = DartBot.forAverage(average, random: math.Random(seed));
  final game = GameCatalog.byId(gameId)!.start(config, seed)..prepare();
  final sid = await repo.startSession(playerId: player, gameId: gameId, config: config, seed: seed, startedAt: start);
  for (var seq = 0; !game.finished && seq < (stopAfter ?? 400); seq++) {
    if (game.visitClosed && game.physicalDartsInVisit > 0 && game.physicalDartsInVisit < TrainingGame.dartsPerVisit) {
      game.endVisit();
    }
    final Segment target;
    if (game is X01Solo) {
      target = DartBot.aim(game.remaining, game.dartsLeftInVisit, OutMode.double, opened: game.opened);
    } else {
      final t = game.targets.toList()..sort((a, b) => b.score.compareTo(a.score));
      target = t.isEmpty ? Segment.triple(20) : t.first;
    }
    final dart = bot.throwAt(target, at: start.add(Duration(seconds: seq * 9)));
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
  await repo.endSession(sid, result: game.result, finished: game.finished, endedAt: start.add(length));
  return sid;
}

/// X01-Match gegen einen Bot, beide Seiten werfen mit Bot-Streuung. Gesucht
/// wird ein Startwert, bei dem das Match [legs] Legs dauert und Spieler 0
/// gewinnt (bzw. verliert mit [win] = false). Gespeichert werden nur die
/// Würfe von Spieler 0, wie im `MatchController`.
Future<int> seedMatch(
  GameRepository repo,
  int player,
  DateTime start, {
  String me = 'Ich',
  String opponent = 'Robo',
  double myAverage = 68,
  double botAverage = 60,
  int legsToWin = 2,
  int legs = 3,
  bool win = true,
  bool tournament = false,
}) async {
  final format = MatchFormat(startScore: 501, legsToWin: legsToWin);
  final setup = MatchSetup(
    format: format,
    players: [MatchPlayer.human(me, profileId: player), MatchPlayer.bot(opponent, average: botAverage)],
    tournamentMatch: tournament ? 't1/r0-m0' : null,
  );
  late MatchSession session;
  for (var seed = 1;; seed++) {
    session = MatchSession(setup);
    final bots = [
      DartBot.forAverage(myAverage, random: math.Random(seed)),
      DartBot.forAverage(botAverage, random: math.Random(seed * 31 + 7)),
    ];
    var t = start;
    while (!session.match.finished) {
      final m = session.match;
      if (m.visitClosed) {
        session.endVisit();
        continue;
      }
      t = t.add(const Duration(seconds: 7));
      session.addDart(bots[m.current].next(m, at: t));
    }
    if (session.match.legs.length == legs && (session.match.winner == 0) == win) break;
  }
  final sid = await repo.startSession(
    playerId: player,
    gameId: matchGameId,
    config: {
      ...format.toJson(),
      'opponents': [opponent],
      'vsBot': true,
      if (tournament) 'tournament': true,
    },
    seed: 0,
    startedAt: start,
  );
  var seq = 0;
  for (final r in session.records) {
    if (r.player != 0) continue;
    await repo.addThrow(
      sessionId: sid,
      playerId: player,
      gameId: matchGameId,
      seq: seq++,
      visitIndex: r.visitSerial,
      counted: r.counted,
      dart: r.dart,
    );
  }
  await repo.endSession(
    sid,
    result: matchResultFor(session.match, 0, setup),
    finished: true,
    endedAt: start.add(const Duration(minutes: 21)),
  );
  return sid;
}

/// Die Daten der Entwürfe und Widget-Tests: 501-Training, Match gegen die
/// CPU über drei Legs, Cricket und eine abgebrochene Session, dazu ein paar
/// ältere Sessions für die Liste.
Future<({int x01, int match, int cricket, int aborted})> seedHistory(GameRepository repo, int player, DateTime now) async {
  DateTime at(int daysAgo, int hour, int minute) => DateTime(now.year, now.month, now.day - daysAgo, hour, minute);
  await seedTraining(repo, player, 'highscore_hunt', const {}, at(6, 18, 5), seed: 4);
  await seedTraining(repo, player, 'bobs_27', const {}, at(4, 19, 40), seed: 5, average: 70);
  await seedMatch(repo, player, at(3, 20, 10), opponent: 'Phil', botAverage: 75, win: false, legs: 2, tournament: true);
  final cricket = await seedTraining(repo, player, 'cricket', const {}, at(1, 18, 30), seed: 6);
  final aborted = await seedTraining(repo, player, 'around_the_clock', const {}, at(1, 19, 15),
      seed: 7, stopAfter: 14, length: const Duration(minutes: 3));
  final x01 = await seedTraining(repo, player, 'x01', const {'startScore': 501}, at(0, 17, 20), seed: 3);
  final match = await seedMatch(repo, player, at(0, 18, 45));
  return (x01: x01, match: match, cricket: cricket, aborted: aborted);
}
