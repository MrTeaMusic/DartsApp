import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';
import 'checkout/checkout_rules.dart';

/// Genau 100 („Nine Dart Century“): pro Versuch genau [target] Punkte
/// erreichen, mit höchstens [visitsPerAttempt] Aufnahmen.
///
/// Regeln:
/// * Alle Treffer zählen ihren normalen Wert. Genau das Ziel = Erfolg, auch
///   vor dem letzten Dart (Versuch sofort vorbei).
/// * Überworfen: [bustOnOvershoot] aus = Versuch gescheitert; an = Aufnahme
///   zählt nicht (Stand zurück), ist aber verbraucht.
class ExactScore extends TrainingGame {
  ExactScore({
    required super.seed,
    this.target = 100,
    this.visitsPerAttempt = 3,
    this.bustOnOvershoot = false,
    this.attempts = 5,
  });

  static const String id = 'exact_score';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'target': 100, 'visitsPerAttempt': 3, 'overshoot': 'fail', 'attempts': 5},
    options: const [
      IntChoiceOption('target', [60, 100, 150, 200]),
      IntChoiceOption('visitsPerAttempt', [2, 3]),
      ChoiceOption('overshoot', ['fail', 'bust']),
      IntOption('attempts', min: 1, max: 20),
    ],
    create: (c, seed) => ExactScore(
      seed: seed,
      target: c.intOf('target', 100),
      visitsPerAttempt: c.intOf('visitsPerAttempt', 3).clamp(1, 3),
      bustOnOvershoot: c.stringOf('overshoot', 'fail') == 'bust',
      attempts: c.intOf('attempts', 5),
    ),
  );

  final int target;
  final int visitsPerAttempt;
  final bool bustOnOvershoot;
  final int attempts;

  int score = 0;
  int _visitStartScore = 0;
  int _visitsUsed = 0;
  int _attemptDarts = 0;
  bool _justAdvanced = false;

  /// (Erfolg, Darts, Abstand zum Ziel) je Versuch.
  final List<({bool success, int darts, int gap})> results = [];

  int get remaining => target - score;
  int get successes => results.where((r) => r.success).length;

  @override
  void onVisitStart() => _visitStartScore = score;

  @override
  void handleDart(DartThrow dart) {
    _attemptDarts++;
    final next = score + dart.score;
    if (next == target) {
      score = next;
      events.add(GameEvent(GameEventType.visitSuccess, value: target));
      _endAttempt(success: true, gap: 0, closing: true);
    } else if (next > target) {
      if (bustOnOvershoot) {
        score = _visitStartScore;
        events.add(GameEvent(GameEventType.bust, value: next));
        closeVisit();
      } else {
        score = next;
        events.add(GameEvent(GameEventType.failed, value: next));
        _endAttempt(success: false, gap: next - target, closing: true);
      }
    } else {
      score = next;
    }
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    if (_justAdvanced) {
      _justAdvanced = false;
      return;
    }
    _visitsUsed++;
    if (_visitsUsed < visitsPerAttempt) {
      _visitStartScore = score;
      return;
    }
    events.add(GameEvent(GameEventType.failed, value: score));
    _endAttempt(success: false, gap: target - score, closing: false);
  }

  void _endAttempt({required bool success, required int gap, required bool closing}) {
    results.add((success: success, darts: _attemptDarts, gap: gap));
    if (results.length >= attempts) {
      finish();
      return;
    }
    score = 0;
    _visitStartScore = 0;
    _visitsUsed = 0;
    _attemptDarts = 0;
    if (closing) {
      _justAdvanced = true;
      closeVisit();
    }
  }

  /// Weg zum genauen Ziel mit den restlichen Darts der Aufnahme.
  List<Segment>? get suggestion =>
      finished ? null : CheckoutRules.suggest(remaining, darts: dartsLeftInVisit, out: OutMode.straight);

  @override
  Set<Segment> get targets {
    final s = suggestion;
    return s == null || s.isEmpty ? const {} : {s.first};
  }

  @override
  GameDisplay get display => GameDisplay(
        headline: '$remaining',
        headlineKey: 'remaining',
        suggestion: suggestion,
        progress: results.length / attempts,
        progressLabel: '${(results.length + (finished ? 0 : 1)).clamp(1, attempts)}/$attempts',
        stats: [
          GameStat('points', '$score/$target'),
          GameStat('visitsLeft', '${visitsPerAttempt - _visitsUsed}'),
          GameStat('successes', '$successes/${results.length}'),
        ],
      );

  @override
  GameResult get result {
    final ok = results.where((r) => r.success).toList();
    final failed = results.where((r) => !r.success).toList();
    final rate = results.isEmpty ? null : ok.length / results.length;
    final avgDarts = ok.isEmpty ? null : ok.fold<int>(0, (s, r) => s + r.darts) / ok.length;
    final avgGap = failed.isEmpty ? null : failed.fold<int>(0, (s, r) => s + r.gap) / failed.length;
    return GameResult(
      metrics: {
        'successes': ok.length,
        'successRate': rate ?? 0,
        'averageDarts': ?avgDarts,
        'averageGap': ?avgGap,
        'attempts': results.length,
        'darts': dartsThrown,
        'completed': results.length >= attempts ? 1 : 0,
      },
      summary: [
        GameStat('successes', '${ok.length}/${results.length}'),
        GameStat('successRate', formatPercent(rate)),
        GameStat('averageDarts', formatDecimal(avgDarts)),
        GameStat('averageGap', formatDecimal(avgGap)),
      ],
      details: {
        'attempts': [for (final r in results) {'success': r.success, 'darts': r.darts, 'gap': r.gap}],
      },
    );
  }
}
