import '../../../core/database/app_database.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/domain/game_catalog.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../../games/domain/games/cricket.dart';
import '../../matches/domain/match_format.dart';
import '../../matches/domain/match_result.dart';
import '../../stats/domain/game_metrics.dart';
import '../../stats/domain/stats_calculator.dart';
import '../../stats/domain/target_replay.dart';

/// Filter der Verlaufsliste.
enum HistoryFilter { all, training, matches }

/// Eine abgeschlossene Session in der Verlaufsliste. Liest nur, was in der
/// Session-Zeile steht (ohne Würfe), damit die Liste auch bei vielen
/// Sessions schnell bleibt.
class HistoryEntry {
  HistoryEntry(this.session);
  final SessionRow session;

  late final Map<String, Object?> result = StatsCalculator.decode(session.resultJson);
  late final Map<String, Object?> config = StatsCalculator.decode(session.configJson);
  late final Map<String, num> metrics = StatsCalculator.metricsOf(session);
  late final Map<String, Object?> details = switch (result['details']) {
    final Map<String, Object?> m => m,
    _ => const {},
  };

  int get id => session.id;
  String get gameId => session.gameId;
  DateTime get startedAt => session.startedAt;
  bool get finished => session.finished;
  int get darts => session.dartCount;

  bool get isMatch => session.gameId == matchGameId;
  bool matches(HistoryFilter f) => switch (f) {
        HistoryFilter.all => true,
        HistoryFilter.training => !isMatch,
        HistoryFilter.matches => isMatch,
      };

  /// Dauer von Start bis Ende.
  Duration? get duration => session.endedAt?.difference(session.startedAt);

  /// Gegner eines Matches (aus dem Ergebnis, sonst aus der Config).
  List<String> get opponents {
    final list = details['opponents'] ?? config['opponents'];
    return list is List ? [for (final o in list) '$o'] : const [];
  }

  bool get vsBot => config['vsBot'] == true;
  bool get tournament => config['tournament'] == true || details['tournamentMatch'] != null;

  /// Gewonnen (nur Matches; `null` bei abgebrochenen).
  bool? get won => !isMatch || !finished ? null : metrics['won'] == 1;
  int get legsWon => metrics['legsWon']?.toInt() ?? 0;
  int get legsLost => metrics['legsLost']?.toInt() ?? 0;

  /// Hauptkennzahl laut [PrimaryMetric] (Schlüssel und Wert), falls die
  /// Session sie hat.
  ({String key, double value})? get keyMetric {
    final pm = PrimaryMetric.forGame(gameId);
    if (pm.onlyCompleted && metrics['completed'] != 1) return null;
    final v = metrics[pm.key];
    return v == null ? null : (key: pm.key, value: v.toDouble());
  }
}

/// Ein Dart einer Aufnahme.
class HistoryDart {
  const HistoryDart(this.segment, {this.counted = true, this.finishAttempt = false, this.hit = false, this.position});
  final Segment segment;

  /// `false`, wenn der Dart nach Bust/Checkout nicht mehr zählte.
  final bool counted;

  /// Dart auf ein Finish bzw. aufs Doppel: Das Spiel gab genau ein Double
  /// (oder Bull) als Ziel vor, im X01-Match war der Rest mit einem Dart
  /// checkbar.
  final bool finishAttempt;

  /// Versuch geschafft (nur bei [finishAttempt]).
  final bool hit;
  final BoardPoint? position;
}

/// Eine Aufnahme mit ihren Darts.
class HistoryVisit {
  const HistoryVisit({
    required this.number,
    required this.darts,
    required this.score,
    this.bust = false,
    this.checkout = false,
    this.failed = false,
    this.after,
    this.hits = 0,
    this.marks = 0,
  });

  /// Nummer ab 1 (im Leg, sonst in der Session).
  final int number;
  final List<HistoryDart> darts;

  /// Punkte der gezählten Darts (0 nach Bust).
  final int score;
  final bool bust;

