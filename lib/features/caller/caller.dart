import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import 'data/flutter_tts_speech_engine.dart';
import 'data/sound_pack_store.dart';
import 'data/sound_player.dart';
import 'data/speech_engine.dart';
import 'domain/caller_phrases.dart';
import 'domain/caller_settings.dart';
import 'domain/sound_pack.dart';

export 'domain/caller_phrases.dart';
export 'domain/caller_settings.dart';
export 'domain/sound_pack.dart';

/// Der Caller: eine Stimme sagt Punkte und Rest an wie bei einem Turnier.
///
/// Öffentliche API für alle Spielmodi (Training, später Match/Turnier):
///
/// ```dart
/// final caller = ref.read(callerProvider);
/// caller.gameOn();                 // „Game on!“
/// caller.visit(score: 140, remaining: 32); // „One hundred and forty“, „You require thirty-two“
/// caller.visit(bust: true);        // „Bust“
/// caller.gameShot(GameShotKind.leg); // „Game shot, and the leg!“
/// caller.announce([ScoreCall(180)]); // beliebige Ausrufe in Reihenfolge
/// caller.stop();
/// ```
///
/// Jeder Aufruf beachtet die Einstellungen ([callerSettingsProvider]):
/// aus/stumm, Sprache, Lautstärke, Tempo und welche Ausrufe gewünscht sind.
/// `remaining` wird nur angesagt, wenn der Aufrufer weiß, dass der Rest
/// auscheckbar ist. Ein neuer Aufruf unterbricht einen noch laufenden.
/// Sind eigene Sounddateien importiert ([CallerSoundPack]), werden sie statt
/// der Stimme abgespielt; fehlt eine Datei, spricht die Stimme diese Ansage.
/// Alle Methoden sind „fire and forget“: Fehler der Plattform werden
/// geschluckt, das Future endet, wenn alles gesprochen ist.
class Caller {
  Caller({
    required this._engine,
    required this._settings,
    this._player = const SilentSoundPlayer(),
    CallerSoundPack Function()? soundPack,
  }) : _soundPack = soundPack ?? (() => CallerSoundPack.empty);

  final SpeechEngine _engine;
  final CallerSettings Function() _settings;
  final SoundPlayer _player;
  final CallerSoundPack Function() _soundPack;
  int _generation = 0;
  bool _speaking = false;

  /// Längste Wartezeit pro Satz, falls die Plattform das Ende nie meldet.
  static const _phraseTimeout = Duration(seconds: 8);

  Future<void> gameOn() => announce(const [GameOnCall()]);

  /// Eine Aufnahme ansagen: Punkte (bzw. „Bust“) und danach optional den
  /// Rest auf einem Finish.
  Future<void> visit({int score = 0, bool bust = false, int? remaining}) => announce([
        if (bust) const BustCall() else ScoreCall(score),
        if (remaining != null) RequireCall(remaining),
      ]);

  Future<void> gameShot([GameShotKind kind = GameShotKind.plain]) => announce([GameShotCall(kind)]);

  /// Hörprobe für die Einstellungen: „One hundred and eighty!“ und
  /// „You require thirty-two“, unabhängig davon, welche Ausrufe gewählt sind.
  Future<void> preview() {
    final settings = _settings();
    if (!settings.enabled) return Future.value();
    return _speak(const [ScoreCall(180), RequireCall(32)], settings);
  }

  /// Sagt [calls] nacheinander an, gefiltert nach den Einstellungen.
  Future<void> announce(List<CallerCall> calls) {
    final settings = _settings();
    if (!settings.enabled) return Future.value();
    final wanted = [for (final c in calls) if (_wanted(c, settings)) c];
    if (wanted.isEmpty) return Future.value();
    return _speak(wanted, settings);
  }

  Future<void> _speak(List<CallerCall> wanted, CallerSettings settings) async {
    final phrases = CallerPhrases.of(settings.language);
    final pack = settings.useSoundPack ? _soundPack() : CallerSoundPack.empty;
    final generation = ++_generation;
    if (_speaking) await Future.wait([_engine.stop(), _player.stop()]);
    _speaking = true;
    try {
      for (final call in wanted) {
        if (generation != _generation) return;
        if (await _playSounds(pack.pathsFor(call), settings, generation)) continue;
        if (generation != _generation) return;
        final phrase = phrases.forCall(call);
        await _engine
            .speak(
              phrase.text,
              SpeechOptions(
                language: settings.language,
                volume: settings.volume,
                rate: phrase.emphasis ? settings.rate * 0.9 : settings.rate,
                pitch: phrase.emphasis ? 1.15 : 1.0,
              ),
            )
            .timeout(_phraseTimeout, onTimeout: () {});
      }
    } catch (e) {
      debugPrint('Caller: $e');
    } finally {
      if (generation == _generation) _speaking = false;
    }
  }

