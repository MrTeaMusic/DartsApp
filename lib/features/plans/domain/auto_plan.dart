import 'dart:math' as math;

import '../../stats/domain/stats_calculator.dart';
import 'training_plan.dart';

/// Automatischer Trainingsplan aus der Statistik.
///
/// [AutoPlanGenerator.generate] sucht Schwächen ([Weakness]) in den
/// Kennzahlen eines Zeitraums, ordnet jeder ein passendes Spiel mit
/// konkreter Config zu und baut daraus einen Plan:
/// Aufwärmen → Schwerpunkte → Abschluss unter Druck. Jeder Schritt bekommt
/// eine kurze Begründung als Hinweis (`note`), die auch im Spiel erscheint.
///
/// Reine Berechnung ohne Zufall: gleiche Eingabe, gleiche Länge und gleiche
/// Variante ergeben denselben Plan. „Neu vorschlagen“ erhöht die Variante.

/// Rolle eines Schritts im automatischen Plan.
enum AutoStepRole { warmup, focus, finish }

/// Arten von Schwächen. Die Reihenfolge ist zugleich die Reihenfolge der
/// Schwerpunkte im Plan: erst Scoring, dann Doppel und Finishes.
enum WeaknessKind { scoring, first9, consistency, treble, double, doubles, checkout }

/// Eine gefundene Schwäche mit Begründung.
class Weakness {
  const Weakness({
    required this.kind,
    required this.severity,
    required this.label,
    required this.value,
    required this.goal,
    required this.reason,
    this.number,
    this.range,
  });

  final WeaknessKind kind;

  /// 0 (kaum) bis 1 (stark). Bestimmt, welche Schwächen in den Plan kommen.
  final double severity;

  /// Kurzname, z. B. „D16“ oder „Checkout 41–60“.
  final String label;

  /// Aktueller Wert, z. B. „18 %“.
  final String value;

  /// Ziel, z. B. „25 %“.
  final String goal;

  /// Begründung, z. B. „D16 triffst du nur zu 18 %, Ziel: 25 %“.
  final String reason;

  /// Double (1–20, 25 = Bull), Triple-Zahl oder Score-Ziel (Konstanz).
  final int? number;
  final CheckoutRange? range;
}

/// Ein Schritt des automatischen Plans mit Rolle und geschätzter Dauer.
class AutoPlanStep {
  const AutoPlanStep({required this.step, required this.role, required this.minutes, this.weakness});
  final PlanStep step;
  final AutoStepRole role;
  final double minutes;

  /// Schwäche, für die der Schritt da ist (nur bei Schwerpunkten aus Daten).
  final Weakness? weakness;

  String get reason => step.note ?? '';
}

/// Ergebnis von [AutoPlanGenerator.generate].
class AutoPlan {
  const AutoPlan({
    required this.plan,
    required this.steps,
    required this.weaknesses,
    required this.enoughData,
    required this.notice,
    required this.targetMinutes,
    required this.variant,
  });

  /// Der Plan zum Starten oder Speichern (ID [AutoPlanGenerator.planId]).
  final TrainingPlan plan;
  final List<AutoPlanStep> steps;

  /// Alle gefundenen Schwächen, stärkste zuerst (auch die, die nicht in den
  /// Plan gepasst haben).
  final List<Weakness> weaknesses;

  /// Genug Daten für einen persönlichen Plan? Sonst ist es der Startplan.
  final bool enoughData;

  /// Hinweis zur Grundlage, z. B. „Aus 1234 Darts der letzten 30 Tage.“
  final String notice;
  final int targetMinutes;
  final int variant;

  /// Geschätzte Gesamtdauer in Minuten.
  double get minutes => steps.fold(0.0, (s, e) => s + e.minutes);
}

/// Die Kennzahlen, die der Generator braucht. Aus einem [StatsReport] oder
/// in Tests direkt gebaut.
class AutoPlanInput {
  const AutoPlanInput({
    this.days,
    this.sessions = 0,
    this.darts = 0,
    this.doubles = const {},
    this.doubleRate,
    this.doubleAttempts = 0,
    this.trebles = const {},
    this.trebleRate,
    this.trebleAttempts = 0,
    this.checkoutByRange = const {},
    this.scoringAverage,
    this.scoringDarts = 0,
    this.first9Average,
    this.scoringVisits = 0,
    this.scoringMean,
    this.scoringStdDev,
  });

