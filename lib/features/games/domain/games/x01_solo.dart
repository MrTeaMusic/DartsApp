import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';
import 'checkout/checkout_rules.dart';
import 'checkout/setup_advisor.dart';

/// Ein gespieltes Leg.
class X01Leg {
  const X01Leg({required this.darts, required this.points, required this.first9, required this.checkout, required this.won});

  /// Gezählte Darts im Leg.
  final int darts;

  /// Abgezogene Punkte (Bust-Aufnahmen zählen 0).
  final int points;

  /// Schnitt der ersten 9 Darts (3-Dart-Average), `null` ohne Darts.
  final double? first9;

  /// Gecheckter Rest, 0 ohne Checkout.
  final int checkout;
  final bool won;

  double? get average => darts == 0 ? null : points / darts * 3;

  Map<String, Object?> toJson() => {
        'darts': darts,
        'average': average ?? 0,
        'first9': first9 ?? 0,
        'checkout': checkout,
        'won': won,
      };
}

/// Was ein gezählter Dart im X01-Solo bewirkt hat (für die Aufnahmen-Tabelle).
class X01DartInfo {
  const X01DartInfo({required this.leg, required this.remaining, required this.bust, required this.legEnd});

  /// Leg-Nummer (ab 1).
  final int leg;

  /// Rest nach dem Dart: 0 beim Checkout, nach Bust der Rest vor der Aufnahme.
  final int remaining;
  final bool bust;

  /// Der Dart hat das Leg beendet (Checkout oder Dart-Limit erreicht).
  final bool legEnd;
}

/// X01-Solo: 501 & Co. allein gegen die Uhr.
///
/// Regeln:
/// * Start bei [startScore], jeder gezählte Dart zieht ab, Ziel ist 0.
/// * Double-In: Punkte zählen erst ab dem ersten Double/Bullseye (dieser
///   Dart zählt mit). Darts davor zählen als geworfen.
/// * Out: straight, double oder master. Bust (unter 0, Rest 1 bei Double-/
///   Master-Out, 0 mit unerlaubtem Dart) setzt Rest und Einstiegs-Status auf
///   den Stand vor der Aufnahme zurück und beendet die Aufnahme.
/// * Checkout beendet das Leg, das nächste beginnt mit der nächsten Aufnahme.
/// * Mit [dartLimit] > 0 ist ein Leg verloren, wenn das Limit ohne Checkout
///   erreicht wird.
/// * Ende nach [legs] Legs.
class X01Solo extends TrainingGame {
  X01Solo({
    required super.seed,
    this.startScore = 501,
    this.doubleIn = false,
    this.outMode = OutMode.double,
    this.legs = 1,
    this.dartLimit = 0,
    this.showSuggestion = true,
  });

