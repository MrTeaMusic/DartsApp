import '../../board/domain/segment.dart';
import '../../games/domain/games/checkout/checkout_calculator.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../../games/domain/games/checkout/setup_advisor.dart';

/// Warum ein eingegebener Weg kein Checkout ist.
enum RouteProblem {
  /// Kein Dart eingegeben.
  empty,

  /// Mehr Darts als übrig.
  tooManyDarts,

  /// Ein Dart ist daneben (Miss) – im Quiz nicht sinnvoll.
  miss,

  /// Unterwegs überworfen: Rest unter 0 oder (Double-Out) Rest 1, bevor
  /// der letzte Dart geworfen ist.
  bust,

  /// Die Summe stimmt nicht.
  total,

  /// Der letzte Dart ist kein erlaubtes Finish (Double bzw. Bull).
  finish,
}

/// Ergebnis der Prüfung eines Checkout-Wegs.
class RouteCheck {
  const RouteCheck({required this.route, required this.sum, this.problem, this.recommended = false});

  final List<Segment> route;

  /// Summe der eingegebenen Darts.
  final int sum;

  /// `null` = gültiger Checkout.
  final RouteProblem? problem;

  /// Entspricht dem Weg, den die App vorschlägt (Reihenfolge der
  /// Aufbau-Darts egal).
  final bool recommended;

  bool get valid => problem == null;
}

/// Wie gut ein Rest für die nächste Aufnahme ist: 1 = Ein-Dart-Finish,
/// 2 = Zwei-Dart-Finish, 3 = Drei-Dart-Finish, 4 = kein Finish.
int leaveTier(int leave, OutMode out) {
  for (var d = 1; d <= 3; d++) {
    if (CheckoutRules.isCheckout(leave, darts: d, out: out)) return d;
  }
  return 4;
}

/// Ergebnis der Prüfung eines Stell-Wegs (wenn kein Finish möglich ist).
class SetupCheck {
  const SetupCheck({
    required this.route,
    required this.leave,
    required this.tier,
    required this.advice,
    required this.adviceTier,
    this.problem,
  });

  final List<Segment> route;

  /// Rest nach den Stell-Darts.
  final int leave;

  /// [leaveTier] des Rests (4 bei ungültigem Weg).
  final int tier;

  /// Vorschlag des [SetupAdvisor]; `null`, wenn er keinen hat.
  final SetupPlan? advice;

  /// [leaveTier] des vorgeschlagenen Rests (4 ohne Vorschlag).
  final int adviceTier;

  /// [RouteProblem.empty], [RouteProblem.tooManyDarts], [RouteProblem.miss]
  /// oder [RouteProblem.bust] (Rest unter 2); sonst `null`.
  final RouteProblem? problem;

  bool get valid => problem == null;

  /// Gut gestellt: gültig und der Rest ist mindestens so gut wie der des
  /// Vorschlags (gleiche Stufe: Ein-, Zwei- oder Drei-Dart-Finish).
  bool get good => valid && tier <= adviceTier;

  /// Gleicher Rest wie der Vorschlag.
  bool get recommended => valid && advice != null && leave == advice!.leave;
}

/// Prüft Checkout- und Stell-Wege für das Quiz. Reine Funktionen auf
/// Grundlage von [CheckoutRules] und [SetupAdvisor].
abstract final class CheckoutRoutes {
  /// Kann [score] mit [darts] Darts gecheckt werden?
  static bool possible(int score, int darts, OutMode out) => CheckoutRules.isCheckout(score, darts: darts, out: out);

  /// Vorschlag der App (wenigste Darts, bevorzugte Felder) oder `null`.
  static List<Segment>? recommended(int score, int darts, OutMode out) =>
      CheckoutRules.suggest(score, darts: darts, out: out);

