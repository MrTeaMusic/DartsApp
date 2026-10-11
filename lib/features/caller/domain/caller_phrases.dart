/// Sprache des Callers. Englisch wie im Fernsehen, Deutsch wählbar.
enum CallerLanguage {
  english('en', 'en-GB'),
  german('de', 'de-DE');

  const CallerLanguage(this.code, this.fallbackLocale);

  /// Sprachcode, mit dem die Stimmen gefiltert werden.
  final String code;

  /// Gebietsschema, falls keine passende Stimme gefunden wird.
  final String fallbackLocale;
}

/// Wie ein Checkout ausgerufen wird.
enum GameShotKind {
  /// Nur „Game shot“ (Trainingsspiele ohne Legs).
  plain,

  /// Leg gewonnen, es geht weiter.
  leg,

  /// Letztes Leg, das Match ist gewonnen.
  match,
}

/// Ein Ausruf, unabhängig von der Sprache. Der [CallerPhrases]-Baukasten
/// macht daraus Text.
sealed class CallerCall {
  const CallerCall();
}

/// „Game on“ zu Spielbeginn.
class GameOnCall extends CallerCall {
  const GameOnCall();

  @override
  bool operator ==(Object other) => other is GameOnCall;

  @override
  int get hashCode => (GameOnCall).hashCode;

  @override
  String toString() => 'GameOnCall';
}

/// Punkte einer Aufnahme, 0 wird „No score“.
class ScoreCall extends CallerCall {
  const ScoreCall(this.score);
  final int score;

  @override
  bool operator ==(Object other) => other is ScoreCall && other.score == score;

  @override
  int get hashCode => Object.hash(ScoreCall, score);

  @override
  String toString() => 'ScoreCall($score)';
}

/// Überworfen.
class BustCall extends CallerCall {
  const BustCall();

  @override
  bool operator ==(Object other) => other is BustCall;

  @override
  int get hashCode => (BustCall).hashCode;

  @override
  String toString() => 'BustCall';
}

/// Rest auf einem Finish: „You require 32“.
class RequireCall extends CallerCall {
  const RequireCall(this.remaining);
  final int remaining;

  @override
  bool operator ==(Object other) => other is RequireCall && other.remaining == remaining;

  @override
  int get hashCode => Object.hash(RequireCall, remaining);

  @override
  String toString() => 'RequireCall($remaining)';
}

/// Checkout geschafft.
class GameShotCall extends CallerCall {
  const GameShotCall([this.kind = GameShotKind.plain]);
  final GameShotKind kind;

  @override
  bool operator ==(Object other) => other is GameShotCall && other.kind == kind;

  @override
  int get hashCode => Object.hash(GameShotCall, kind);

  @override
  String toString() => 'GameShotCall(${kind.name})';
}

/// Fertiger Text für die Sprachausgabe. [emphasis] spricht etwas langsamer
/// und höher (180, Match gewonnen).
class CallerPhrase {
  const CallerPhrase(this.text, {this.emphasis = false});
  final String text;
  final bool emphasis;

  @override
  bool operator ==(Object other) => other is CallerPhrase && other.text == text && other.emphasis == emphasis;

  @override
  int get hashCode => Object.hash(text, emphasis);

  @override
  String toString() => 'CallerPhrase("$text"${emphasis ? ', emphasis' : ''})';
}

/// Baut die Sätze des Callers. Zahlen werden ausgeschrieben, damit die
/// Stimme sie wie ein Caller spricht („One hundred and forty“ statt
/// „one hundred forty“).
abstract class CallerPhrases {
  const CallerPhrases();

  factory CallerPhrases.of(CallerLanguage language) => switch (language) {
        CallerLanguage.english => const EnglishCallerPhrases(),
        CallerLanguage.german => const GermanCallerPhrases(),
      };

  /// Zahl in Worten, kleingeschrieben. Über 999 als Ziffern.
  String number(int n);

  CallerPhrase gameOn();
  CallerPhrase noScore();
  CallerPhrase bust();
  CallerPhrase requires(int remaining);
  CallerPhrase gameShot(GameShotKind kind);

