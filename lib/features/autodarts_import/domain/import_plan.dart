import '../../autodarts_live/domain/live_recorder.dart';
import '../../autodarts_live/domain/live_stats.dart' show autodartsLiveX01GameId;
import '../../autodarts_live/domain/live_x01.dart';
import '../../autodarts_live/presentation/autodarts_live_controller.dart' show liveSessionResult;
import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../../matches/domain/match_format.dart';
import 'imported_match.dart';

/// Spiel, unter dem importierte Matches gespeichert werden: dasselbe wie die
/// Live-Sessions mit „X01 mitzählen“ (`x01_live`), damit Verlauf, Statistik
/// „Online“, Streuung und Doppelquote sie ohne Änderung auswerten.
const String importGameId = autodartsLiveX01GameId;

/// Quelle der gespeicherten Darts (Spalte `throws.source`). Bewusst nicht
/// `autodartsLocal`: Die Zeiten eines Imports messen nicht das Werfen und
/// bleiben aus der Wurftempo-Auswertung.
const String importThrowSource = 'autodartsImport';

/// Wer bin ich? Gibt den Index des eigenen Spielers zurück, wenn der Name
/// [myName] (ohne Groß-/Kleinschreibung) genau einen der beiden trifft.
/// `null` heißt: nachfragen.
int? identifyMe(ImportedMatch match, String myName) {
  final wanted = myName.trim().toLowerCase();
  if (wanted.isEmpty) return null;
  final hits = [
    for (final (i, p) in match.players.indexed)
      if (p.name.trim().toLowerCase() == wanted) i,
  ];
  return hits.length == 1 ? hits.single : null;
}

/// Ein eigener Dart, wie er in die Datenbank kommt.
typedef PlannedDart = ({Segment segment, BoardPoint? position, DateTime at, int visitIndex, bool counted});

/// Alles, was zum Speichern eines importierten Matches nötig ist, fertig
/// gerechnet. Reine Daten, noch nichts geschrieben.
class ImportPlan {
  ImportPlan({
    required this.match,
    required this.me,
    required this.darts,
    required this.x01,
    required this.marks,
    required this.config,
    required this.result,
    required this.startedAt,
    required this.endedAt,
    required this.finished,
    required this.won,
    required this.legsMe,
    required this.legsOpponent,
    required this.ownVisits,
    required this.warnings,
  });

  final ImportedMatch match;

  /// Index des eigenen Spielers in [ImportedMatch.players].
  final int me;
  final List<PlannedDart> darts;
  final LiveX01Config x01;
  final List<LegMark> marks;

  /// `sessions.config_json` (mit der Autodarts-Match-Id).
  final Map<String, Object?> config;
  final GameResult result;
  final DateTime startedAt;
  final DateTime endedAt;
  final bool finished;

  /// Gewonnen; `null`, solange offen oder unentschieden.
  final bool? won;
  final int legsMe;
  final int legsOpponent;

  /// Aufnahmen des eigenen Spielers.
  final int ownVisits;
  final List<String> warnings;

  ImportedPlayer get myPlayer => match.players[me];
  ImportedPlayer get opponent => match.players[1 - me];
  String get id => match.id;
}

