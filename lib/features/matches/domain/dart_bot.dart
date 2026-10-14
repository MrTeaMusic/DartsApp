import 'dart:math' as math;

import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../games/domain/games/checkout/checkout_calculator.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import 'bot_calibration.dart';
import 'x01_match.dart';

/// Computergegner, der wie ein Mensch wirft: Er wählt ein Ziel (T20 zum
/// Scoren, einen sinnvollen Aufbau oder den Checkout-Weg) und trifft mit
/// normalverteilter Streuung um den Zielpunkt. Wo der Dart landet, entscheidet
/// die echte Board-Geometrie.
class DartBot {
  DartBot({required this.sigma, double? finishSigma, math.Random? random})
    : finishSigma = finishSigma ?? sigma,
      random = random ?? math.Random();

  /// Bot mit ungefähr diesem 3-Dart-Average (siehe [BotCalibration]).
  factory DartBot.forAverage(double average, {math.Random? random}) => DartBot(
    sigma: BotCalibration.sigmaFor(average),
    finishSigma: BotCalibration.finishSigmaFor(average),
    random: random,
  );

  /// Standardabweichung der Streuung je Achse in normierten Board-Einheiten
  /// (1.0 = Außenkante Double-Ring = 170 mm).
  final double sigma;

  /// Streuung beim Dart, der das Leg beenden (oder mit Double-In eröffnen)
  /// soll. Schwache Bots zielen hier genauer als beim Scoren, sonst stünden
  /// sie oft zehn Aufnahmen und länger auf dem Finish.
  final double finishSigma;
  final math.Random random;

  /// Ab diesem Rest wirft der Bot jeden Dart mit [finishSigma], auch das
  /// Stellen auf ein Doppel. Sonst überwirft er bei kleinen Resten fast jede
  /// Aufnahme.
  static const int finishZone = 60;

  /// Nächster Dart für den Spieler am Zug in [match].
  DartThrow next(X01Match match, {DateTime? at}) {
    final p = match.currentPlayer;
    final target = aim(p.remaining, match.dartsLeft == 0 ? 3 : match.dartsLeft, match.format.outMode, opened: p.opened);
    final finishing = !p.opened || p.remaining <= finishZone || target.score == p.remaining;
    return throwAt(target, at: at, sigma: finishing ? finishSigma : null);
  }

  /// Wirft auf [target] und liefert, wo der Dart landet. Ohne [sigma] gilt
  /// die Scoring-Streuung.
  DartThrow throwAt(Segment target, {DateTime? at, double? sigma}) {
    final spread = sigma ?? this.sigma;
    final aimPoint = BoardGeometry.centerOf(target);
    final p = aimPoint + BoardPoint(_gaussian() * spread, _gaussian() * spread);
    return DartThrow(
      segment: BoardGeometry.segmentAt(p),
      position: p,
      timestamp: at ?? DateTime.now(),
      source: DartSourceKind.simulator,
    );
  }

  /// Zielfeld bei Rest [remaining] mit [dartsLeft] Darts in der Aufnahme.
  static Segment aim(int remaining, int dartsLeft, OutMode out, {bool opened = true}) {
    if (!opened) return Segment.double(20);
    final route = CheckoutRules.suggest(remaining, darts: dartsLeft, out: out);
    if (route != null && route.isNotEmpty) return route.first;
    if (remaining >= 230) return Segment.triple(20);
    return _setup(remaining, out);
  }

  static final List<Segment> _setupCandidates = [
    Segment.triple(20),
    Segment.triple(19),
    Segment.triple(18),
    Segment.triple(17),
    Segment.triple(16),
    Segment.triple(15),
    for (var n = 20; n >= 1; n--) Segment.single(n, inner: true),
    Segment.outerBull,
  ];

  /// Kein Finish in dieser Aufnahme: möglichst viel Punkte, aber so, dass der
  /// Rest ein gutes Finish bleibt und der Dart nicht überwirft.
  static Segment _setup(int remaining, OutMode out) {
    Segment best = Segment.triple(20);
    var bestValue = double.negativeInfinity;
    final minLeave = out == OutMode.straight ? 1 : 2;
    for (final s in _setupCandidates) {
      final leave = remaining - s.score;
      if (leave < minLeave) continue;
      final value = _leaveValue(leave, out) * 100 + s.score * 0.5 - (s.isTriple ? 0 : 5);
      if (value > bestValue) {
        bestValue = value;
        best = s;
      }
    }
    // Ohne passenden Kandidaten (sehr kleiner Rest) auf eine kleine Single.
    if (bestValue == double.negativeInfinity) return Segment.single(1);
    return best;
  }

  /// Wie gut ist ein Rest für die nächste Aufnahme?
  static double _leaveValue(int leave, OutMode out) {
    final doubleOut = out != OutMode.straight;
    final master = out == OutMode.master;
    if (CheckoutCalculator.isCheckout(leave, darts: 1, doubleOut: doubleOut, masterOut: master)) {
      // Bevorzugte Doppel (D20, D16, D8 …) und Bull zuletzt.
      return switch (leave) {
        40 || 32 || 16 || 36 || 24 => 3.3,
        50 => 2.6,
        _ => 3,
      };
    }
    if (CheckoutCalculator.isCheckout(leave, darts: 2, doubleOut: doubleOut, masterOut: master)) return 2;
    if (CheckoutCalculator.isCheckout(leave, darts: 3, doubleOut: doubleOut, masterOut: master)) return 1;
    return 0;
  }

  // Box-Muller.
  double _gaussian() {
    final u1 = 1.0 - random.nextDouble();
    final u2 = random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}