  /// Finish geschafft bzw. Leg gewonnen.
  final bool checkout;

  /// Aufgabe nicht geschafft (z. B. Checkout-Versuch aufgebraucht).
  final bool failed;

  /// Stand nach der Aufnahme (Rest bzw. Punktestand), siehe
  /// [SessionDetail.afterKey].
  final String? after;

  /// Treffer auf das vorgegebene Ziel.
  final int hits;

  /// Gezählte Marks (Cricket).
  final int marks;

  /// Wert der Spalte bzw. Säule für [kind].
  int valueOf(VisitValue kind) => switch (kind) {
        VisitValue.points => score,
        VisitValue.hits => hits,
        VisitValue.marks => marks,
      };
}

/// Was je Aufnahme als Wert steht.
enum VisitValue {
  /// Punkte der Darts (Scoring-Spiele, X01, Matches, Spiele ohne Ziel).
  points,

  /// Treffer aufs vorgegebene Ziel (Around the Clock, Bob's 27 …).
  hits,

  /// Marks (Cricket).
  marks,
}

/// Ein Abschnitt der Aufnahmen: ein Leg (X01, Match) oder die ganze Session.
class HistoryLeg {
  const HistoryLeg({required this.number, required this.visits, this.set = 1, this.winner, this.winnerDarts, this.checkout});

  /// Leg-Nummer ab 1; 0 = ganze Session ohne Legs.
  final int number;
  final int set;
  final List<HistoryVisit> visits;

  /// Wer das Leg gewann (Index in [SessionDetail.players]; bei Trainings
  /// 0 = man selbst). `null` = offen oder nicht bekannt.
  final int? winner;

  /// Gezählte Darts des Siegers in diesem Leg.
  final int? winnerDarts;
  final int? checkout;
}

/// Ergebnis eines Match-Teilnehmers, wie es gespeichert wurde.
class MatchPlayerResult {
  const MatchPlayerResult({required this.name, this.bot = false, this.stats = const {}});
  final String name;
  final bool bot;

  /// Kennzahlen (`legs`, `sets`, `average`, `first9`, `checkoutRate`, …);
  /// leer, wenn sie nicht gespeichert sind (ältere Matches, Gegner).
  final Map<String, num> stats;
}

/// Wie die Aufnahmen im Diagramm erscheinen.
enum VisitChart {
  /// Punkte je Aufnahme (Scoring-Spiele, X01, Matches).
  score,

  /// Punktestand nach jeder Aufnahme (z. B. Bob's 27).
  total,

  /// Treffer aufs Ziel je Aufnahme (Around the Clock …).
  hits,

  /// Marks je Aufnahme (Cricket).
  marks,
}

/// Alles, was die Detailansicht einer Session zeigt.
class SessionDetail {
  const SessionDetail({
    required this.entry,
    required this.legs,
    required this.summary,
    required this.positions,
    required this.chart,
    this.afterKey,
    this.value = VisitValue.points,
    this.players = const [],
    this.me = 0,
    this.legsKnown = true,
  });

  final HistoryEntry entry;

  /// Aufnahmen, je Leg (Matches, X01 mit mehreren Legs) oder in einem
  /// Abschnitt mit [HistoryLeg.number] 0.
  final List<HistoryLeg> legs;

  /// Kennzahlen wie im Ergebnis des Spiels.
  final List<GameStat> summary;

  /// Positionen der Darts mit Koordinaten (Simulator, Autodarts).
  final List<BoardPoint> positions;
  final VisitChart chart;

  /// Schlüssel des Stands in [HistoryVisit.after] (`remaining`, `points`),
  /// `null` ohne Stand.
  final String? afterKey;

  /// Was je Aufnahme als Wert steht.
  final VisitValue value;

  /// Teilnehmer eines Matches, man selbst ist [me].
  final List<MatchPlayerResult> players;
  final int me;