/// Rechnet das Match aus Sicht des Spielers [me] durch.
///
/// * Die eigenen Darts werden Aufnahme für Aufnahme gespeichert (Aufnahme-
///   Nummer über das ganze Match), mit Position, soweit geliefert.
/// * Legs, die der Gegner gewinnt, werden als „Leg verloren“ nach den
///   eigenen Darts des Legs markiert, so wie der Live-Modus es tut. Damit
///   rechnet [LiveX01.replay] genau dieselben Legs, Checkouts und Busts wie
///   bei einer Live-Session.
/// * Der Gegner wird nur im Ergebnis gespeichert (Name, Kennzahlen, Aufnahmen
///   als Feldnamen), nie als Darts: Seine Würfe zählen in keiner Statistik.
ImportPlan buildImportPlan(
  ImportedMatch match, {
  required int me,
  DateTime? now,
  String origin = 'file',
}) {
  assert(match.players.length == 2 && (me == 0 || me == 1));
  final clock = now ?? DateTime.now();
  final opp = 1 - me;
  final config = LiveX01Config(startScore: match.startScore, outMode: match.outMode);
  final warnings = [...match.warnings];

  // Legs: Sieger, Darts und Finish je Leg; eigene Darts und Marken.
  final ownVisits = <List<ImportedDart>>[];
  final ownTurnTimes = <DateTime?>[];
  final oppVisits = <List<Segment>>[];
  final ownMarks = <LegMark>[];
  final oppMarks = <LegMark>[];
  final storedLegs = <Map<String, Object?>>[];
  var ownDartCount = 0;
  var oppDartCount = 0;
  var legsMe = 0;
  var legsOpp = 0;
  var lastOwnVisit = -1;
  for (final leg in match.legs) {
    final sim = _simulate(leg, match);
    final winner = leg.winner ?? sim.winner;
    if (leg.winner != null && sim.winner != null && leg.winner != sim.winner) {
      warnings.add('Leg ${leg.leg}: Sieger laut Daten und laut Nachrechnen unterscheiden sich.');
    }
    final legOwnVisitsStart = ownVisits.length;
    for (final t in leg.turns) {
      if (t.player == me) {
        ownVisits.add(t.darts);
        ownTurnTimes.add(t.at);
        ownDartCount += t.darts.length;
      } else {
        oppVisits.add([for (final d in t.darts) d.segment]);
        oppDartCount += t.darts.length;
      }
    }
    if (ownVisits.length > legOwnVisitsStart) lastOwnVisit = ownVisits.length - 1;
    if (winner == me) {
      legsMe++;
    } else if (winner == opp) {
      legsOpp++;
      ownMarks.add((at: ownDartCount, kind: LegMarkKind.lost));
    }
    if (winner != null && winner != opp) oppMarks.add((at: oppDartCount, kind: LegMarkKind.lost));
    storedLegs.add({
      'set': leg.set,
      'leg': leg.leg,
      'winner': winner == null ? null : (winner == me ? 0 : 1),
      'darts': sim.winner == null || winner != sim.winner ? null : sim.darts,
      'checkout': sim.winner == null || winner != sim.winner ? null : sim.finish,
      'visit': lastOwnVisit,
      'opp': [
        for (final t in leg.turns)
          if (t.player == opp) [for (final d in t.darts) d.segment.name],
      ],
    });
  }

  // Eigene Darts mit Zeit und Aufnahme-Nummer.
  final times = _fillTimes([for (final (i, v) in ownVisits.indexed) for (final d in v) d.at ?? ownTurnTimes[i]], match.finishedAt ?? clock);
  final planned = <PlannedDart>[];
  final recorded = <RecordedDart>[];
  var n = 0;
  for (final (vi, v) in ownVisits.indexed) {
    for (final d in v) {
      final at = times[n++];
      recorded.add((
        dart: DartThrow(segment: d.segment, position: d.position, timestamp: at, source: DartSourceKind.autodartsLocal),
        visitIndex: vi,
      ));
    }
  }
  final replay = LiveX01.replay(
    config,
    [for (final v in ownVisits) [for (final d in v) d.segment]],
    ownMarks,
    visitOpen: false,
  );
  for (var i = 0; i < recorded.length; i++) {
    final r = recorded[i];
    planned.add((
      segment: r.dart.segment,
      position: r.dart.position,
      at: r.dart.timestamp,
      visitIndex: r.visitIndex,
      counted: i < replay.counted.length ? replay.counted[i] : true,
    ));
  }

  final dataLost = legsOpp;
  if (replay.legsWon != legsMe || replay.legsLost != dataLost) {
    warnings.add(
      'Nachgerechnete Legs (${replay.legsWon}:${replay.legsLost}) weichen von den Daten ($legsMe:$legsOpp) ab; '
      'es gelten die Legs aus den Daten.',
    );
  }

  // Ergebnis des Spielers wie bei einer Live-Session, dazu Gegner und Legs.
  final base = liveSessionResult(recorded, config, ownMarks);
  final oppReplay = LiveX01.replay(config, oppVisits, oppMarks, visitOpen: false);
  final ownStats = _playerStats(base.metrics, legsMe);
  final oppStats = _playerStats(oppReplay.result(const {}).metrics, legsOpp);
  final finished = match.finished && match.legs.every((l) => l.turns.isNotEmpty);
  final bool? won = finished && legsMe != legsOpp ? legsMe > legsOpp : null;
  final format = MatchFormat(
    startScore: match.startScore,
    outMode: match.outMode,
    legsToWin: (legsMe > legsOpp ? legsMe : legsOpp).clamp(1, 50),
  );

  final startedAt = times.isEmpty ? clock : times.first;
  var endedAt = times.isEmpty ? clock : times.last;
  final finishedAt = match.finishedAt;
  if (finishedAt != null && finishedAt.isAfter(endedAt)) endedAt = finishedAt;

  final me0 = match.players[me].name;
  final opp0 = match.players[opp].name;
  final importInfo = <String, Object?>{
    'id': match.id,
    'origin': origin,
    'importedAt': clock.toIso8601String(),
    'me': me0,
    'opponent': opp0,
    if (warnings.isNotEmpty) 'warnings': warnings.take(8).toList(),
  };
  final metrics = <String, num>{
    ...base.metrics,
    'legsWon': legsMe,
    'legsLost': legsOpp,
    'legs': legsMe + legsOpp,
    'won': ?(won == null ? null : (won ? 1 : 0)),
  };
  final result = GameResult(
    metrics: metrics,
    summary: const [],
    details: {
      ...base.details,
      'source': importThrowSource,
      'mode': 'import',
      'import': importInfo,
      'opponents': [opp0],
      'format': format.toJson(),
      'won': ?won,
      'player': 0,
      'players': [
        {'name': me0, ...ownStats},
        {'name': opp0, ...oppStats},
      ],
      'matchLegs': storedLegs,
    },
  );

  return ImportPlan(
    match: match,
    me: me,
    darts: planned,
    x01: config,
    marks: ownMarks,
    config: {
      'source': importThrowSource,
      'mode': 'import',
      'x01': config.toJson(),
      'import': importInfo,
    },
    result: result,
    startedAt: startedAt,
    endedAt: endedAt,
    finished: finished,
    won: won,
    legsMe: legsMe,
    legsOpponent: legsOpp,
    ownVisits: ownVisits.length,
    warnings: warnings,
  );
}