  factory AutoPlanInput.fromReport(StatsReport r, {int? days}) => AutoPlanInput(
        days: days,
        sessions: r.sessions,
        darts: r.darts,
        doubles: r.doubles,
        doubleRate: r.doubleRate,
        doubleAttempts: r.doubleAttempts,
        trebles: r.trebles,
        trebleRate: r.trebleRate,
        trebleAttempts: r.trebleAttempts,
        checkoutByRange: r.checkoutByRange,
        scoringAverage: r.scoringAverage,
        scoringDarts: r.scoringDarts,
        first9Average: r.first9Average,
        scoringVisits: r.scoring?.visits ?? 0,
        scoringMean: r.scoring?.mean,
        scoringStdDev: r.scoring?.stdDev,
      );

  /// Länge des Zeitraums in Tagen, `null` = alle Daten.
  final int? days;
  final int sessions;
  final int darts;
  final Map<int, HitCount> doubles;
  final double? doubleRate;
  final int doubleAttempts;
  final Map<int, HitCount> trebles;
  final double? trebleRate;
  final int trebleAttempts;
  final Map<CheckoutRange, HitCount> checkoutByRange;
  final double? scoringAverage;
  final int scoringDarts;
  final double? first9Average;
  final int scoringVisits;
  final double? scoringMean;
  final double? scoringStdDev;
}

/// Ein Spiel-Vorschlag, dessen Umfang sich an die verfügbare Zeit anpasst.
class _Drill {
  const _Drill(this.build, {this.fixedMinutes});

  /// Baut den Schritt für ungefähr so viele Minuten.
  final PlanStep Function(double minutes) build;

  /// Dauer unabhängig von der Zeit (z. B. Bob's 27), sonst `null`.
  final double? fixedMinutes;
}

/// Erzeugt automatische Trainingspläne. Siehe [AutoPlan].
abstract final class AutoPlanGenerator {
  /// ID des (noch nicht gespeicherten) automatischen Plans. Ein Durchlauf
  /// läuft unter dieser ID und lässt sich im Plan-für-mich-Bildschirm
  /// fortsetzen.
  static const String planId = 'auto-plan';

  /// Wählbare Längen in Minuten.
  static const List<int> lengths = [20, 40, 60];
  static const int defaultMinutes = 40;

  /// Ab so vielen Darts und Sessions im Zeitraum gibt es einen persönlichen
  /// Plan, sonst den Startplan.
  static const int minDarts = 150;
  static const int minSessions = 3;

  /// Mindestversuche, damit ein Double, ein Triple oder ein Checkout-
  /// Bereich bewertet wird.
  static const int minDoubleAttempts = 10;
  static const int minTrebleAttempts = 15;
  static const int minCheckoutAttempts = 8;

  /// Ab so vielen Darts zählt die eigene Gesamtquote als Vergleich.
  static const int minReferenceAttempts = 30;

  /// Ein Double oder Triple gilt als schwach, wenn seine Quote mindestens so
  /// weit unter der eigenen Gesamtquote liegt (wie im Doubles-Raster).
  static const double relativeGap = 0.15;

  /// Unter dieser Double-Quote sind die Doppel insgesamt ein Schwerpunkt.
  static const double doublesBenchmark = 0.20;

  /// Richtwerte je Checkout-Bereich.
  static const Map<CheckoutRange, double> checkoutBenchmark = {
    CheckoutRange.low: 0.40,
    CheckoutRange.mid: 0.30,
    CheckoutRange.high: 0.20,
    CheckoutRange.big: 0.10,
    CheckoutRange.huge: 0.05,
  };

  /// Unter diesem 3-Dart-Average ist Scoring ein Schwerpunkt.
  static const double scoringBenchmark = 60;
  static const int minScoringDarts = 90;
  static const int minScoringVisits = 30;

