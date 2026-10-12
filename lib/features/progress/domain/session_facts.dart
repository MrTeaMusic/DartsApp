import '../../../core/database/app_database.dart';
import '../../board/domain/segment.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../games/domain/engine/game_definition.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/domain/engine/training_game.dart';
import '../../games/domain/game_catalog.dart';
import '../../matches/domain/match_result.dart';
import '../../matches/domain/tournament.dart';
import '../../stats/domain/game_metrics.dart';
import '../../stats/domain/stats_calculator.dart';
import '../../stats/domain/target_replay.dart';

/// Was eine abgeschlossene Session zu den Erfolgen beiträgt.
class SessionFacts {
  const SessionFacts({
    required this.gameId,
    required this.time,
    this.finished = false,
    this.darts = 0,
    this.duration = Duration.zero,
    this.tons = 0,
    this.visits140 = 0,
    this.max180 = 0,
    this.average,
    this.highestCheckout = 0,
    this.checkouts = 0,
    this.bullFinishes = 0,
    this.fastest501,
    this.bobsScore,
    this.bobsSurvived = false,
    this.doubleHits = 0,
    this.doubleRun = 0,
    this.cpuWin = false,
    this.tournamentWin = false,
    this.shanghais = 0,
  });

  final String gameId;

  /// Ende der Session; Datum für Freischaltungen.
  final DateTime time;

  /// Regulär zu Ende gespielt.
  final bool finished;
  final int darts;
  final Duration duration;

  /// Aufnahmen mit mindestens 100 bzw. 140 Punkten, 180er.
  final int tons;
  final int visits140;
  final int max180;

  /// 3-Dart-Average, nur ab [minAverageDarts] Darts.
  final double? average;
  final int highestCheckout;
  final int checkouts;
  final int bullFinishes;

  /// Wenigste Darts für ein gewonnenes 501-Leg (Double- oder Master-Out).
  final int? fastest501;

  /// Endstand in Bob's 27 (Start 27), nur wenn überstanden.
  final int? bobsScore;
  final bool bobsSurvived;

  /// Darts mit genau einem Doppel als Ziel, die es getroffen haben, und die
  /// längste Folge solcher Treffer ohne Fehlwurf dazwischen.
  final int doubleHits;
  final int doubleRun;
  final bool cpuWin;
  final bool tournamentWin;
  final int shanghais;

  static const int minAverageDarts = 18;
}

/// Spiele, in denen ein Checkout-Ereignis ein Finish ist.
const Set<String> _checkoutGames = {'checkout', 'one_twenty_one', 'catch_40', 'x01'};

/// Kennung des Finales im Turnierbaum.
const String tournamentFinalId = 'r${Tournament.roundCount - 1}-m0';

