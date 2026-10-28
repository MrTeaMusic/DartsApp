import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';

/// SYNTHETISCH: Matches für die Tests und Bilder des Haus-Elo. Alle Namen sind
/// erfunden („Ben“, „Anna“, „Gegner“, Bots), nichts stammt aus echten Daten.
///
/// Die Form der Ergebnisse folgt `matchResultFor` (Bot- und Mitspieler-
/// Matches) und `buildImportPlan` (Online-Import).
enum EloKind { bot, local, online }

var _sid = 0;

/// Ergebnis und Config eines Matches aus Sicht von Spieler 0.
({Map<String, Object?> config, Map<String, Object?> result, String gameId}) eloMatchData(
  EloKind kind, {
  String opponent = 'Bot',
  bool won = true,
  double myAverage = 55,
  double opponentAverage = 50,
  double? botAverage,
  int legsWon = 3,
  int legsLost = 1,
  bool tournament = false,
  bool finished = true,
}) {
  final players = [
    {'name': 'Ben', 'bot': false, 'legs': legsWon, 'average': myAverage},
    {
      'name': opponent,
      'bot': kind == EloKind.bot,
      'botAverage': ?(kind == EloKind.bot ? (botAverage ?? opponentAverage) : null),
      'legs': legsLost,
      'average': opponentAverage,
    },
  ];
  final metrics = <String, num>{
    'darts': 90,
    'average': myAverage,
    'legsWon': legsWon,
    'legsLost': legsLost,
    'legs': legsWon + legsLost,
    'won': won ? 1 : 0,
    'completed': finished ? 1 : 0,
  };
  final details = <String, Object?>{
    'opponents': [opponent],
    'won': won,
    'player': 0,
    'players': players,
  };
  if (kind == EloKind.online) {
    final info = {'id': 'm-${++_sid}', 'origin': 'file', 'me': 'Ben', 'opponent': opponent};
    return (
      gameId: 'x01_live',
      config: {'source': 'autodartsImport', 'mode': 'import', 'import': info},
      result: {'metrics': metrics, 'details': {...details, 'mode': 'import', 'import': info}},
    );
  }
  return (
    gameId: 'x01_match',
    config: {
      'startScore': 501,
      'opponents': [opponent],
      'vsBot': kind == EloKind.bot,
      if (tournament) 'tournament': true,
    },
    result: {'metrics': metrics, 'details': details},
  );
}

var _rowId = 1000;

/// Eine fertige Session als Zeile, ohne Datenbank (für Rechner-Tests).
SessionRow eloRow(
  EloKind kind,
  DateTime start, {
  String opponent = 'Bot',
  bool won = true,
  double myAverage = 55,
  double opponentAverage = 50,
  double? botAverage,
  bool finished = true,
  String? gameId,
  String? uid,
}) {
  final d = eloMatchData(kind,
      opponent: opponent, won: won, myAverage: myAverage, opponentAverage: opponentAverage, botAverage: botAverage, finished: finished);
  final id = ++_rowId;
  return SessionRow(
    id: id,
    uid: uid ?? 'u${id.toString().padLeft(6, '0')}',
    playerId: 1,
    gameId: gameId ?? d.gameId,
    configJson: jsonEncode(d.config),
    seed: 0,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 20)),
    finished: finished,
    resultJson: jsonEncode(d.result),
    dartCount: 1,
  );
}

StatsCalculator eloCalc(List<SessionRow> rows, {DateTime? now}) =>
    StatsCalculator(sessions: rows, throws: const [], now: now ?? DateTime(2026, 10, 28, 12));

/// Speichert ein Match wie die App (eine Session mit einem Dart, denn eine
/// Session ohne Würfe löscht `endSession`). Gibt die Session-Id zurück.
Future<int> seedEloMatch(
  GameRepository repo,
  int player,
  DateTime start,
  EloKind kind, {
  String opponent = 'Bot',
  bool won = true,
  double myAverage = 55,
  double opponentAverage = 50,
  double? botAverage,
  int legsWon = 3,
  int legsLost = 1,
  bool tournament = false,
  bool finished = true,
}) async {
  final d = eloMatchData(kind,
      opponent: opponent,
      won: won,
      myAverage: myAverage,
      opponentAverage: opponentAverage,
      botAverage: botAverage,
      legsWon: legsWon,
      legsLost: legsLost,
      tournament: tournament,
      finished: finished);
  final sid = await repo.startSession(playerId: player, gameId: d.gameId, config: d.config, seed: 0, startedAt: start);
  await repo.addThrow(
    sessionId: sid,
    playerId: player,
    gameId: d.gameId,
    seq: 0,
    visitIndex: 0,
    counted: true,
    dart: DartThrow(segment: Segment.single(20), timestamp: start, source: DartSourceKind.manual),
  );
  await repo.endSession(
    sid,
    result: GameResult(metrics: (d.result['metrics']! as Map).cast<String, num>(), summary: const [], details: (d.result['details']! as Map).cast<String, Object?>()),
    finished: finished,
    endedAt: start.add(const Duration(minutes: 20)),
  );
  return sid;
}

