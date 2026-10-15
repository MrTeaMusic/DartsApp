import '../../board/domain/segment.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../../games/domain/games/checkout/setup_advisor.dart';

/// Einstellungen für „X01 mitzählen“ in Autodarts Live.
class LiveX01Config {
  const LiveX01Config({this.startScore = 501, this.outMode = OutMode.double});

  static const List<int> startScores = [301, 501, 701];

  final int startScore;
  final OutMode outMode;

  Map<String, Object?> toJson() => {'startScore': startScore, 'outMode': outMode.name};

  /// Aus der gespeicherten Config einer Session (`config['x01']`); `null`,
  /// wenn [json] keine Map ist.
  static LiveX01Config? fromJson(Object? json) => json is Map
      ? LiveX01Config(
          startScore: (json['startScore'] as num?)?.toInt() ?? 501,
          outMode: OutMode.values.where((o) => o.name == json['outMode']).firstOrNull ?? OutMode.double,
        )
      : null;

  @override
  bool operator ==(Object other) => other is LiveX01Config && other.startScore == startScore && other.outMode == outMode;

  @override
  int get hashCode => Object.hash(startScore, outMode);
}

/// Von Hand gesetztes Leg-Ende (die Darts des Gegners sieht DartLab nicht).
enum LegMarkKind {
  /// Der Gegner hat gecheckt: Leg verloren, das nächste beginnt beim Startwert.
  lost,

  /// Rest stimmt nicht (z. B. Dart verpasst): Rest zurück auf den Startwert,
  /// das Leg wird nicht gewertet.
  restart,
}

/// Markierung vor dem Dart mit der Nummer [at] (Zählung über die ganze
/// Session; [at] = Zahl der Darts beim Drücken).
typedef LegMark = ({int at, LegMarkKind kind});

/// Leg-Markierungen aus dem gespeicherten Ergebnis (`details['marks']`).
List<LegMark> legMarksFromJson(Object? json) => [
      if (json is List)
        for (final m in json)
          if (m is Map && m['at'] is num)
            (
              at: (m['at'] as num).toInt(),
              kind: LegMarkKind.values.where((k) => k.name == m['kind']).firstOrNull ?? LegMarkKind.lost,
            ),
    ];

/// Ein abgeschlossenes Leg.
class LiveX01Leg {
  const LiveX01Leg({
    required this.darts,
    required this.points,
    required this.first9,
    required this.checkout,
    required this.won,
  });

  /// Gezählte Darts.
  final int darts;

  /// Abgezogene Punkte (Bust-Aufnahmen zählen 0).
  final int points;

  /// 3-Dart-Schnitt der ersten bis zu neun Darts.
  final double? first9;

  /// Gecheckter Rest, 0 ohne Checkout.
  final int checkout;
  final bool won;
}

/// Stand von „X01 mitzählen“, aus den Aufnahmen der Session berechnet.
///
/// Wird bei jeder Änderung komplett neu abgespielt ([LiveX01.replay]), damit
/// Korrekturen am Board und „Leg verloren“ ohne eigenen Rückgängig-Code
/// stimmen. Regeln wie X01-Solo (Bust setzt den Rest der Aufnahme zurück und
/// beendet sie, Checkout beendet das Leg); weitere Darts nach Bust oder
/// Checkout in derselben Aufnahme zählen nicht.
class LiveX01 {
  LiveX01._(this.config);

  final LiveX01Config config;

  /// Abgeschlossene Legs (ohne neu gestartete).
  final List<LiveX01Leg> legs = [];

  /// Je Dart der Session: zählt er für X01? (`false` nach Bust/Checkout.)
  final List<bool> counted = [];

  /// Je Dart der Session das Doppel, auf das er zum Finish geworfen wurde
  /// (1–20, 25 = Bull), sonst `null`. Wie bei X01-Solo: Der Checkout-Weg
  /// für die restlichen Darts der Aufnahme besteht aus genau einem Doppel
  /// (z. B. Rest 32 → D16). Nur bei Double- und Master-Out.
  final List<int?> aimedDoubles = [];