  /// Bei älteren Matches ist nicht gespeichert, wann ein Leg endete. Dann
  /// gibt es nur die Aufnahmen ohne Rest.
  final bool legsKnown;

  List<HistoryVisit> get visits => [for (final l in legs) ...l.visits];

  Iterable<HistoryDart> get _attempts => visits.expand((v) => v.darts).where((d) => d.finishAttempt);
  int get finishAttempts => _attempts.length;
  int get finishHits => _attempts.where((d) => d.hit).length;

  /// Werte für das Diagramm, eine je Aufnahme.
  List<double> get chartValues => [
        for (final v in visits)
          switch (chart) {
            VisitChart.score => v.score.toDouble(),
            VisitChart.hits => v.hits.toDouble(),
            VisitChart.marks => v.marks.toDouble(),
            VisitChart.total => double.tryParse(v.after ?? '') ?? double.nan,
          },
      ];
}

/// Baut die Detailansicht aus Session und Würfen.
SessionDetail buildSessionDetail(SessionRow session, List<ThrowRow> throws, {String playerName = ''}) {
  final entry = HistoryEntry(session);
  final sorted = [...throws]..sort((a, b) => a.seq.compareTo(b.seq));
  final positions = [
    for (final t in sorted)
      if (t.x != null && t.y != null) BoardPoint(t.x!, t.y!),
  ];
  if (entry.isMatch) return _matchDetail(entry, sorted, positions, playerName);
  return _trainingDetail(entry, sorted, positions) ?? _plainDetail(entry, sorted, positions);
}

BoardPoint? _pos(ThrowRow t) => t.x != null && t.y != null ? BoardPoint(t.x!, t.y!) : null;

/// Würfe nach Aufnahme gruppiert, in Wurfreihenfolge.
List<List<ThrowRow>> _byVisit(List<ThrowRow> sorted) {
  final out = <List<ThrowRow>>[];
  int? current;
  for (final t in sorted) {
    if (current != t.visitIndex || out.isEmpty) {
      out.add([]);
      current = t.visitIndex;
    }
    out.last.add(t);
  }
  return out;
}

/// Ohne Spiellogik (unbekanntes Spiel): nur Darts und Punkte je Aufnahme.
SessionDetail _plainDetail(HistoryEntry entry, List<ThrowRow> sorted, List<BoardPoint> positions) {
  final visits = <HistoryVisit>[];
  for (final group in _byVisit(sorted)) {
    final darts = [
      for (final t in group)
        if (segmentOf(t) case final s?) HistoryDart(s, counted: t.counted, position: _pos(t)),
    ];
    visits.add(HistoryVisit(
      number: visits.length + 1,
      darts: darts,
      score: darts.where((d) => d.counted).fold(0, (a, d) => a + d.segment.score),
    ));
  }
  return SessionDetail(
    entry: entry,
    legs: [HistoryLeg(number: 0, visits: visits)],
    summary: _metricStats(entry),
    positions: positions,
    chart: VisitChart.score,
  );
}

/// Gespeicherte Kennzahlen als Zeilen, falls sich das Spiel nicht
/// nachspielen lässt.
List<GameStat> _metricStats(HistoryEntry entry) => [
      for (final e in entry.metrics.entries)
        if (!nonTrendMetrics.contains(e.key)) GameStat(e.key, _number(e.value)),
    ];

String _number(num v) => v == v.roundToDouble() ? '${v.round()}' : formatDecimal(v);