  /// Ab dieser Streuung (Standardabweichung / Mittelwert) ist Konstanz ein
  /// Schwerpunkt.
  static const double maxVariation = 0.55;

  /// Triple-Zahlen, die das T20-Training anbietet.
  static const List<int> trebleNumbers = [20, 19, 18, 17, 16, 15];

  /// Grob geschätzte Minuten pro Aufnahme (Werfen, Darts holen, Eingabe).
  static const double minutesPerVisit = 1 / 3;

  static bool hasEnoughData(AutoPlanInput input) => input.darts >= minDarts && input.sessions >= minSessions;

  /// Anzahl Schwerpunkte je Länge: 20 min → 2, 40 → 3, 60 → 4.
  static int focusSlots(int minutes) => ((minutes / 20).round() + 1).clamp(2, 5);

  // ------------------------------------------------------------ Schwächen

  /// Alle Schwächen, stärkste zuerst. Bei gleicher Stärke entscheidet die
  /// Art, dann die Zahl, damit das Ergebnis stabil bleibt.
  static List<Weakness> weaknesses(AutoPlanInput input) {
    final list = <Weakness>[
      ..._doubleWeaknesses(input),
      ?_doublesWeakness(input),
      ?_trebleWeakness(input),
      ?_checkoutWeakness(input),
      ?_scoringWeakness(input),
      ?_first9Weakness(input),
      ?_consistencyWeakness(input),
    ];
    list.sort((a, b) {
      final s = b.severity.compareTo(a.severity);
      if (s != 0) return s;
      final k = a.kind.index.compareTo(b.kind.index);
      if (k != 0) return k;
      return (a.number ?? a.range?.index ?? 0).compareTo(b.number ?? b.range?.index ?? 0);
    });
    return list;
  }

  static double? _reference(double? overall, int overallAttempts, Map<int, HitCount> perTarget) {
    if (overall != null && overallAttempts >= minReferenceAttempts) return overall;
    final sum = perTarget.values.fold(HitCount.zero, (a, b) => a + b);
    return sum.attempts >= minReferenceAttempts ? sum.rate : null;
  }

  static List<Weakness> _doubleWeaknesses(AutoPlanInput input) {
    final ref = _reference(input.doubleRate, input.doubleAttempts, input.doubles);
    if (ref == null || ref <= 0) return const [];
    final out = <Weakness>[];
    final keys = input.doubles.keys.toList()..sort();
    for (final n in keys) {
      final h = input.doubles[n]!;
      if (h.attempts < minDoubleAttempts) continue;
      final rate = h.rate!;
      final severity = (1 - rate / ref).clamp(0.0, 1.0);
      if (severity < relativeGap) continue;
      final goal = _ceilTo(math.max(ref, rate + 0.05), 5);
      final label = doubleName(n);
      out.add(Weakness(
        kind: WeaknessKind.double,
        severity: severity,
        label: label,
        value: percent(rate),
        goal: '$goal %',
        number: n,
        reason: '$label triffst du nur zu ${percent(rate)}, Ziel: $goal %',
      ));
    }
    out.sort((a, b) => b.severity.compareTo(a.severity));
    return out.take(2).toList();
  }

  static Weakness? _doublesWeakness(AutoPlanInput input) {
    final rate = input.doubleRate;
    if (rate == null || input.doubleAttempts < minReferenceAttempts || rate >= doublesBenchmark) return null;
    final goal = _ceilTo(rate + 0.03, 5);
    return Weakness(
      kind: WeaknessKind.doubles,
      severity: 1 - rate / doublesBenchmark,
      label: 'Doppel',
      value: percent(rate),
      goal: '$goal %',
      reason: 'Deine Doppelquote liegt bei ${percent(rate)}, Ziel: $goal %',
    );
  }