  /// Je Dart der Session der Rest vor dem Dart (Streuungs-Analyse: ab
  /// welchem Rest ein Dart als Scoring-Dart gilt).
  final List<int> remainingBefore = [];

  late int remaining = config.startScore;

  /// Gezählte Darts im laufenden Leg.
  int legDarts = 0;

  /// Rest zu Beginn der laufenden Aufnahme.
  late int visitStartRemaining = config.startScore;

  /// Darts der laufenden Aufnahme, die noch geworfen werden können
  /// (0 nach Bust oder Checkout).
  int dartsLeft = 3;

  int points = 0;
  int darts = 0;
  int checkoutDarts = 0;
  int busts = 0;
  int count100 = 0;
  int count140 = 0;
  int count180 = 0;

  /// Letztes Ereignis der laufenden Aufnahme (Bust, Checkout) für die Anzeige.
  GameEventType? lastEvent;

  final List<int> _legPoints = [];

  int get legsWon => legs.where((l) => l.won).length;
  int get legsLost => legs.length - legsWon;
  double? get average => darts == 0 ? null : points / darts * 3;
  double? get checkoutRate => checkoutDarts == 0 ? null : legsWon / checkoutDarts;
  int get highestFinish => legs.fold(0, (m, l) => l.checkout > m ? l.checkout : m);
  int? get bestLegDarts {
    final won = legs.where((l) => l.won).map((l) => l.darts);
    return won.isEmpty ? null : won.reduce((a, b) => a < b ? a : b);
  }

  /// Schnitt der First-9-Werte aller Legs inklusive des laufenden.
  double? get first9 {
    final values = [for (final l in legs) ?l.first9, ?_first9Of(_legPoints)];
    return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
  }

  static double? _first9Of(List<int> pts) {
    final first = pts.take(9).toList();
    return first.isEmpty ? null : first.fold(0, (a, b) => a + b) / first.length * 3;
  }

  /// Checkout-Weg für die restlichen Darts der Aufnahme.
  List<Segment>? get suggestion => CheckoutRules.suggest(remaining, darts: dartsLeft == 0 ? 3 : dartsLeft, out: config.outMode);

  /// Stell-Vorschlag, wenn kein Finish mehr geht.
  SetupPlan? get setup =>
      suggestion != null ? null : SetupAdvisor.suggest(remaining, darts: dartsLeft == 0 ? 3 : dartsLeft, out: config.outMode);

  /// Spielt die Session ab: [visits] in Wurfreihenfolge, [marks] aufsteigend.
  /// [visitOpen]: Die letzte Aufnahme läuft noch (kein Takeout).
  static LiveX01 replay(LiveX01Config config, List<List<Segment>> visits, List<LegMark> marks, {bool visitOpen = true}) {
    final x = LiveX01._(config);
    final pending = [...marks]..sort((a, b) => a.at.compareTo(b.at));
    var index = 0;
    void applyMarks(int upTo) {
      while (pending.isNotEmpty && pending.first.at <= upTo) {
        x._mark(pending.removeAt(0).kind);
      }
    }

    for (final (vi, v) in visits.indexed) {
      x._startVisit();
      for (final seg in v) {
        applyMarks(index);
        x._dart(seg);
        index++;
      }
      final last = vi == visits.length - 1;
      if (!last || !visitOpen) x._endVisit();
    }
    applyMarks(index);
    return x;
  }

  bool _visitCounted = false;
  int _visitPoints = 0;
  int _visitStartLegDarts = 0;
  bool _visitDone = false;
  int _visitDarts = 0;

  void _startVisit() {
    visitStartRemaining = remaining;
    _visitPoints = 0;
    _visitDarts = 0;
    _visitCounted = false;
    _visitDone = false;
    _visitStartLegDarts = _legPoints.length;
    dartsLeft = 3;
    lastEvent = null;
  }