/// Trainingsspiel: noch einmal durchspielen wie die Statistik (siehe
/// `replayTargets`), dabei je Aufnahme Stand, Ereignisse und je Dart das
/// Ziel merken. `null`, wenn das Spiel unbekannt ist oder sich nicht
/// abspielen lässt.
SessionDetail? _trainingDetail(HistoryEntry entry, List<ThrowRow> sorted, List<BoardPoint> positions) {
  final def = GameCatalog.byId(entry.gameId);
  if (def == null || sorted.isEmpty) return null;
  try {
    final game = def.start(entry.config, entry.session.seed)..prepare();
    final legs = <HistoryLeg>[];
    var visits = <HistoryVisit>[];
    var darts = <HistoryDart>[];
    var events = <GameEventType>{};
    var hits = 0;
    var marks = 0;
    var anyTargets = false;
    String? afterKey;
    var multiLeg = false;
    int countedMarks() => game is CricketTraining ? game.countedMarks : 0;

    void flush() {
      if (darts.isEmpty) return;
      final display = game.display;
      final key = display.headlineKey;
      final stand = key == 'remaining' || key == 'points';
      if (stand) afterKey ??= key;
      final checkout = events.contains(GameEventType.checkout);
      final failed = events.contains(GameEventType.failed);
      final bust = events.contains(GameEventType.bust);
      visits.add(HistoryVisit(
        number: visits.length + 1,
        darts: darts,
        score: bust ? 0 : darts.where((d) => d.counted).fold(0, (a, d) => a + d.segment.score),
        bust: bust,
        checkout: checkout,
        failed: failed && !checkout,
        after: stand && key == afterKey && !checkout && !failed ? display.headline : null,
        hits: hits,
        marks: marks,
      ));
      if (events.contains(GameEventType.legComplete)) {
        multiLeg = true;
        legs.add(HistoryLeg(number: legs.length + 1, visits: visits, winner: checkout ? 0 : null));
        visits = [];
      }
      darts = [];
      events = {};
      hits = 0;
      marks = 0;
    }

    int? visitIndex;
    for (final t in sorted) {
      final seg = segmentOf(t);
      if (seg == null) return null;
      if (visitIndex != null && t.visitIndex != visitIndex) {
        if (t.visitIndex > game.visitIndex &&
            game.physicalDartsInVisit > 0 &&
            game.physicalDartsInVisit < 3) {
          game.endVisit();
          events.addAll(game.events.map((e) => e.type));
        }
        flush();
      }
      visitIndex = t.visitIndex;
      final targets = game.targets;
      if (targets.isNotEmpty) anyTargets = true;
      final before = game.dartsThrown;
      final marksBefore = countedMarks();
      game.throwDart(DartThrow(segment: seg, timestamp: t.timestamp, source: DartSourceKind.manual));
      final counted = game.dartsThrown > before;
      marks += countedMarks() - marksBefore;
      events.addAll(game.events.map((e) => e.type));
      final aimed = targets.length == 1 && targets.first.isDouble ? targets.first : null;
      if (counted && targets.contains(seg)) hits++;
      darts.add(HistoryDart(
        seg,
        counted: counted,
        finishAttempt: counted && aimed != null,
        hit: aimed == seg,
        position: _pos(t),
      ));
    }
    flush();
    if (visits.isNotEmpty || legs.isEmpty) {
      legs.add(HistoryLeg(number: multiLeg ? legs.length + 1 : 0, visits: visits));
    }
    // Ein einzelnes Leg braucht keine Überschrift.
    if (legs.length == 1 && legs.first.number != 0) {
      final only = legs.removeLast();
      legs.add(HistoryLeg(number: 0, visits: only.visits, winner: only.winner));
    }
    // Punkte nur, wo auf Punkte geworfen wird; sonst zählt, was das Spiel
    // misst: Marks (Cricket) oder Treffer aufs Ziel.
    final value = isVisitScoringGame(entry.gameId)
        ? VisitValue.points
        : game is CricketTraining
            ? VisitValue.marks
            : anyTargets
                ? VisitValue.hits
                : VisitValue.points;
    final chart = switch (value) {
      VisitValue.points => afterKey == 'points' ? VisitChart.total : VisitChart.score,
      VisitValue.hits => afterKey == 'points' ? VisitChart.total : VisitChart.hits,
      VisitValue.marks => VisitChart.marks,
    };
    return SessionDetail(
      entry: entry,
      legs: legs,
      summary: game.result.summary,
      positions: positions,
      chart: chart,
      afterKey: afterKey,
      value: value,
    );
  } on Object {
    return null;
  }
}