  /// Spielt [paths] nacheinander. `false`, wenn es keine Dateien gibt oder
  /// die erste nicht abspielbar war: dann spricht die Stimme.
  Future<bool> _playSounds(List<String>? paths, CallerSettings settings, int generation) async {
    if (paths == null) return false;
    for (final (i, path) in paths.indexed) {
      if (generation != _generation) return true;
      final ok = await _player.play(path, settings.volume);
      if (!ok && i == 0) return false;
    }
    return true;
  }

  /// Laufende Ansage abbrechen.
  Future<void> stop() async {
    _generation++;
    _speaking = false;
    await Future.wait([_engine.stop(), _player.stop()]);
  }

  static bool _wanted(CallerCall call, CallerSettings s) => switch (call) {
        GameOnCall() => s.announceGameOn,
        ScoreCall() || BustCall() => s.announceScores,
        RequireCall() => s.announceRemaining,
        GameShotCall() => s.announceCheckout,
      };
}

/// Sprachausgabe. In Tests mit einem Fake überschreiben, damit das echte
/// Plugin nicht angesprochen wird.
final speechEngineProvider = Provider<SpeechEngine>((ref) => FlutterTtsSpeechEngine());

/// Wiedergabe eigener Sounddateien. In Tests mit einem Fake überschreiben.
final soundPlayerProvider = Provider<SoundPlayer>((ref) => AudioplayersSoundPlayer());

/// Ablage der eigenen Sounddateien. In Tests mit einem Temp-Ordner.
final soundPackStoreProvider = Provider<SoundPackStore>((ref) => SoundPackStore());

/// Die importierten eigenen Sounddateien des Callers.
final soundPackProvider = AsyncNotifierProvider<SoundPackNotifier, CallerSoundPack>(SoundPackNotifier.new);

class SoundPackNotifier extends AsyncNotifier<CallerSoundPack> {
  @override
  Future<CallerSoundPack> build() async {
    try {
      return await ref.watch(soundPackStoreProvider).load();
    } catch (e) {
      // Kein App-Ordner (z. B. in Tests): normale Stimme.
      debugPrint('Caller: Sounddateien nicht lesbar: $e');
      return CallerSoundPack.empty;
    }
  }

  /// Ersetzt das Paket durch die Sounds aus Ordnern, Dateien oder Zips.
  /// Gibt die Zahl der übernommenen Dateien zurück, `null`, wenn keine
  /// Sounds dabei waren (das alte Paket bleibt dann).
  Future<int?> import(List<String> sources) async {
    final pack = await ref.read(soundPackStoreProvider).import(sources);
    if (pack == null) return null;
    state = AsyncData(pack);
    return pack.length;
  }

  Future<void> clear() async {
    await ref.read(soundPackStoreProvider).clear();
    state = const AsyncData(CallerSoundPack.empty);
  }
}

final callerSettingsProvider = NotifierProvider<CallerSettingsNotifier, CallerSettings>(CallerSettingsNotifier.new);

class CallerSettingsNotifier extends Notifier<CallerSettings> {
  @override
  CallerSettings build() => CallerSettings.load(ref.watch(sharedPreferencesProvider));

  Future<void> update(CallerSettings Function(CallerSettings) change) async {
    state = change(state);
    await state.save(ref.read(sharedPreferencesProvider));
  }

  /// Stumm-Knopf: schaltet den Caller an/aus.
  Future<void> toggleEnabled() => update((s) => s.copyWith(enabled: !s.enabled));
}

/// Der Caller-Dienst, siehe [Caller].
final callerProvider = Provider<Caller>((ref) {
  final caller = Caller(
    engine: ref.watch(speechEngineProvider),
    settings: () => ref.read(callerSettingsProvider),
    player: ref.watch(soundPlayerProvider),
    soundPack: () => ref.read(soundPackProvider).value ?? CallerSoundPack.empty,
  );
  // Paket schon beim Start laden, damit die erste Ansage es kennt.
  ref.listen(soundPackProvider, (_, _) {});
  // Stummschalten bricht eine laufende Ansage sofort ab.
  ref.listen(callerSettingsProvider.select((s) => s.enabled), (_, enabled) {
    if (!enabled) unawaited(caller.stop());
  });
  ref.onDispose(() => unawaited(caller.stop()));
  return caller;
});