  static Weakness? _trebleWeakness(AutoPlanInput input) {
    final ref = _reference(input.trebleRate, input.trebleAttempts, input.trebles);
    if (ref == null || ref <= 0) return null;
    Weakness? worst;
    for (final n in trebleNumbers) {
      final h = input.trebles[n];
      if (h == null || h.attempts < minTrebleAttempts) continue;
      final rate = h.rate!;
      final severity = (1 - rate / ref).clamp(0.0, 1.0);
      if (severity < relativeGap || (worst != null && severity <= worst.severity)) continue;
      final goal = _ceilTo(math.max(ref, rate + 0.03), 1);
      worst = Weakness(
        kind: WeaknessKind.treble,
        severity: severity,
        label: 'T$n',
        value: percent(rate),
        goal: '$goal %',
        number: n,
        reason: 'T$n triffst du nur zu ${percent(rate)}, Ziel: $goal %',
      );
    }
    return worst;
  }

  static Weakness? _checkoutWeakness(AutoPlanInput input) {
    Weakness? worst;
    for (final range in CheckoutRange.values) {
      final h = input.checkoutByRange[range];
      if (h == null || h.attempts < minCheckoutAttempts) continue;
      final rate = h.rate!;
      final bench = checkoutBenchmark[range]!;
      final severity = (1 - rate / bench).clamp(0.0, 1.0);
      if (severity < relativeGap || (worst != null && severity <= worst.severity)) continue;
      final goal = math.min(_ceilTo(bench, 5), math.max(_ceilTo(rate + 0.05, 5), _ceilTo(bench / 2, 5)));
      final label = 'Checkout ${range.min}–${range.max}';
      worst = Weakness(
        kind: WeaknessKind.checkout,
        severity: severity,
        label: label,
        value: percent(rate),
        goal: '$goal %',
        range: range,
        reason: 'Checkouts ${range.min}–${range.max} schaffst du zu ${percent(rate)}, Ziel: $goal %',
      );
    }
    return worst;
  }

  static Weakness? _scoringWeakness(AutoPlanInput input) {
    final avg = input.scoringAverage;
    if (avg == null || input.scoringDarts < minScoringDarts || avg >= scoringBenchmark) return null;
    final goal = _ceilTo((avg + 3) / 100, 5);
    return Weakness(
      kind: WeaknessKind.scoring,
      severity: (1 - avg / scoringBenchmark) * 0.8,
      label: 'Scoring',
      value: decimal(avg),
      goal: '$goal',
      reason: 'Dein 3-Dart-Average liegt bei ${decimal(avg)}, Ziel: $goal',
    );
  }

  static Weakness? _first9Weakness(AutoPlanInput input) {
    final f9 = input.first9Average;
    final avg = input.scoringAverage;
    if (f9 == null || avg == null || avg <= 0 || input.scoringDarts < minScoringDarts || f9 >= avg * 0.97) return null;
    return Weakness(
      kind: WeaknessKind.first9,
      severity: ((1 - f9 / avg) * 3).clamp(0.0, 1.0),
      label: 'First 9',
      value: decimal(f9),
      goal: decimal(avg),
      reason: 'Deine First 9 (${decimal(f9)}) liegen unter deinem Average (${decimal(avg)}): stärker starten',
    );
  }

  static Weakness? _consistencyWeakness(AutoPlanInput input) {
    final mean = input.scoringMean;
    final sd = input.scoringStdDev;
    if (mean == null || sd == null || mean <= 0 || input.scoringVisits < minScoringVisits) return null;
    final variation = sd / mean;
    if (variation <= maxVariation) return null;
    final target = consistencyTarget(mean);
    return Weakness(
      kind: WeaknessKind.consistency,
      severity: (variation - 0.45).clamp(0.0, 1.0),
      label: 'Konstanz',
      value: '± ${sd.round()}',
      goal: '$target+',
      number: target,
      reason: 'Deine Aufnahmen streuen stark (± ${sd.round()} bei ${decimal(mean)} im Schnitt), Ziel: '
          'jede Aufnahme $target+',
    );
  }

  /// Score-Ziel für Konstanz: höchster Wert des Spiels bis zum Schnitt.
  static int consistencyTarget(double mean) {
    const options = [60, 81, 100, 121, 140];
    return options.lastWhere((o) => o <= mean, orElse: () => 60);
  }

  // ------------------------------------------------------------ Spiele