/// X01-Match: nur die eigenen Würfe sind gespeichert. Seit dem Spielverlauf
/// steht im Ergebnis, mit welcher Aufnahme jedes Leg endete und wer es
/// gewann; damit lassen sich Rest und Finish-Versuche je Leg nachrechnen.
/// Ältere Matches haben das nicht; wurden dort alle Legs selbst gewonnen,
/// endet jedes Leg mit dem eigenen Checkout und es geht trotzdem.
SessionDetail _matchDetail(HistoryEntry entry, List<ThrowRow> sorted, List<BoardPoint> positions, String playerName) {
  final format = MatchFormat.fromJson(entry.details['format'] ?? entry.config);
  final groups = _byVisit(sorted);
  final storedPlayers = entry.details['players'];
  final storedLegs = entry.details['legs'];
  final me = (entry.details['player'] as num?)?.toInt() ?? 0;

  final players = <MatchPlayerResult>[];
  if (storedPlayers is List && storedPlayers.isNotEmpty) {
    for (final p in storedPlayers) {
      final m = p is Map ? p : const {};
      players.add(MatchPlayerResult(
        name: '${m['name'] ?? '?'}',
        bot: m['bot'] == true,
        stats: {for (final e in m.entries) if (e.value is num) '${e.key}': e.value as num},
      ));
    }
  } else {
    players.add(MatchPlayerResult(name: playerName, stats: _ownStats(entry)));
    players.addAll([for (final o in entry.opponents) MatchPlayerResult(name: o, bot: entry.vsBot)]);
  }
  final self = me.clamp(0, players.length - 1);

  final legs = <HistoryLeg>[];
  var legsKnown = true;
  if (storedLegs is List) {
    var i = 0;
    for (final (n, l) in storedLegs.indexed) {
      final m = l is Map ? l : const {};
      final end = (m['visit'] as num?)?.toInt() ?? -1;
      final own = <List<ThrowRow>>[];
      while (i < groups.length && groups[i].first.visitIndex <= end) {
        own.add(groups[i++]);
      }
      legs.add(HistoryLeg(
        number: n + 1,
        set: (m['set'] as num?)?.toInt() ?? 1,
        visits: _x01Visits(own, format),
        winner: (m['winner'] as num?)?.toInt(),
        winnerDarts: (m['darts'] as num?)?.toInt(),
        checkout: (m['checkout'] as num?)?.toInt(),
      ));
    }
    if (i < groups.length) {
      legs.add(HistoryLeg(number: legs.length + 1, visits: _x01Visits(groups.sublist(i), format)));
    }
  } else if (entry.legsLost == 0) {
    // Alle Legs selbst gewonnen: jedes endet mit dem eigenen Checkout.
    final visits = _x01Visits(groups, format);
    var current = <HistoryVisit>[];
    for (final v in visits) {
      current.add(v);
      if (v.checkout) {
        legs.add(HistoryLeg(number: legs.length + 1, visits: _renumber(current), winner: self));
        current = [];
      }
    }
    if (current.isNotEmpty) legs.add(HistoryLeg(number: legs.length + 1, visits: _renumber(current)));
  } else {
    legsKnown = false;
    legs.add(HistoryLeg(
      number: 0,
      visits: [
        for (final (n, g) in groups.indexed)
          HistoryVisit(
            number: n + 1,
            darts: [
              for (final t in g)
                if (segmentOf(t) case final s?) HistoryDart(s, counted: t.counted, position: _pos(t)),
            ],
            score: g.where((t) => t.counted).fold(0, (a, t) => a + t.score),
          ),
      ],
    ));
  }
  return SessionDetail(
    entry: entry,
    legs: legs,
    summary: _matchSummary(players[self].stats.isEmpty ? _ownStats(entry) : players[self].stats, entry),
    positions: positions,
    chart: VisitChart.score,
    afterKey: legsKnown ? 'remaining' : null,
    players: players,
    me: self,
    legsKnown: legsKnown,
  );
}

