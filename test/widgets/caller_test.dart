import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/caller/caller.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_speech_engine.dart';
import '../helpers/pump_app.dart';

/// Im laufenden Spiel pulsieren die Zielfelder, daher feste Frames statt
/// pumpAndSettle.
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> startGame(WidgetTester tester, FakeSpeechEngine speech, String id, Map<String, Object?> config) async {
  final c = await pumpApp(tester, speech: speech);
  await c.read(activeGameProvider.notifier).start(GameCatalog.all.firstWhere((g) => g.id == id), config, seed: 7);
  c.read(routerProvider).go(Routes.play);
  await pumpFrames(tester);
  return c;
}

Future<void> throwDarts(WidgetTester tester, ProviderContainer c, List<Segment> segments) async {
  final source = c.read(dartSourceProvider) as SimulatorSource;
  for (final s in segments) {
    source.throwAt(BoardGeometry.centerOf(s));
    await pumpFrames(tester);
  }
}

void main() {
  final t20 = Segment.triple(20);

  testWidgets('X01: Caller sagt „Game on“, die 180 und den Rest auf dem Finish an', (tester) async {
    final speech = FakeSpeechEngine();
    final c = await startGame(tester, speech, 'x01', {'startScore': 501});
    expect(speech.spoken, ['Game on!']);

    await throwDarts(tester, c, [t20, t20]);
    expect(speech.spoken, ['Game on!'], reason: 'erst nach der vollen Aufnahme');
    await throwDarts(tester, c, [t20]);
    expect(speech.spoken, ['Game on!', 'One hundred and eighty!']);

    await throwDarts(tester, c, [t20, t20, t20]);
    expect(speech.spoken.skip(2), ['One hundred and eighty!', 'You require one hundred and forty-one']);

    // Rückgängig sagt nichts an, die korrigierte Aufnahme wird neu angesagt.
    final before = speech.spoken.length;
    c.read(activeGameProvider.notifier).undo();
    await pumpFrames(tester);
    expect(speech.spoken.length, before);
    await throwDarts(tester, c, [Segment.single(20)]);
    // 120 + 20 = 140, Rest 181 ist kein Finish.
    expect(speech.spoken.skip(before), ['One hundred and forty']);
  });

  testWidgets('Stumm-Knopf in der App-Leiste schaltet den Caller ab', (tester) async {
    final speech = FakeSpeechEngine();
    final c = await startGame(tester, speech, 'x01', {'startScore': 501});
    expect(find.byKey(const Key('caller-mute')), findsOneWidget);

    await tester.tap(find.byKey(const Key('caller-mute')));
    await pumpFrames(tester);
    expect(c.read(callerSettingsProvider).enabled, isFalse);
    expect(c.read(sharedPreferencesProvider).getBool('caller.enabled'), isFalse);
    expect(speech.stops, greaterThan(0));

    await throwDarts(tester, c, [t20, t20, t20]);
    expect(speech.spoken, ['Game on!']);

    await tester.tap(find.byKey(const Key('caller-mute')));
    await pumpFrames(tester);
    await throwDarts(tester, c, [Segment.single(20), Segment.single(1), Segment.miss]);
    expect(speech.spoken.last, 'Twenty-one');
  });

  testWidgets('Around the Clock bleibt still', (tester) async {
    final speech = FakeSpeechEngine();
    final c = await startGame(tester, speech, 'around_the_clock', const {});
    await throwDarts(tester, c, [Segment.single(1), Segment.single(2), Segment.single(3)]);
    expect(speech.spoken, isEmpty);
  });

  testWidgets('Optionen: Caller an/aus und Sprache', (tester) async {
    final speech = FakeSpeechEngine();
    final c = await pumpApp(tester, speech: speech);
    c.read(routerProvider).go(Routes.settings);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('caller-enabled'));
    await tester.scrollUntilVisible(toggle, 300, scrollable: find.byType(Scrollable).last);
    expect(c.read(callerSettingsProvider).enabled, isTrue);
    expect(find.byKey(const Key('caller-language')), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(c.read(callerSettingsProvider).enabled, isFalse);
    expect(c.read(sharedPreferencesProvider).getBool('caller.enabled'), isFalse);
    expect(find.byKey(const Key('caller-language')), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    expect(c.read(callerSettingsProvider).language, CallerLanguage.german);
    expect(c.read(sharedPreferencesProvider).getString('caller.language'), 'german');
    await tester.scrollUntilVisible(find.byKey(const Key('caller-preview')), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('„Du brauchst zweiunddreißig“'), findsOneWidget);

    await tester.tap(find.byKey(const Key('caller-preview')));
    await tester.pumpAndSettle();
    expect(speech.spoken, ['Hundertachtzig!', 'Du brauchst zweiunddreißig']);
  });
}