  /// Spiele für eine Schwäche. Die Variante wählt reihum.
  static List<_Drill> _drillsFor(Weakness w) {
    final note = w.reason;
    switch (w.kind) {
      case WeaknessKind.double:
        final value = w.number == 25 ? 50 : w.number! * 2;
        return [
          _Drill((m) => PlanStep(
                gameId: 'checkout',
                config: {'mode': 'random', 'min': value, 'max': value, 'attempts': _count(m, 1), 'dartsPerAttempt': 3},
                note: '$note. Immer $value Rest, also ${w.label} zum Checken.',
              )),
        ];
      case WeaknessKind.doubles:
        return [
          _Drill(
            (_) => PlanStep(gameId: 'around_the_clock', config: {'ring': 'double', 'includeBull': false}, note: '$note. Jedes Doppel der Reihe nach.'),
            fixedMinutes: 12,
          ),
          _Drill(
            (_) => PlanStep(gameId: 'doubles_420', config: {'includeBull': false}, note: '$note. Eine Aufnahme pro Doppel.'),
            fixedMinutes: 7,
          ),
          _Drill((m) => PlanStep(
                gameId: 'checkout',
                config: {'mode': 'random', 'min': 2, 'max': 40, 'attempts': _count(m, 1), 'dartsPerAttempt': 3},
                note: '$note. Kurze Reste, nur Doppel zum Schluss.',
              )),
        ];
      case WeaknessKind.treble:
        return [
          _Drill((m) => PlanStep(
                gameId: 'target_practice',
                config: {'number': w.number, 'visits': _count(m, 1)},
                note: '$note. Alles auf die T${w.number}.',
              )),
        ];
      case WeaknessKind.checkout:
        final r = w.range!;
        final big = r.min > 100;
        final dpa = big ? 6 : 3;
        return [
          _Drill((m) => PlanStep(
                gameId: 'checkout',
                config: {'mode': 'random', 'min': r.min, 'max': r.max, 'attempts': _count(m, dpa ~/ 3), 'dartsPerAttempt': dpa},
                note: '$note. Den Weg vor dem ersten Dart planen.',
              )),
          if (r == CheckoutRange.big || r == CheckoutRange.high)
            _Drill((m) => PlanStep(
                  gameId: 'one_twenty_one',
                  config: {'start': r == CheckoutRange.big ? 121 : 81, 'dartsPerAttempt': 9, 'rounds': _count(m, 3, factor: 0.8)},
                  note: '$note. Geschafft = 1 höher, verfehlt = zurück.',
                ))
          else
            _Drill((m) => PlanStep(
                  gameId: 'checkout',
                  config: {'mode': 'descending', 'min': r.min, 'max': r.max, 'attempts': _count(m, 1), 'dartsPerAttempt': 3},
                  note: '$note. Von oben nach unten durch den ganzen Bereich.',
                )),
        ];
      case WeaknessKind.scoring:
        return [
          _Drill((m) => PlanStep(gameId: 'target_practice', config: {'number': 20, 'visits': _count(m, 1)}, note: '$note. Alles auf die T20.')),
          _Drill((m) => PlanStep(
                gameId: 'score_target',
                config: {'target': 60, 'visits': _count(m, 1)},
                note: '$note. Jede Aufnahme mindestens 60.',
              )),
          _Drill((m) => PlanStep(gameId: 'highscore_hunt', config: {'visits': _count(m, 1)}, note: '$note. Möglichst viele Punkte.')),
        ];
      case WeaknessKind.first9:
        return [
          _Drill((m) => PlanStep(
                gameId: 'score_target',
                config: {'target': 100, 'visits': _count(m, 1)},
                note: '$note. Jede Aufnahme zählt wie die ersten drei.',
              )),
          _Drill((m) => PlanStep(
                gameId: 'target_practice',
                config: {'number': 20, 'visits': _count(m, 1)},
                note: '$note. Von der ersten Aufnahme an voll konzentriert.',
              )),
        ];
      case WeaknessKind.consistency:
        final target = w.number!;
        return [
          _Drill((m) => PlanStep(gameId: 'score_target', config: {'target': target, 'visits': _count(m, 1)}, note: '$note.')),
          _Drill((m) => PlanStep(
                gameId: 'target_practice',
                config: {'number': 19, 'visits': _count(m, 1)},
                note: '$note. Gleicher Ablauf bei jedem Dart.',
              )),
        ];
    }
  }