List<HistoryVisit> _renumber(List<HistoryVisit> visits) => [
      for (final (i, v) in visits.indexed)
        HistoryVisit(
          number: i + 1,
          darts: v.darts,
          score: v.score,
          bust: v.bust,
          checkout: v.checkout,
          after: v.after,
        ),
    ];

/// Rechnet die eigenen Aufnahmen eines Legs nach X01-Regeln durch (wie
/// `X01Match`): Rest nach jeder Aufnahme, Bust und Darts aufs Finish.
List<HistoryVisit> _x01Visits(List<List<ThrowRow>> groups, MatchFormat format) {
  var remaining = format.startScore;
  var opened = !format.doubleIn;
  final out = <HistoryVisit>[];
  for (final g in groups) {
    final startRemaining = remaining;
    final startOpened = opened;
    var points = 0;
    var bust = false;
    var checkout = false;
    final darts = <HistoryDart>[];
    for (final t in g) {
      final s = segmentOf(t);
      if (s == null) continue;
      if (!t.counted || bust || checkout) {
        darts.add(HistoryDart(s, counted: false, position: _pos(t)));
        continue;
      }
      final attempt = opened && CheckoutRules.isCheckout(remaining, darts: 1, out: format.outMode);
      if (!opened) {
        if (!s.isDouble) {
          darts.add(HistoryDart(s, position: _pos(t)));
          continue;
        }
        opened = true;
      }
      if (CheckoutRules.isBust(remaining, s, format.outMode)) {
        bust = true;
        remaining = startRemaining;
        opened = startOpened;
        points = 0;
        darts.add(HistoryDart(s, finishAttempt: attempt, position: _pos(t)));
        continue;
      }
      remaining -= s.score;
      points += s.score;
      if (remaining == 0) checkout = true;
      darts.add(HistoryDart(s, finishAttempt: attempt, hit: attempt && checkout, position: _pos(t)));
    }
    out.add(HistoryVisit(
      number: out.length + 1,
      darts: darts,
      score: points,
      bust: bust,
      checkout: checkout,
      after: checkout ? null : '$remaining',
    ));
    if (checkout) {
      remaining = format.startScore;
      opened = !format.doubleIn;
    }
  }
  return out;
}

/// Eigene Kennzahlen aus den gespeicherten Metriken (ältere Matches).
Map<String, num> _ownStats(HistoryEntry entry) {
  final m = entry.metrics;
  return {
    'legs': m['legsWon'] ?? 0,
    'sets': ?m['setsWon'],
    'darts': m['darts'] ?? entry.darts,
    if ((m['darts'] ?? 0) > 0) 'average': m['average'] ?? 0,
    'first9': ?m['first9'],
    if ((m['checkoutDarts'] ?? 0) > 0) 'checkoutRate': m['checkoutRate'] ?? 0,
    'highestFinish': m['highestFinish'] ?? 0,
    'bestLegDarts': ?m['bestLegDarts'],
    'count100': m['count100'] ?? 0,
    'count140': m['count140'] ?? 0,
    'count180': m['count180'] ?? 0,
  };
}

/// Kennzahlen-Kacheln eines Matches (eigene Werte).
List<GameStat> _matchSummary(Map<String, num> s, HistoryEntry entry) => [
      GameStat('average', formatDecimal(s['average'])),
      GameStat('first9Average', formatDecimal(s['first9'])),
      GameStat('checkoutRate', formatPercent(s['checkoutRate'])),
      GameStat('highestFinish', (s['highestFinish'] ?? 0) == 0 ? '–' : '${s['highestFinish']}'),
      GameStat('bestLegDarts', s['bestLegDarts'] == null ? '–' : '${s['bestLegDarts']}'),
      GameStat('scores100', '${s['count100'] ?? 0} / ${s['count140'] ?? 0} / ${s['count180'] ?? 0}'),
    ];
