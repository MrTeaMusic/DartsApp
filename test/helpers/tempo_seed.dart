import 'dart:math' as math;

import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';

/// Eine Session mit Würfen vom Board und gewünschtem Tempo.
///
/// [gap]: mittlerer Wurfabstand in Sekunden, [between]: Zeit vom ersten Dart
/// einer Aufnahme bis zum ersten der nächsten. Langsamere Aufnahmen treffen
/// etwas öfter das Triple (damit der Zusammenhang Tempo und Punkte etwas zeigt).
Future<int> seedTempoSession(
  GameRepository repo,
  int player,
  String gameId,
  DateTime start, {
  required int visits,
  double gap = 3.5,
  double between = 15,
  String source = 'autodartsLocal',
  math.Random? random,
  bool slowerScoresMore = true,
}) async {
  final rnd = random ?? math.Random(5);
  double gauss() => math.sqrt(-2 * math.log(1 - rnd.nextDouble())) * math.cos(2 * math.pi * rnd.nextDouble());
  final kind = DartSourceKind.values.firstWhere((k) => k.name == source);
  final sid = await repo.startSession(playerId: player, gameId: gameId, config: const {}, seed: 0, startedAt: start);
  var at = start;
  var seq = 0;
  var points = 0;
  for (var v = 0; v < visits; v++) {
    final visitGap = gap * math.exp(gauss() * 0.45);
    final slow = ((visitGap * 2 - 6) / 8).clamp(0.0, 1.0);
    final pTriple = 0.2 + (slowerScoresMore ? 0.16 * slow : 0);
    var t = at;
    for (var d = 0; d < 3; d++) {
      if (d > 0) t = t.add(Duration(milliseconds: (visitGap * math.exp(gauss() * 0.18) * 1000).round().clamp(1200, 25000)));
      final r = rnd.nextDouble();
      final seg = r < pTriple
          ? Segment.triple(20)
          : r < pTriple + 0.34
              ? Segment.single(20)
              : r < pTriple + 0.5
                  ? Segment.triple(19)
                  : r < pTriple + 0.62
                      ? Segment.single(1)
                      : r < pTriple + 0.72
                          ? Segment.single(5)
                          : r < pTriple + 0.78
                              ? Segment.double(20)
                              : Segment.miss;
      points += seg.score;
      await repo.addThrow(
        sessionId: sid,
        playerId: player,
        gameId: gameId,
        seq: seq++,
        visitIndex: v,
        counted: true,
        dart: DartThrow(segment: seg, timestamp: t, source: kind),
      );
    }
    at = at.add(Duration(milliseconds: (between * math.exp(gauss() * 0.22) * 1000).round().clamp(5000, 55000)));
  }
  await repo.endSession(
    sid,
    result: GameResult(metrics: {'average': points / (visits * 3) * 3, 'darts': visits * 3}, summary: const []),
    finished: true,
    endedAt: at.add(const Duration(seconds: 20)),
  );
  return sid;
}

/// Zehn Wochen Training, Matches und Online-Matches, das Tempo steigt von
/// etwa 4,6 auf 3,2 Sekunden je Dart. Liefert die Zahl der Sessions.
Future<int> seedTempo(GameRepository repo, int player, DateTime now, {int weeks = 10, int seed = 3}) async {
  final rnd = math.Random(seed);
  var sessions = 0;
  for (var w = weeks - 1; w >= 0; w--) {
    final base = 3.2 + 1.4 * (w / math.max(1, weeks - 1)) + (rnd.nextDouble() - 0.5) * 0.4;
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1 + 7 * w));
    final plan = [
      ('highscore_hunt', 1, 16, 14.0),
      ('x01_live', 3, 18, 30.0),
      if (w.isEven) ('x01_match', 5, 14, 26.0),
    ];
    for (final (gameId, day, visits, between) in plan) {
      final start = monday.add(Duration(days: day, hours: 19, minutes: rnd.nextInt(40)));
      if (start.isAfter(now.subtract(const Duration(hours: 1)))) continue;
      await seedTempoSession(repo, player, gameId, start,
          visits: visits, gap: base * (gameId == 'x01_match' ? 1.1 : 1), between: between, random: rnd);
      sessions++;
    }
  }
  return sessions;
}