  /// Prüft, ob [route] [score] mit höchstens [darts] Darts checkt. Jeder
  /// gültige Weg zählt, nicht nur der Vorschlag.
  static RouteCheck check(int score, int darts, List<Segment> route, OutMode out) {
    final sum = route.fold<int>(0, (a, s) => a + s.score);
    RouteCheck bad(RouteProblem p) => RouteCheck(route: route, sum: sum, problem: p);
    if (route.isEmpty) return bad(RouteProblem.empty);
    if (route.length > darts) return bad(RouteProblem.tooManyDarts);
    if (route.any((s) => s.isMiss)) return bad(RouteProblem.miss);
    var rest = score;
    for (var i = 0; i < route.length - 1; i++) {
      rest -= route[i].score;
      if (rest < 0 || rest == 0 || (out != OutMode.straight && rest == 1)) return bad(RouteProblem.bust);
    }
    if (sum != score) return bad(sum > score ? RouteProblem.bust : RouteProblem.total);
    if (!CheckoutRules.isFinisher(route.last, out)) return bad(RouteProblem.finish);
    final rec = recommended(score, darts, out);
    return RouteCheck(route: route, sum: sum, recommended: rec != null && sameRoute(route, rec));
  }

  /// Gleicher Weg: gleiches letztes Feld, gleiche Aufbau-Felder in
  /// beliebiger Reihenfolge (innere/äußere Single egal).
  static bool sameRoute(List<Segment> a, List<Segment> b) {
    if (a.length != b.length || a.isEmpty) return false;
    if (!a.last.sameField(b.last)) return false;
    final rest = [for (final s in b.sublist(0, b.length - 1)) s];
    for (final s in a.sublist(0, a.length - 1)) {
      final i = rest.indexWhere((r) => r.sameField(s));
      if (i < 0) return false;
      rest.removeAt(i);
    }
    return rest.isEmpty;
  }

  /// Andere gültige Wege neben dem Vorschlag, bester zuerst: mit derselben
  /// Dartzahl wie der Vorschlag, bei zu wenigen auch mit einem Dart mehr.
  static List<List<Segment>> alternatives(int score, int darts, OutMode out, {int limit = 3}) {
    final rec = recommended(score, darts, out);
    if (rec == null) return const [];
    final out0 = <List<Segment>>[];
    for (var n = rec.length; n <= darts && out0.length < limit; n++) {
      for (final r in CheckoutCalculator.routes(score,
          darts: n, doubleOut: out != OutMode.straight, masterOut: out == OutMode.master, limit: 12)) {
        if (sameRoute(r, rec) || out0.any((o) => sameRoute(o, r))) continue;
        out0.add(r);
        if (out0.length >= limit) break;
      }
    }
    return out0;
  }

  /// Stell-Vorschlag der App für einen nicht checkbaren Rest.
  static SetupPlan? setupAdvice(int score, int darts, OutMode out) =>
      SetupAdvisor.suggest(score, darts: darts, out: out);

  /// Prüft einen Stell-Weg: höchstens [darts] Darts, danach bleibt ein Rest
  /// von mindestens 2 (Double-Out) bzw. 1. Gut ist er, wenn der Rest
  /// mindestens so gut ist wie der des [SetupAdvisor].
  static SetupCheck checkSetup(int score, int darts, List<Segment> route, OutMode out) {
    final sum = route.fold<int>(0, (a, s) => a + s.score);
    final leave = score - sum;
    final advice = setupAdvice(score, darts, out);
    final min = out == OutMode.straight ? 1 : 2;
    final problem = route.isEmpty
        ? RouteProblem.empty
        : route.length > darts
            ? RouteProblem.tooManyDarts
            : route.any((s) => s.isMiss)
                ? RouteProblem.miss
                : leave < min
                    ? RouteProblem.bust
                    : null;
    return SetupCheck(
      route: route,
      leave: leave,
      tier: problem == null ? leaveTier(leave, out) : 4,
      advice: advice,
      adviceTier: advice == null ? 4 : leaveTier(advice.leave, out),
      problem: problem,
    );
  }
}