  static const String id = 'x01';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {
      'startScore': 501,
      'inMode': 'straight',
      'outMode': 'double',
      'legs': 1,
      'dartLimit': 0,
      'showSuggestion': true,
    },
    options: const [
      IntChoiceOption('startScore', [101, 170, 301, 501, 701, 1001]),
      ChoiceOption('inMode', ['straight', 'double']),
      ChoiceOption('outMode', ['straight', 'double', 'master']),
      IntOption('legs', min: 1, max: 20),
      IntOption('dartLimit', min: 0, max: 99, step: 3),
      BoolOption('showSuggestion'),
    ],
    create: (c, seed) => X01Solo(
      seed: seed,
      startScore: c.intOf('startScore', 501),
      doubleIn: c.stringOf('inMode', 'straight') == 'double',
      outMode: OutMode.values.firstWhere((v) => v.name == c.stringOf('outMode', 'double'), orElse: () => OutMode.double),
      legs: c.intOf('legs', 1),
      dartLimit: c.intOf('dartLimit', 0),
      showSuggestion: c.boolOf('showSuggestion', true),
    ),
  );

  final int startScore;
  final bool doubleIn;
  final OutMode outMode;
  final int legs;
  final int dartLimit;
  final bool showSuggestion;

  late int remaining = startScore;
  late bool opened = !doubleIn;
  final List<X01Leg> legResults = [];

  int _visitStartRemaining = 0;
  bool _visitStartOpened = false;
  int _visitPoints = 0;

  /// Punkte je gezähltem Dart im laufenden Leg (Bust-Aufnahmen auf 0 gesetzt).
  final List<int> _legDartPoints = [];

  int totalPoints = 0;
  int checkoutDarts = 0;
  int busts = 0;
  int count100 = 0;
  int count140 = 0;
  int count180 = 0;

  int get legDarts => _legDartPoints.length;
  int get legsWon => legResults.where((l) => l.won).length;
  int get legNumber => (legResults.length + (finished ? 0 : 1)).clamp(1, legs);

  double? get average => dartsThrown == 0 ? null : totalPoints / dartsThrown * 3;

  /// Schnitt im laufenden Leg (3-Dart-Average), `null` ohne Darts.
  double? get legAverage =>
      _legDartPoints.isEmpty ? null : _legDartPoints.fold<int>(0, (a, b) => a + b) / _legDartPoints.length * 3;

  @override
  void onStart() => _snapshot();

  @override
  void onVisitStart() => _snapshot();

  void _snapshot() {
    _visitStartRemaining = remaining;
    _visitStartOpened = opened;
    _visitPoints = 0;
    _visitCounted = false;
  }

  X01DartInfo? _lastInfo;
  int _afterRemaining = 0;
  bool _dartBust = false;
  bool _dartLegEnd = false;

  @override
  Object? get lastDartInfo => _lastInfo;

  @override
  void handleDart(DartThrow dart) {
    final leg = legResults.length + 1;
    _afterRemaining = remaining;
    _dartBust = false;
    _dartLegEnd = false;
    _handle(dart);
    _lastInfo = X01DartInfo(leg: leg, remaining: _afterRemaining, bust: _dartBust, legEnd: _dartLegEnd);
  }

  void _handle(DartThrow dart) {
    final s = dart.segment;
    if (opened && CheckoutRules.isCheckout(remaining, darts: 1, out: outMode)) checkoutDarts++;
    if (!opened) {
      if (!s.isDouble) {
        _legDartPoints.add(0);
        _checkLimit();
        return;
      }
      opened = true;
    }
    if (CheckoutRules.isBust(remaining, s, outMode)) {
      _legDartPoints.add(0);
      _bust();
      return;
    }
    remaining -= s.score;
    _afterRemaining = remaining;
    totalPoints += s.score;
    _visitPoints += s.score;
    _legDartPoints.add(s.score);
    if (remaining == 0) {
      events.add(GameEvent(GameEventType.checkout, value: _visitStartRemaining));
      _endLeg(won: true, checkout: _visitStartRemaining);
      return;
    }
    _checkLimit();
  }

  void _bust() {
    busts++;
    // Punkte der Aufnahme zählen nicht.
    totalPoints -= _visitPoints;
    for (var i = _legDartPoints.length - visit.length; i < _legDartPoints.length; i++) {
      _legDartPoints[i] = 0;
    }
    _visitPoints = 0;
    remaining = _visitStartRemaining;
    opened = _visitStartOpened;
    _afterRemaining = remaining;
    _dartBust = true;
    events.add(GameEvent(GameEventType.bust, value: remaining));
    closeVisit();
    _checkLimit();
  }

  void _checkLimit() {
    if (dartLimit <= 0 || legDarts < dartLimit || finished) return;
    events.add(const GameEvent(GameEventType.failed));
    _endLeg(won: false, checkout: 0);
  }

  void _endLeg({required bool won, required int checkout}) {
    _dartLegEnd = true;
    final first = _legDartPoints.take(9).toList();
    legResults.add(X01Leg(
      darts: legDarts,
      points: _legDartPoints.fold(0, (a, b) => a + b),
      first9: first.isEmpty ? null : first.fold(0, (a, b) => a + b) / first.length * 3,
      checkout: checkout,
      won: won,
    ));
    events.add(GameEvent(GameEventType.legComplete, value: legResults.length));
    if (legResults.length >= legs) {
      _countVisit();
      finish();
      return;
    }
    // Nächstes Leg beginnt mit der nächsten Aufnahme.
    _countVisit();
    remaining = startScore;
    opened = !doubleIn;
    _legDartPoints.clear();
    closeVisit();
  }

  bool _visitCounted = false;

  /// 100+/140+/180 einmal pro Aufnahme zählen.
  void _countVisit() {
    if (_visitCounted) return;
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

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) => _countVisit();

  List<Segment>? get suggestion {
    if (!showSuggestion || finished || !opened) return null;
    var darts = dartsLeftInVisit;
    if (dartLimit > 0) {
      final left = dartLimit - legDarts;
      if (left < darts) darts = left;
    }
    return CheckoutRules.suggest(remaining, darts: darts, out: outMode);
  }

  /// Wie man sich stellt, wenn kein Finish mehr geht (sonst `null`).
  SetupPlan? get setup {
    if (!showSuggestion || finished || !opened || suggestion != null) return null;
    var darts = dartsLeftInVisit;
    if (dartLimit > 0) {
      final left = dartLimit - legDarts;
      if (left < darts) darts = left;
    }
    return SetupAdvisor.suggest(remaining, darts: darts, out: outMode);
  }

  static final Set<Segment> _allDoubles = {for (var n = 1; n <= 20; n++) Segment.double(n), Segment.bull};

  @override
  Set<Segment> get targets {
    if (finished) return const {};
    if (!opened) return _allDoubles;
    final s = suggestion;
    return s == null ? const {} : s.toSet();
  }

  double? get _first9Average {
    final values = [for (final l in legResults) ?l.first9];
    if (!finished && _legDartPoints.isNotEmpty) {
      final first = _legDartPoints.take(9).toList();
      values.add(first.fold(0, (a, b) => a + b) / first.length * 3);
    }
    return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
  }

  int? get _bestLegDarts {
    final won = legResults.where((l) => l.won).map((l) => l.darts);
    return won.isEmpty ? null : won.reduce((a, b) => a < b ? a : b);
  }

  int get _highestFinish => legResults.fold(0, (m, l) => l.checkout > m ? l.checkout : m);

  @override
  GameDisplay get display => GameDisplay(
        headline: '$remaining',
        headlineKey: opened ? 'remaining' : 'doubleToStart',
        suggestion: suggestion,
        setup: setup,
        progress: legResults.length / legs,
        progressLabel: 'Leg $legNumber/$legs',
        stats: [
          GameStat('average', formatDecimal(average)),
          GameStat('legDarts', dartLimit > 0 ? '$legDarts/$dartLimit' : '$legDarts'),
          if (legs > 1) GameStat('legsWon', '$legsWon'),
        ],
      );

  @override
  GameResult get result {
    final rate = checkoutDarts == 0 ? null : legsWon / checkoutDarts;
    final best = _bestLegDarts;
    final first9 = _first9Average;
    return GameResult(
      metrics: {
        'darts': dartsThrown,
        'average': average ?? 0,
        'first9Average': first9 ?? 0,
        'bestLegDarts': ?best,
        'legsWon': legsWon,
        'legs': legResults.length,
        'highestFinish': _highestFinish,
        'checkoutDarts': checkoutDarts,
        'checkoutRate': rate ?? 0,
        'count100': count100,
        'count140': count140,
        'count180': count180,
        'busts': busts,
        'completed': finished ? 1 : 0,
      },
      summary: [
        GameStat('average', formatDecimal(average)),
        GameStat('first9Average', formatDecimal(first9)),
        GameStat('legsWon', '$legsWon/${legResults.length}'),
        GameStat('bestLegDarts', best == null ? '–' : '$best'),
        GameStat('checkoutRate', formatPercent(rate)),
        GameStat('highestFinish', _highestFinish == 0 ? '–' : '$_highestFinish'),
        GameStat('scores100', '$count100 / $count140 / $count180'),
      ],
      details: {'legs': [for (final l in legResults) l.toJson()]},
    );
  }
}
