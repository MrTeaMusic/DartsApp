import '../../games/domain/games/checkout/checkout_rules.dart';
import 'checkout_route.dart';

/// Spiel-ID der Quiz-Sessions im Verlauf und in der Statistik. Das Quiz
/// steht nicht im `GameCatalog`, weil es keine Würfe hat.
const String checkoutQuizGameId = 'checkout_quiz';

/// Training: ohne Zeitlimit, Erklärung nach jeder Antwort. Zeit: eine
/// Minute, so viele richtige Antworten wie möglich.
enum QuizMode { training, timed }

/// Welche Reste abgefragt werden.
enum QuizRange {
  low(2, 40),
  mid(41, 100),
  high(101, 170),
  all(2, 170);

  const QuizRange(this.min, this.max);
  final int min;
  final int max;

  String get label => '$min–$max';
}

/// Wie viele Darts noch übrig sind. [mixed] wählt je Frage 1, 2 oder 3
/// (1 Dart nur bis 60, 2 Darts bis 120).
enum QuizDarts {
  three(3),
  two(2),
  one(1),
  mixed(0);

  const QuizDarts(this.count);
  final int count;
}

/// Ein Rest mit der Zahl der übrigen Darts, z. B. 121 mit 3 Darts.
class QuizKey {
  const QuizKey(this.score, this.darts);
  final int score;
  final int darts;

  @override
  bool operator ==(Object other) => other is QuizKey && other.score == score && other.darts == darts;

  @override
  int get hashCode => Object.hash(score, darts);

  @override
  String toString() => '$score/$darts';
}

/// Einstellungen eines Quiz-Durchgangs.
class QuizConfig {
  const QuizConfig({
    this.mode = QuizMode.training,
    this.range = QuizRange.all,
    this.darts = QuizDarts.three,
    this.onlyCheckable = false,
    this.askSetup = true,
    this.out = OutMode.double,
    this.seconds = timedSeconds,
  });

  /// Dauer im Modus Zeit.
  static const int timedSeconds = 60;

  final QuizMode mode;
  final QuizRange range;
  final QuizDarts darts;

  /// Nur Reste, die mit den übrigen Darts checkbar sind (keine Bogeys wie
  /// 169 mit drei Darts, keine Stell-Fragen).
  final bool onlyCheckable;

  /// Nach richtigem „Nicht möglich“ fragen, wie man sich stellt.
  final bool askSetup;
  final OutMode out;
  final int seconds;

  bool get timed => mode == QuizMode.timed;

  /// Alle Fragen, die diese Einstellungen erlauben.
  List<QuizKey> pool() {
    final keys = <QuizKey>[];
    for (var s = range.min; s <= range.max; s++) {
      final dartsFor = switch (darts) {
        QuizDarts.mixed => [3, if (s <= 120) 2, if (s <= 60) 1],
        _ => [darts.count],
      };
      for (final d in dartsFor) {
        if (onlyCheckable && !CheckoutRoutes.possible(s, d, out)) continue;
        keys.add(QuizKey(s, d));
      }
    }
    return keys;
  }

  QuizConfig copyWith({
    QuizMode? mode,
    QuizRange? range,
    QuizDarts? darts,
    bool? onlyCheckable,
    bool? askSetup,
    OutMode? out,
  }) =>
      QuizConfig(
        mode: mode ?? this.mode,
        range: range ?? this.range,
        darts: darts ?? this.darts,
        onlyCheckable: onlyCheckable ?? this.onlyCheckable,
        askSetup: askSetup ?? this.askSetup,
        out: out ?? this.out,
        seconds: seconds,
      );

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'range': range.name,
        'darts': darts.name,
        'onlyCheckable': onlyCheckable,
        'askSetup': askSetup,
        'outMode': out.name,
        if (timed) 'seconds': seconds,
      };

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.where((v) => v.name == name).firstOrNull ?? fallback;

  factory QuizConfig.fromJson(Map<String, Object?> j) => QuizConfig(
        mode: _enum(QuizMode.values, j['mode'], QuizMode.training),
        range: _enum(QuizRange.values, j['range'], QuizRange.all),
        darts: _enum(QuizDarts.values, j['darts'], QuizDarts.three),
        onlyCheckable: j['onlyCheckable'] == true,
        askSetup: j['askSetup'] != false,
        // Straight-Out ergibt kein sinnvolles Quiz.
        out: j['outMode'] == OutMode.master.name ? OutMode.master : OutMode.double,
        seconds: (j['seconds'] as num?)?.toInt() ?? timedSeconds,
      );

  @override
  bool operator ==(Object other) =>
      other is QuizConfig &&
      other.mode == mode &&
      other.range == range &&
      other.darts == darts &&
      other.onlyCheckable == onlyCheckable &&
      other.askSetup == askSetup &&
      other.out == out &&
      other.seconds == seconds;

  @override
  int get hashCode => Object.hash(mode, range, darts, onlyCheckable, askSetup, out, seconds);
}