/// Eine Demo-Historie von 25 Matches in den letzten 60 Tagen: Bots, Online-
/// Gegner und Mitspieler, mit Aufs und Abs. Älteste zuerst; gibt die
/// Session-Ids in dieser Reihenfolge zurück.
Future<List<int>> seedEloHistory(GameRepository repo, int player, DateTime now) async {
  DateTime at(int daysAgo, int hour) => DateTime(now.year, now.month, now.day - daysAgo, hour, 15);
  // (Tage her, Uhrzeit, Art, Gegner, Sieg, eigener Average, Gegner-Average, Legs)
  const plan = <(int, int, EloKind, String, bool, double, double, (int, int))>[
    (58, 19, EloKind.bot, 'CPU 40', true, 46.0, 40.0, (3, 1)),
    (56, 20, EloKind.bot, 'CPU 40', true, 48.5, 40.0, (3, 0)),
    (53, 18, EloKind.local, 'Anna', true, 47.0, 41.0, (3, 2)),
    (50, 21, EloKind.bot, 'CPU 55', false, 47.5, 55.0, (1, 3)),
    (47, 19, EloKind.online, 'Lukas77', false, 49.0, 58.5, (1, 3)),
    (44, 20, EloKind.bot, 'CPU 55', true, 52.0, 55.0, (3, 2)),
    (41, 19, EloKind.local, 'Anna', true, 51.0, 44.0, (3, 1)),
    (38, 22, EloKind.online, 'Lukas77', false, 50.5, 59.0, (2, 3)),
    (35, 19, EloKind.bot, 'CPU 40', true, 53.0, 40.0, (3, 0)),
    (32, 20, EloKind.online, 'DartFee', true, 54.0, 49.5, (3, 2)),
    (29, 18, EloKind.bot, 'CPU 70', false, 52.0, 70.0, (0, 3)),
    (27, 19, EloKind.local, 'Anna', false, 48.0, 49.0, (2, 3)),
    (24, 20, EloKind.online, 'Lukas77', true, 57.0, 56.0, (3, 2)),
    (22, 21, EloKind.bot, 'CPU 55', true, 56.5, 55.0, (3, 1)),
    (20, 19, EloKind.online, 'DartFee', true, 55.0, 50.0, (3, 0)),
    (17, 18, EloKind.bot, 'CPU 70', false, 55.5, 70.0, (1, 3)),
    (15, 20, EloKind.local, 'Anna', true, 54.5, 46.0, (3, 0)),
    (13, 19, EloKind.online, 'Pfeilwurf', false, 53.0, 66.0, (0, 3)),
    (11, 21, EloKind.bot, 'CPU 55', true, 57.5, 55.0, (3, 2)),
    (9, 19, EloKind.online, 'Lukas77', true, 60.0, 57.5, (3, 1)),
    (7, 20, EloKind.bot, 'CPU 70', true, 62.0, 70.0, (3, 2)),
    (5, 18, EloKind.local, 'Anna', true, 58.0, 47.0, (3, 0)),
    (3, 19, EloKind.online, 'Pfeilwurf', false, 58.5, 64.0, (2, 3)),
    (2, 21, EloKind.bot, 'CPU 40', false, 51.0, 40.0, (2, 3)),
    (1, 20, EloKind.online, 'DartFee', false, 54.0, 52.0, (1, 3)),
  ];
  final ids = <int>[];
  for (final (days, hour, kind, opponent, won, mine, theirs, legs) in plan) {
    ids.add(await seedEloMatch(repo, player, at(days, hour), kind,
        opponent: opponent,
        won: won,
        myAverage: mine,
        opponentAverage: theirs,
        botAverage: kind == EloKind.bot ? theirs : null,
        legsWon: legs.$1,
        legsLost: legs.$2));
  }
  return ids;
}
