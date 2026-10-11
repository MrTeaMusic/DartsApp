import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../domain/caller_phrases.dart';
import '../domain/voice_picker.dart';
import 'speech_engine.dart';

/// Sprachausgabe über die Text-to-Speech der Plattform (Paket `flutter_tts`):
/// AVSpeechSynthesizer auf macOS/iOS, Windows.Media.SpeechSynthesis auf
/// Windows.
///
/// Die Stimme wird beim ersten Sprechen bzw. beim Sprachwechsel gewählt
/// (siehe [pickVoice]). Fehlt eine passende Stimme oder wirft die Plattform,
/// geht es still mit der Standardstimme weiter bzw. der Caller schweigt.
class FlutterTtsSpeechEngine implements SpeechEngine {
  FlutterTts? _tts;
  CallerLanguage? _voiceFor;
  bool _initFailed = false;

  Future<FlutterTts?> _ready() async {
    if (_tts != null || _initFailed) return _tts;
    try {
      final tts = FlutterTts();
      await tts.awaitSpeakCompletion(true);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Hörbar auch neben Musik; andere Audioquellen werden kurz leiser.
        await tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [IosTextToSpeechAudioCategoryOptions.mixWithOthers, IosTextToSpeechAudioCategoryOptions.duckOthers],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      }
      _tts = tts;
    } catch (e) {
      _initFailed = true;
      debugPrint('Caller: Sprachausgabe nicht verfügbar: $e');
    }
    return _tts;
  }

  Future<void> _selectVoice(FlutterTts tts, CallerLanguage language) async {
    if (_voiceFor == language) return;
    _voiceFor = language;
    try {
      final raw = await tts.getVoices;
      final voices = raw is List ? raw.map(VoiceInfo.fromPlatform).whereType<VoiceInfo>() : const <VoiceInfo>[];
      final voice = pickVoice(voices, language);
      if (voice != null) {
        await tts.setVoice(voice.toPlatform());
        return;
      }
    } catch (e) {
      debugPrint('Caller: Stimmen nicht lesbar: $e');
    }
    try {
      await tts.setLanguage(language.fallbackLocale);
    } catch (_) {
      // Keine Stimme für die Sprache: Standardstimme der Plattform.
    }
  }

  @override
  Future<void> speak(String text, SpeechOptions options) async {
    final tts = await _ready();
    if (tts == null) return;
    try {
      await _selectVoice(tts, options.language);
      await tts.setVolume(options.volume);
      await tts.setSpeechRate(options.rate);
      await tts.setPitch(options.pitch);
      await tts.speak(text);
    } catch (e) {
      debugPrint('Caller: Sprechen fehlgeschlagen: $e');
    }
  }

  @override
  Future<void> stop() async {
    final tts = _tts;
    if (tts == null) return;
    try {
      await tts.stop();
    } catch (_) {}
  }
}
