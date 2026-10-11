import 'package:dartlab/features/caller/data/speech_engine.dart';

/// Schreibt mit, was der Caller sprechen würde. Ersetzt in Tests die echte
/// Sprachausgabe, damit kein Plattform-Plugin angesprochen wird.
class FakeSpeechEngine implements SpeechEngine {
  final List<String> spoken = [];
  final List<SpeechOptions> options = [];
  int stops = 0;

  @override
  Future<void> speak(String text, SpeechOptions options) async {
    spoken.add(text);
    this.options.add(options);
  }

  @override
  Future<void> stop() async => stops++;
}
