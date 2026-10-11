import 'dart:async';

import 'package:dartlab/features/caller/caller.dart';
import 'package:dartlab/features/caller/data/speech_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_speech_engine.dart';

void main() {
  late FakeSpeechEngine engine;
  late CallerSettings settings;
  late Caller caller;

  setUp(() {
    engine = FakeSpeechEngine();
    settings = const CallerSettings();
    caller = Caller(engine: engine, settings: () => settings);
  });

  test('Aufnahme mit Rest: zwei Sätze nacheinander, Englisch als Standard', () async {
    await caller.visit(score: 140, remaining: 32);
    expect(engine.spoken, ['One hundred and forty', 'You require thirty-two']);
    expect(engine.options.first.language, CallerLanguage.english);
  });

  test('180 wird betont (langsamer, höher)', () async {
    settings = settings.copyWith(rate: 0.5, volume: 0.7);
    await caller.visit(score: 180);
    expect(engine.spoken, ['One hundred and eighty!']);
    final o = engine.options.single;
    expect(o.pitch, greaterThan(1));
    expect(o.rate, lessThan(0.5));
    expect(o.volume, 0.7);
  });

  test('Bust und Checkout', () async {
    await caller.visit(bust: true, remaining: 40);
    await caller.gameShot(GameShotKind.leg);
    expect(engine.spoken, ['Bust', 'You require forty', 'Game shot, and the leg!']);
  });

  test('Deutsch', () async {
    settings = settings.copyWith(language: CallerLanguage.german);
    await caller.visit(score: 0, remaining: 32);
    expect(engine.spoken, ['Keine Punkte', 'Du brauchst zweiunddreißig']);
    expect(engine.options.first.language, CallerLanguage.german);
  });

  test('Aus: nichts wird gesprochen', () async {
    settings = settings.copyWith(enabled: false);
    await caller.gameOn();
    await caller.visit(score: 60);
    await caller.preview();
    expect(engine.spoken, isEmpty);
  });

  test('Einzelne Ansagen abwählbar', () async {
    settings = settings.copyWith(announceScores: false, announceGameOn: false);
    await caller.gameOn();
    await caller.visit(score: 100, remaining: 50);
    await caller.gameShot();
    expect(engine.spoken, ['You require fifty', 'Game shot!']);

    engine.spoken.clear();
    settings = const CallerSettings(announceRemaining: false, announceCheckout: false);
    await caller.visit(score: 100, remaining: 50);
    await caller.gameShot();
    expect(engine.spoken, ['One hundred']);
  });

  test('Hörprobe ignoriert die Auswahl der Ansagen', () async {
    settings = const CallerSettings(announceScores: false, announceRemaining: false);
    await caller.preview();
    expect(engine.spoken, ['One hundred and eighty!', 'You require thirty-two']);
  });

  test('Neue Ansage unterbricht die laufende', () async {
    final slow = _GatedEngine();
    final c = Caller(engine: slow, settings: () => settings);
    final first = c.visit(score: 60, remaining: 40);
    await Future<void>.delayed(Duration.zero);
    final second = c.gameShot();
    slow.release();
    await Future.wait([first, second]);
    // „You require forty“ fällt weg, die Plattform wurde gestoppt.
    expect(slow.spoken, ['Sixty', 'Game shot!']);
    expect(slow.stops, 1);
  });
}

/// Das Sprechen endet erst nach [release].
class _GatedEngine extends FakeSpeechEngine {
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<void> speak(String text, SpeechOptions options) async {
    await super.speak(text, options);
    await _gate.future;
  }
}