  void _dart(Segment s) {
    remainingBefore.add(remaining);
    if (_visitDone || dartsLeft <= 0) {
      counted.add(false);
      aimedDoubles.add(null);
      return;
    }
    counted.add(true);
    aimedDoubles.add(_aimedDouble());
    _visitDarts++;
    darts++;
    legDarts++;
    dartsLeft--;
    if (CheckoutRules.isCheckout(remaining, darts: 1, out: config.outMode)) checkoutDarts++;
    if (CheckoutRules.isBust(remaining, s, config.outMode)) {
      _legPoints.add(0);
      for (var i = _visitStartLegDarts; i < _legPoints.length; i++) {
        _legPoints[i] = 0;
      }
      points -= _visitPoints;
      _visitPoints = 0;
      remaining = visitStartRemaining;
      busts++;
      lastEvent = GameEventType.bust;
      _closeVisit();
      return;
    }
    remaining -= s.score;
    points += s.score;
    _visitPoints += s.score;
    _legPoints.add(s.score);
    if (remaining == 0) {
      lastEvent = GameEventType.checkout;
      _closeVisit();
      _endLeg(won: true, checkout: visitStartRemaining);
    }
  }

  /// Ein Doppel geht nur bis Rest 50 (Bull); darüber gibt es keinen
  /// Weg aus einem einzelnen Doppel.
  int? _aimedDouble() {
    if (config.outMode == OutMode.straight || remaining > 50) return null;
    final path = CheckoutRules.suggest(remaining, darts: dartsLeft, out: config.outMode);
    if (path == null || path.length != 1 || !path.first.isDouble) return null;
    return path.first.number;
  }

  void _closeVisit() {
    _visitDone = true;
    dartsLeft = 0;
    _countVisit();
  }

  void _endVisit() {
    if (!_visitDone) _countVisit();
    _visitDone = true;
  }

  void _countVisit() {
    if (_visitCounted || _visitDarts == 0) return;
    _visitCounted = true;
    final p = _visitPoints;
    if (p == 180) {
      count180++;
    } else if (p >= 140) {
      count140++;
    } else if (p >= 100) {
      count100++;
    }
  }

  void _mark(LegMarkKind kind) {
    if (legDarts == 0) return;
    switch (kind) {
      case LegMarkKind.lost:
        _countVisit();
        _endLeg(won: false, checkout: 0);
      case LegMarkKind.restart:
        _resetLeg();
    }
    // Darts derselben Aufnahme nach der Markierung beginnen das neue Leg.
    visitStartRemaining = remaining;
    _visitPoints = 0;
    _visitDarts = 0;
    _visitCounted = false;
    _visitStartLegDarts = 0;
    _visitDone = false;
    lastEvent = null;
  }

  void _endLeg({required bool won, required int checkout}) {
    legs.add(LiveX01Leg(
      darts: legDarts,
      points: _legPoints.fold(0, (a, b) => a + b),
      first9: _first9Of(_legPoints),
      checkout: checkout,
      won: won,
    ));
    _resetLeg();
  }

  void _resetLeg() {
    remaining = config.startScore;
    legDarts = 0;
    _legPoints.clear();
  }

  /// Ergebnis zum Speichern; Schlüssel wie beim Match, damit die Statistik
  /// Average, First 9 und Checkout-Quote wie bei X01 auswertet.
  GameResult result(Map<String, num> rawMetrics) {
    final f9 = first9;
    final best = bestLegDarts;
    return GameResult(
      metrics: {
        ...rawMetrics,
        'darts': darts,
        'average': average ?? 0,
        'first9': ?f9,
        'first9Average': f9 ?? 0,
        'legsWon': legsWon,
        'legsLost': legsLost,
        'legs': legs.length,
        'highestFinish': highestFinish,
        if (highestFinish > 0) 'highestCheckout': highestFinish,
        'bestLegDarts': ?best,
        'checkoutDarts': checkoutDarts,
        'checkoutRate': checkoutRate ?? 0,
        'count100': count100,
        'count140': count140,
        'count180': count180,
        'busts': busts,
      },
      summary: const [],
      details: {
        'source': 'autodartsLocal',
        'mode': 'listen',
        'x01': config.toJson(),
        'legs': [
          for (final l in legs)
            {'darts': l.darts, 'points': l.points, 'first9': l.first9 ?? 0, 'checkout': l.checkout, 'won': l.won},
        ],
      },
    );
  }
}