  /// Punkte einer Aufnahme. 180 mit Nachdruck, 0 als „No score“.
  CallerPhrase score(int score) {
    if (score <= 0) return noScore();
    final text = _capitalize(number(score));
    return score == 180 ? CallerPhrase('$text!', emphasis: true) : CallerPhrase(text);
  }

  CallerPhrase forCall(CallerCall call) => switch (call) {
        GameOnCall() => gameOn(),
        ScoreCall(:final score) => this.score(score),
        BustCall() => bust(),
        RequireCall(:final remaining) => requires(remaining),
        GameShotCall(:final kind) => gameShot(kind),
      };

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class EnglishCallerPhrases extends CallerPhrases {
  const EnglishCallerPhrases();

  static const _small = [
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', //
    'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen',
  ];
  static const _tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

  @override
  String number(int n) {
    if (n < 0 || n > 999) return '$n';
    if (n < 20) return _small[n];
    if (n < 100) {
      final rest = n % 10;
      return rest == 0 ? _tens[n ~/ 10] : '${_tens[n ~/ 10]}-${_small[rest]}';
    }
    final rest = n % 100;
    final hundreds = '${_small[n ~/ 100]} hundred';
    return rest == 0 ? hundreds : '$hundreds and ${number(rest)}';
  }

  @override
  CallerPhrase gameOn() => const CallerPhrase('Game on!');

  @override
  CallerPhrase noScore() => const CallerPhrase('No score');

  @override
  CallerPhrase bust() => const CallerPhrase('Bust');

  @override
  CallerPhrase requires(int remaining) => CallerPhrase('You require ${number(remaining)}');

  @override
  CallerPhrase gameShot(GameShotKind kind) => switch (kind) {
        GameShotKind.plain => const CallerPhrase('Game shot!'),
        GameShotKind.leg => const CallerPhrase('Game shot, and the leg!'),
        GameShotKind.match => const CallerPhrase('Game shot, and the match!', emphasis: true),
      };
}

class GermanCallerPhrases extends CallerPhrases {
  const GermanCallerPhrases();

  static const _small = [
    'null', 'eins', 'zwei', 'drei', 'vier', 'fünf', 'sechs', 'sieben', 'acht', 'neun', 'zehn', //
    'elf', 'zwölf', 'dreizehn', 'vierzehn', 'fünfzehn', 'sechzehn', 'siebzehn', 'achtzehn', 'neunzehn',
  ];
  static const _tens = ['', '', 'zwanzig', 'dreißig', 'vierzig', 'fünfzig', 'sechzig', 'siebzig', 'achtzig', 'neunzig'];

  /// Einer vor „und“ bzw. „hundert“: „ein“ statt „eins“.
  static String _unit(int n) => n == 1 ? 'ein' : _small[n];

  @override
  String number(int n) {
    if (n < 0 || n > 999) return '$n';
    if (n < 20) return _small[n];
    if (n < 100) {
      final rest = n % 10;
      return rest == 0 ? _tens[n ~/ 10] : '${_unit(rest)}und${_tens[n ~/ 10]}';
    }
    final rest = n % 100;
    final hundreds = n ~/ 100 == 1 ? 'hundert' : '${_small[n ~/ 100]}hundert';
    return rest == 0 ? hundreds : '$hundreds${number(rest)}';
  }

  @override
  CallerPhrase gameOn() => const CallerPhrase("Los geht's!");

  @override
  CallerPhrase noScore() => const CallerPhrase('Keine Punkte');

  @override
  CallerPhrase bust() => const CallerPhrase('Überworfen');

  @override
  CallerPhrase requires(int remaining) => CallerPhrase('Du brauchst ${number(remaining)}');

  @override
  CallerPhrase gameShot(GameShotKind kind) => switch (kind) {
        GameShotKind.plain => const CallerPhrase('Ausgecheckt!'),
        GameShotKind.leg => const CallerPhrase('Ausgecheckt, Leg gewonnen!'),
        GameShotKind.match => const CallerPhrase('Ausgecheckt, Match gewonnen!', emphasis: true),
      };
}