  /// Aufwärmen, Umfang nach [minutes].
  static List<_Drill> _warmups() => [
        _Drill(
          (_) => const PlanStep(
            gameId: 'around_the_clock',
            config: {'order': 'ascending', 'ring': 'any', 'includeBull': false},
            note: 'Zum Aufwärmen einmal ums Board, Rhythmus finden.',
          ),
          fixedMinutes: 5,
        ),
        _Drill((m) => PlanStep(
              gameId: 'target_practice',
              config: {'number': 20, 'visits': _count(m, 1)},
              note: 'Zum Aufwärmen locker auf die 20.',
            )),
        _Drill((m) => PlanStep(gameId: 'bull_drill', config: {'visits': _count(m, 1)}, note: 'Zum Aufwärmen aufs Bull, Wurf sauber zu Ende führen.')),
      ];

  /// Abschluss unter Druck, passend zum stärksten Schwerpunkt.
  static List<_Drill> _finishers(WeaknessKind? main) {
    final x01 = _Drill((m) => PlanStep(
          gameId: 'x01_solo',
          config: {'startScore': 501, 'legs': (m / 6).round().clamp(1, 20)},
          note: 'Zum Schluss 501 unter Spielbedingungen: alles zusammen.',
        ));
    final bobs = _Drill(
      (_) => const PlanStep(gameId: 'bobs_27', config: {'includeBull': false}, note: 'Zum Schluss Druck: Bob\'s 27 bestraft jedes verfehlte Doppel.'),
      fixedMinutes: 7,
    );
    final oneTwentyOne = _Drill((m) => PlanStep(
          gameId: 'one_twenty_one',
          config: {'start': 121, 'dartsPerAttempt': 9, 'rounds': _count(m, 3, factor: 0.8)},
          note: 'Zum Schluss 121: jedes geschaffte Finish macht es schwerer.',
        ));
    return switch (main) {
      WeaknessKind.double || WeaknessKind.doubles => [bobs, oneTwentyOne],
      WeaknessKind.checkout => [oneTwentyOne, x01],
      null => [x01, oneTwentyOne],
      _ => [x01, bobs],
    };
  }

  /// Ausgewogene Schritte für den Startplan und als Auffüllung.
  static List<_Drill> _fillers() => [
        _Drill((m) => PlanStep(
              gameId: 'target_practice',
              config: {'number': 20, 'visits': _count(m, 1)},
              note: 'Grundlage fürs Scoring: Triple 20.',
            )),
        _Drill((m) => PlanStep(
              gameId: 'checkout',
              config: {'mode': 'random', 'min': 2, 'max': 40, 'attempts': _count(m, 1), 'dartsPerAttempt': 3},
              note: 'Kurze Reste, wie sie im Spiel oft übrig bleiben.',
            )),
        _Drill((m) => PlanStep(
              gameId: 'score_target',
              config: {'target': 100, 'visits': _count(m, 1)},
              note: 'Aufnahmen über 100 sammeln.',
            )),
        _Drill((m) => PlanStep(
              gameId: 'checkout',
              config: {'mode': 'random', 'min': 41, 'max': 100, 'attempts': _count(m, 1), 'dartsPerAttempt': 3},
              note: 'Mittlere Finishes mit Wegvorschlag.',
            )),
      ];

  /// Anzahl Aufnahmen bzw. Versuche für [minutes], wenn ein Versuch
  /// [visits] Aufnahmen dauert ([factor] < 1: oft früher fertig).
  static int _count(double minutes, int visits, {double factor = 1}) =>
      (minutes / (visits * minutesPerVisit * factor)).round().clamp(3, 50);