/// Wertet eine Session für die Erfolge aus. [calc] muss die Session und ihre
/// Würfe enthalten.
SessionFacts sessionFacts(StatsCalculator calc, SessionRow s) {
  final metrics = calc.metricsOfSession(s);
  final result = calc.resultOf(s);
  final details = result['details'] is Map ? result['details'] as Map : const {};
  final config = StatsCalculator.decode(s.configJson);
  final counted = calc.countedOf(s);
  int m(String k) => (metrics[k] ?? 0).toInt();

  // Volle Aufnahmen.
  var tons = 0;
  var v140 = 0;
  var v180 = 0;
  if (s.gameId.startsWith('x01')) {
    v180 = m('count180');
    v140 = m('count140') + v180;
    tons = m('count100') + v140;
  } else if (scoringGames.contains(s.gameId)) {
    for (final v in calc.visitsOf(s)) {
      if (v.length != 3) continue;
      final score = v.fold<int>(0, (a, t) => a + t.score);
      if (score >= 100) tons++;
      if (score >= 140) v140++;
      if (score == 180) v180++;
    }
  }

  // Average.
  double? average;
  final sc = calc.scoringOf(s);
  if (sc != null && sc.darts >= SessionFacts.minAverageDarts) average = sc.points / sc.darts * 3;

  // Finishes.
  var highest = 0;
  var checkouts = 0;
  var bull = 0;
  if (_checkoutGames.contains(s.gameId)) {
    for (final c in replayCheckouts(s, calc.throwsOf(s), config)) {
      checkouts++;
      if (c.value > highest) highest = c.value;
      if (c.last == Segment.bull) bull++;
    }
  } else if (s.gameId == matchGameId) {
    highest = m('highestFinish');
    checkouts = m('legsWon');
    if (m('won') == 1 && counted.isNotEmpty && segmentOf(counted.last) == Segment.bull) bull = 1;
  }

  // Schnellstes 501-Leg.
  int? fastest;
  final doubleOut = config['outMode'] != 'straight';
  if (s.gameId == 'x01' && config['startScore'] == 501 && doubleOut && config['inMode'] != 'double') {
    final legs = details['legs'];
    if (legs is List) {
      for (final l in legs) {
        if (l is Map && l['won'] == true && l['darts'] is num) {
          final d = (l['darts'] as num).toInt();
          if (fastest == null || d < fastest) fastest = d;
        }
      }
    }
  } else if (s.gameId == matchGameId && config['startScore'] == 501 && doubleOut && config['doubleIn'] != true) {
    final best = metrics['bestLegDarts'];
    if (best != null) fastest = best.toInt();
  }

  // Bob's 27.
  int? bobs;
  var survived = false;
  if (s.gameId == 'bobs_27' && config.intOf('startScore', 27) == 27 && m('completed') == 1) {
    survived = true;
    bobs = m('score');
  }

  // Doppel.
  var hits = 0;
  var run = 0;
  var bestRun = 0;
  for (final a in calc.aimedOf(s)) {
    if (a.aimedDouble == null) continue;
    if (a.onTarget) {
      hits++;
      run++;
      if (run > bestRun) bestRun = run;
    } else {
      run = 0;
    }
  }

  var duration = s.endedAt!.difference(s.startedAt);
  if (duration.isNegative) duration = Duration.zero;
  if (duration > StatsCalculator.maxSessionDuration) duration = StatsCalculator.maxSessionDuration;

  final won = s.gameId == matchGameId && m('won') == 1;
  return SessionFacts(
    gameId: s.gameId,
    time: s.endedAt!,
    finished: s.finished,
    darts: counted.length,
    duration: duration,
    tons: tons,
    visits140: v140,
    max180: v180,
    average: average,
    highestCheckout: highest,
    checkouts: checkouts,
    bullFinishes: bull,
    fastest501: fastest,
    bobsScore: bobs,
    bobsSurvived: survived,
    doubleHits: hits,
    doubleRun: bestRun,
    cpuWin: won && config['vsBot'] == true,
    tournamentWin: won && details['tournamentMatch'] == tournamentFinalId,
    shanghais: (s.gameId == 'shanghai' || s.gameId == 'jdc_challenge') ? m('shanghais') : 0,
  );
}

/// Spielt eine Session erneut durch und liefert jedes Finish (Checkout-
/// Ereignis) mit seinem Wert und dem letzten Dart. Unbekannte Spiele oder
/// Fehler ergeben eine leere Liste.
List<({int value, Segment last})> replayCheckouts(SessionRow session, List<ThrowRow> throws, Map<String, Object?> config,
    {GameDefinition? Function(String id) lookup = GameCatalog.byId}) {
  final def = lookup(session.gameId);
  if (def == null || throws.isEmpty) return const [];
  try {
    final TrainingGame game = def.start(config, session.seed)..prepare();
    final sorted = [...throws]..sort((a, b) => a.seq.compareTo(b.seq));
    final out = <({int value, Segment last})>[];
    for (final t in sorted) {
      final seg = segmentOf(t);
      if (seg == null) return const [];
      if (t.visitIndex > game.visitIndex && game.physicalDartsInVisit > 0 && game.physicalDartsInVisit < TrainingGame.dartsPerVisit) {
        game.endVisit();
      }
      game.throwDart(DartThrow(segment: seg, timestamp: t.timestamp, source: DartSourceKind.manual));
      for (final e in game.events) {
        if (e.type == GameEventType.checkout && e.value is int) out.add((value: e.value! as int, last: seg));
      }
    }
    return out;
  } on Object {
    return const [];
  }
}
