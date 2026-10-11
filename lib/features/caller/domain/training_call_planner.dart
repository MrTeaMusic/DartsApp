import '../../games/domain/engine/game_display.dart';
import '../../games/domain/engine/training_game.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import 'caller_phrases.dart';

/// Entscheidet, was der Caller bei einem Trainingsspiel ausruft.
///
/// Statt Spiel-IDs zu kennen, liest er die Daten, die jedes Spiel ohnehin
/// liefert:
/// * Ein 3-Dart-Average (`average` in den Kennzahlen) heißt: jeder Dart
///   zählt seinen Wert, die Punkte der Aufnahme sind sinnvoll (X01,
///   Scoring-Drills).
/// * Eine Checkout-Quote (`checkoutRate`) und die Anzeige `remaining`
///   heißen: es gibt einen Rest, der ausgecheckt wird (X01, 121,
///   Checkout-Training, Catch 40). Dann gibt es „Bust“, „You require“ und
///   „Game shot“.
/// * Alles andere (Around the Clock, Cricket, …) bleibt still.
class TrainingCallPlanner {
  const TrainingCallPlanner._();

  static bool _scoring(TrainingGame game) => game.result.metrics.containsKey('average');
  static bool _checkoutGame(TrainingGame game) => game.result.metrics.containsKey('checkoutRate');

  /// Ruft der Caller bei diesem Spiel überhaupt etwas aus?
  static bool isCallable(TrainingGame game) => _scoring(game) || _checkoutGame(game);

  /// Ausrufe für die gerade abgeschlossene Aufnahme von [game].
  /// [before] ist die Anzeige vor dieser Aufnahme.
  static List<CallerCall> forVisit(TrainingGame game, {required GameDisplay before}) {
    if (!isCallable(game)) return const [];
    final events = game.events.map((e) => e.type).toSet();
    if (events.contains(GameEventType.checkout)) {
      final kind = !events.contains(GameEventType.legComplete)
          ? GameShotKind.plain
          : game.finished
              ? GameShotKind.match
              : GameShotKind.leg;
      return [GameShotCall(kind)];
    }
    final calls = <CallerCall>[
      if (events.contains(GameEventType.bust)) const BustCall() else ScoreCall(_visitScore(game, before)),
    ];
    final remaining = _finishRemaining(game);
    if (remaining != null) calls.add(RequireCall(remaining));
    return calls;
  }

  /// Punkte der Aufnahme. Solange bei Double-In noch nicht eröffnet ist,
  /// zählt nur, was vom Rest abgezogen wurde.
  static int _visitScore(TrainingGame game, GameDisplay before) {
    if (before.headlineKey == 'doubleToStart') {
      final from = int.tryParse(before.headline);
      final to = int.tryParse(game.display.headline);
      if (from == null || to == null || to > from) return 0;
      return from - to;
    }
    return game.visit.fold(0, (s, d) => s + d.score);
  }

  /// Rest, wenn er mit drei Darts auscheckbar ist, sonst `null`.
  static int? _finishRemaining(TrainingGame game) {
    if (game.finished || !_checkoutGame(game)) return null;
    final display = game.display;
    if (display.headlineKey != 'remaining') return null;
    final n = int.tryParse(display.headline);
    if (n == null || n < 1 || n > 170) return null;
    final finishable = display.suggestion != null || CheckoutRules.isCheckout(n, out: OutMode.double);
    return finishable ? n : null;
  }
}