  /// Geschätzte Dauer eines Schritts in Minuten (grob, für die Planlänge).
  static double minutesOf(PlanStep step) {
    final c = step.resolvedConfig;
    int i(String k, int f) => switch (c[k]) {
          final num v => v.toInt(),
          _ => f,
        };
    const v = minutesPerVisit;
    return switch (step.gameId) {
      'target_practice' || 'score_target' || 'highscore_hunt' || 'bull_drill' => i('visits', 10) * v,
      'checkout' => i('attempts', 10) * (i('dartsPerAttempt', 3) / 3).ceil() * v,
      'one_twenty_one' => i('rounds', 10) * (i('dartsPerAttempt', 9) / 3).ceil() * v * 0.8,
      'x01_solo' => i('legs', 1) * i('startScore', 501) / 501 * 6,
      'around_the_clock' => switch (c['ring']) {
          'double' => 12.0,
          'triple' => 12.0,
          _ => 5.0,
        },
      'bobs_27' || 'doubles_420' => 7.0,
      'halve_it' => 5.0,
      _ => 8.0,
    };
  }

  // ------------------------------------------------------------ Plan bauen

  /// Erzeugt den Plan für [minutes] (siehe [lengths]). [variant] wählt
  /// andere Spiele für dieselben Schwerpunkte.
  static AutoPlan generate(AutoPlanInput input, {int minutes = defaultMinutes, int variant = 0}) {
    final target = minutes.clamp(10, 120);
    final v = variant < 0 ? -variant : variant;
    final enough = hasEnoughData(input);
    final found = enough ? weaknesses(input) : const <Weakness>[];

    // Schwerpunkte auswählen: stärkste zuerst, je Art höchstens einer
    // (Doubles: zwei).
    final slots = focusSlots(target);
    final chosen = <Weakness>[];
    for (final w in found) {
      if (chosen.length >= slots) break;
      final sameKind = chosen.where((c) => c.kind == w.kind).length;
      if (sameKind >= (w.kind == WeaknessKind.double ? 2 : 1)) continue;
      chosen.add(w);
    }
    final main = chosen.isEmpty ? null : chosen.first.kind;
    chosen.sort((a, b) => a.kind.index != b.kind.index ? a.kind.index.compareTo(b.kind.index) : found.indexOf(a).compareTo(found.indexOf(b)));

    // Abschluss passend zum stärksten Schwerpunkt.
    final warmMinutes = (target * 0.12).clamp(3.0, 8.0);
    final finMinutes = (target * 0.15).clamp(4.0, 10.0);
    final fin = _pick(_finishers(main), v).build(finMinutes);

    // Schwerpunkte, mit Auffüllung aus dem ausgewogenen Programm. Kein
    // Spiel doppelt, und feste lange Spiele nur, wenn sie in die Zeit passen.
    final share = math.max(3.0, (target - warmMinutes - finMinutes) / slots);
    final taken = <PlanStep>[fin];
    final focus = <(Weakness?, _Drill)>[];
    void take(Weakness? w, _Drill d) {
      focus.add((w, d));
      taken.add(d.build(share));
    }

    for (final (i, w) in chosen.indexed) {
      final drills = _drillsFor(w);
      take(w, _choose(drills, v + i, taken, probe: share, maxFixed: share * 1.5) ?? _pick(drills, v + i));
    }
    final fillers = _fillers();
    for (var k = 0; focus.length < slots && k < fillers.length; k++) {
      final d = _choose([_pick(fillers, v + k)], 0, taken, probe: share, maxFixed: share * 1.5);
      if (d != null) take(null, d);
    }

    // Aufwärmen mit einem Spiel, das nicht schon Schwerpunkt ist.
    final warmDrills = _warmups();
    final warm = (_choose(warmDrills, v, taken, probe: warmMinutes) ?? _pick(warmDrills, v)).build(warmMinutes);

    // Zeit verteilen: feste Dauern zuerst, der Rest nach Gewicht.
    // Schwerpunkte aus der Statistik bekommen mehr Zeit als Auffüllung.
    double weight(Weakness? w) => w == null ? 1.0 : 1.5;
    final fixed = focus.fold(0.0, (s, f) => s + (f.$2.fixedMinutes ?? 0));
    final weights = focus.where((f) => f.$2.fixedMinutes == null).fold(0.0, (s, f) => s + weight(f.$1));
    final budget = target - minutesOf(warm) - minutesOf(fin) - fixed;
    final unit = weights == 0 ? 0.0 : budget / weights;

    final steps = <AutoPlanStep>[
      AutoPlanStep(step: warm, role: AutoStepRole.warmup, minutes: minutesOf(warm)),
      for (final (w, d) in focus)
        () {
          final s = d.build(d.fixedMinutes ?? math.max(3.0, unit * weight(w)));
          return AutoPlanStep(step: s, role: AutoStepRole.focus, minutes: minutesOf(s), weakness: w);
        }(),
      AutoPlanStep(step: fin, role: AutoStepRole.finish, minutes: minutesOf(fin)),
    ];

    final period = input.days == null ? 'aller Daten' : 'der letzten ${input.days} Tage';
    final String notice;
    final String name;
    final String description;
    if (!enough) {
      notice = 'Noch zu wenig Daten für einen persönlichen Plan (${input.darts} Darts in ${input.sessions} '
          '${input.sessions == 1 ? 'Session' : 'Sessions'} $period). Hier ein ausgewogener Startplan; nach ein paar '
          'Trainings wird der Vorschlag persönlicher.';
      name = 'Startplan ($target min)';
      description = 'Ausgewogener Startplan: Aufwärmen, Scoring, Checkouts und ein Abschluss unter Druck. Etwa $target Minuten.';
    } else if (chosen.isEmpty) {
      notice = 'Aus ${input.darts} Darts $period: Keine klare Schwäche gefunden. Hier ein ausgewogener Plan.';
      name = 'Ausgewogen ($target min)';
      description = 'Keine klare Schwäche in der Statistik $period, daher ausgewogen. Etwa $target Minuten.';
    } else {
      final labels = chosen.map((w) => w.label).join(', ');
      notice = 'Aus ${input.darts} Darts $period. Schwerpunkte: $labels.';
      name = TrainingPlan.cleanName('Für mich: $labels');
      description = 'Automatisch aus der Statistik $period: $labels. Etwa $target Minuten.';
    }

    return AutoPlan(
      plan: TrainingPlan(id: planId, name: name, description: description, steps: [for (final s in steps) s.step]),
      steps: steps,
      weaknesses: found,
      enoughData: enough,
      notice: notice,
      targetMinutes: target,
      variant: v,
    );
  }

