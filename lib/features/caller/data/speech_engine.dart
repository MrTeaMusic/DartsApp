import '../domain/caller_phrases.dart';

/// Wie gesprochen wird.
class SpeechOptions {
  const SpeechOptions({required this.language, this.volume = 1, this.rate = 0.5, this.pitch = 1});
  final CallerLanguage language;

  /// 0–1.
  final double volume;

  /// Plattform-Tempo, 0,5 = normal.
  final double rate;

  /// 1 = normal.
  final double pitch;
}

/// Sprachausgabe. In der App die Text-to-Speech der Plattform
/// (`FlutterTtsSpeechEngine`), in Tests ein Fake, der nur mitschreibt.
abstract interface class SpeechEngine {
  /// Spricht [text]. Das Future endet, wenn der Text fertig gesprochen ist
  /// (oder sofort, wenn die Plattform das nicht meldet). Fehler werden
  /// geschluckt: Ohne Stimme bleibt der Caller still.
  Future<void> speak(String text, SpeechOptions options);

  /// Bricht die laufende Ausgabe ab.
  Future<void> stop();
}

/// Spricht nichts. Fallback für Plattformen ohne Sprachausgabe.
class SilentSpeechEngine implements SpeechEngine {
  const SilentSpeechEngine();

  @override
  Future<void> speak(String text, SpeechOptions options) async {}

  @override
  Future<void> stop() async {}
}
