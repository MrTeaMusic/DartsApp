import '../../../../board/domain/segment.dart';
import 'checkout_calculator.dart';

/// Womit ein Leg bzw. Finish beendet werden darf.
enum OutMode {
  /// Jeder Dart darf auf 0.
  straight,

  /// Letzter Dart Double oder Bullseye.
  double,

  /// Letzter Dart Double, Triple oder Bullseye.
  master;

  static OutMode fromDoubleOut(bool doubleOut) => doubleOut ? OutMode.double : OutMode.straight;
}

/// Gemeinsame Finish-Regeln (Bust, erlaubter letzter Dart, Wurfvorschlag)
/// für alle Spiele mit Rest-Countdown.
abstract final class CheckoutRules {
  /// Darf [s] das Finish machen?
  static bool isFinisher(Segment s, OutMode out) => switch (out) {
        OutMode.straight => true,
        OutMode.double => s.isDouble,
        OutMode.master => s.isDouble || s.isTriple,
      };

  /// Ist der Dart [s] bei Rest [remaining] ein Bust? Bust bei Rest unter 0,
  /// Rest 1 (außer Straight-Out) oder 0 mit unerlaubtem letzten Dart.
  static bool isBust(int remaining, Segment s, OutMode out) {
    final next = remaining - s.score;
    if (next < 0) return true;
    if (out == OutMode.straight) return false;
    return next == 1 || (next == 0 && !isFinisher(s, out));
  }

  /// Bester Weg für [remaining] mit höchstens [darts] Darts, `null` ohne
  /// Finish.
  static List<Segment>? suggest(int remaining, {required int darts, required OutMode out}) => CheckoutCalculator.suggest(
        remaining,
        darts: darts,
        doubleOut: out != OutMode.straight,
        masterOut: out == OutMode.master,
      );

  /// Mit [darts] Darts checkbar?
  static bool isCheckout(int remaining, {int darts = 3, required OutMode out}) =>
      suggest(remaining, darts: darts, out: out) != null;
}