  static _Drill _pick(List<_Drill> drills, int index) => drills[index % drills.length];

  /// Erstes Spiel ab [start], das noch nicht im Plan ist (geprüft mit
  /// dem Umfang für [probe] Minuten) und, falls es eine feste Dauer hat,
  /// höchstens [maxFixed] Minuten dauert; `null`, wenn keins passt.
  static _Drill? _choose(List<_Drill> drills, int start, List<PlanStep> taken, {required double probe, double? maxFixed}) {
    for (var k = 0; k < drills.length; k++) {
      final d = _pick(drills, start + k);
      if (maxFixed != null && d.fixedMinutes != null && d.fixedMinutes! > maxFixed) continue;
      final step = d.build(probe);
      if (taken.any((t) => _sameDrill(t, step))) continue;
      return d;
    }
    return null;
  }

  /// Gleiches Spiel mit gleichem Ziel (Zahl, Bereich, Ring, Score)?
  static bool _sameDrill(PlanStep a, PlanStep b) =>
      a.gameId == b.gameId && ['number', 'min', 'max', 'ring', 'target', 'start'].every((k) => a.config[k] == b.config[k]);

  // ------------------------------------------------------------ Texte

  static String doubleName(int n) => n == 25 ? 'Bull' : 'D$n';

  /// Ganze Prozent, deutsch: „18 %“.
  static String percent(double ratio) => '${(ratio * 100).round()} %';

  static String decimal(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  /// Quote in Prozent, aufgerundet auf ein Vielfaches von [step].
  static int _ceilTo(double ratio, int step) => (((ratio * 100) - 1e-9) / step).ceil() * step;
}