/// Kennzahlen eines Spielers im Format der Bot-Matches (`matchPlayerStats`).
Map<String, Object?> _playerStats(Map<String, num> m, int legs) => {
      'legs': legs,
      'sets': 0,
      'darts': m['darts'] ?? 0,
      if ((m['darts'] ?? 0) > 0) 'average': m['average'] ?? 0,
      'first9': ?m['first9'],
      if ((m['checkoutDarts'] ?? 0) > 0) 'checkoutRate': m['checkoutRate'] ?? 0,
      'highestFinish': m['highestFinish'] ?? 0,
      'bestLegDarts': ?m['bestLegDarts'],
      'count100': m['count100'] ?? 0,
      'count140': m['count140'] ?? 0,
      'count180': m['count180'] ?? 0,
    };

/// Zeiten auffüllen: bekannte bleiben, fehlende folgen dem Vorgänger im
/// Abstand von sechs Sekunden; nie rückwärts.
List<DateTime> _fillTimes(List<DateTime?> raw, DateTime end) {
  const step = Duration(seconds: 6);
  final firstKnown = raw.whereType<DateTime>().firstOrNull;
  var prev = firstKnown ?? end.subtract(step * raw.length);
  final out = <DateTime>[];
  for (final t in raw) {
    var at = t ?? (out.isEmpty ? prev : prev.add(step));
    if (at.isBefore(prev)) at = prev;
    out.add(at);
    prev = at;
  }
  return out;
}

/// Spielt ein Leg beider Spieler durch (nur Rest, Bust, Checkout): Sieger,
/// seine Darts und der Finish-Wert (Rest vor der Aufnahme). Dient als
/// Rückfall, wenn die Daten keinen Sieger nennen, und für die Gegenprobe.
({int? winner, int darts, int finish}) _simulate(ImportedLeg leg, ImportedMatch match) {
  final remaining = {0: match.startScore, 1: match.startScore};
  final darts = {0: 0, 1: 0};
  for (final t in leg.turns) {
    final start = remaining[t.player]!;
    var rest = start;
    for (final d in t.darts) {
      darts[t.player] = darts[t.player]! + 1;
      if (CheckoutRules.isBust(rest, d.segment, match.outMode)) {
        rest = start;
        break;
      }
      rest -= d.segment.score;
      if (rest == 0) return (winner: t.player, darts: darts[t.player]!, finish: start);
    }
    remaining[t.player] = rest;
  }
  return (winner: null, darts: 0, finish: 0);
}
