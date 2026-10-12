import 'dart:convert';
import 'dart:math' as math;

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/caller/caller.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/matches/data/match_store.dart';
import 'package:dartlab/features/matches/domain/match_result.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:dartlab/features/matches/presentation/tournament_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_speech_engine.dart';
import '../helpers/pump_app.dart';

/// Board und Zielfelder pulsieren, daher feste Frames statt pumpAndSettle.
Future<void> pumpFrames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const fastBot = BotTiming(
  firstDart: Duration(milliseconds: 100),
  betweenDarts: Duration(milliseconds: 100),
  takeout: Duration(milliseconds: 100),
);

Future<void> openMatches(WidgetTester tester) async {
  await tester.tap(find.text('Training').first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('open-matches')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-matches')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Match gegen die CPU: Bot wirft sichtbar, Checkout gewinnt, nur eigene Darts zählen', (tester) async {
    final speech = FakeSpeechEngine();
    final container = await pumpApp(
      tester,
      speech: speech,
      prefs: {
        MatchStore.setupKey: jsonEncode({
          'opponent': 'cpu',
          'cpuAverage': 20,
          'cpuName': 'Robo',
          'startScore': 101,
          'legs': 1,
          'starter': 'me',
        }),
      },
      overrides: [botTimingProvider.overrideWithValue(fastBot), botRandomProvider.overrideWithValue(math.Random(7))],
    );
    await openMatches(tester);
    await tester.tap(find.byKey(const Key('open-opponent-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('match-cpu-average')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('start-match')),
      300,
      scrollable: find
          .ancestor(of: find.byKey(const Key('match-cpu-average')), matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start-match')));
    await pumpFrames(tester);

    expect(find.byKey(const Key('match-board')), findsOneWidget);
    final state = container.read(matchControllerProvider)!;
    expect(state.setup.players[1].name, 'Robo');
    expect(state.setup.players[1].isBot, isTrue);
    expect(find.text('Du bist dran'), findsOneWidget);
    expect(speech.spoken, ['Game on!']);
    expect(find.byKey(const Key('caller-mute')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('match-remaining-0'))).data, '101');

    // Drei Fehlwürfe, danach ist der Bot dran.
    final source = container.read(dartSourceProvider) as SimulatorSource;
    for (var i = 0; i < 3; i++) {
      source.throwAt(const BoardPoint(0, 1.3));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump();
    expect(container.read(matchControllerProvider)!.match.current, 1);
    expect(find.text('Robo wirft …'), findsOneWidget);
    // Eigene Aufnahme angesagt, dazu der Rest des Bots auf einem Finish.
    expect(speech.spoken.sublist(1), ['No score', 'You require one hundred and one']);

    // Bot-Darts erscheinen nacheinander.
    await tester.pump(const Duration(milliseconds: 110));
    expect(container.read(matchControllerProvider)!.match.players[1].darts, 1);
    await pumpFrames(tester);
    final afterBot = container.read(matchControllerProvider)!.match;
    expect(afterBot.players[1].darts, 3);
    expect(afterBot.current, 0, reason: 'nach dem Bot-Takeout wieder der Mensch');
    expect(afterBot.players[0].remaining, 101);
    // Bot-Aufnahme nach dem dritten Dart angesagt.
    expect(speech.spoken, hasLength(greaterThanOrEqualTo(4)));
    expect(speech.spoken[3], const EnglishCallerPhrases().score(afterBot.players[1].lastVisit!).text);

    // Checkout 101: T20, S9, D16.
    for (final s in [Segment.triple(20), Segment.single(9), Segment.double(16)]) {
      source.throwAt(BoardGeometry.centerOf(s));
      await pumpFrames(tester, 2);
    }
    final done = container.read(matchControllerProvider)!;
    expect(done.ended, isTrue);
    expect(done.match.winner, 0);
    expect(find.text('Ich gewinnt das Match!'), findsOneWidget);
    expect(speech.spoken.last, 'Game shot, and the match!');
    expect(tester.widget<Text>(find.byKey(const Key('match-final-score'))).data, '1 : 0');

    // Gespeichert: eine Session mit den sechs eigenen Darts, keine Bot-Darts.
    await container.read(matchControllerProvider.notifier).pendingWrites;
    final db = container.read(appDatabaseProvider);
    final sessions = await (db.select(db.sessions)..where((s) => s.gameId.equals(matchGameId))).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.finished, isTrue);
    expect(sessions.single.dartCount, 6);
    final throws = await db.select(db.throws).get();
    expect(throws, hasLength(6));
    expect(throws.every((t) => t.source == 'simulator' && t.gameId == matchGameId), isTrue);
    final metrics = (jsonDecode(sessions.single.resultJson!) as Map)['metrics'] as Map;
    expect(metrics['darts'], 6);
    expect(metrics['won'], 1);
    expect(container.read(matchStoreProvider).currentMatch(), isNull);

    await tester.tap(find.byKey(const Key('match-done')));
    await tester.pumpAndSettle();
    expect(container.read(matchControllerProvider), isNull);
    expect(find.byKey(const Key('open-opponent-mode')), findsOneWidget);
  });

  testWidgets('Turnier: Start, Turnierbaum, Spiel unterbrechen und fortsetzen', (tester) async {
    final container = await pumpApp(
      tester,
      overrides: [botTimingProvider.overrideWithValue(fastBot), botRandomProvider.overrideWithValue(math.Random(3))],
    );
    await openMatches(tester);
    await tester.tap(find.byKey(const Key('open-tournament')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tour-preset-sprint')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tour-round-0-value')).evaluate().isNotEmpty, isTrue);
    await tester.scrollUntilVisible(
      find.byKey(const Key('start-tournament')),
      300,
      scrollable: find.ancestor(of: find.byKey(const Key('tour-difficulty')), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start-tournament')));
    await tester.pumpAndSettle();

    final t = container.read(tournamentControllerProvider)!;
    expect(t.bestOf, [3, 3, 5, 7]);
    expect(t.entrants.length, 16);
    expect(find.byKey(const Key('tournament-next')), findsOneWidget);
    expect(find.byKey(const Key('tournament-match-r0-m0')), findsOneWidget);
    expect(find.text('ACHTELFINALE'), findsWidgets);

    await tester.tap(find.byKey(const Key('tournament-play')));
    await pumpFrames(tester);
    final state = container.read(matchControllerProvider)!;
    expect(state.setup.tournamentMatch, '${t.id}/${t.humanMatch!.id}');
    expect(state.setup.format.legsToWin, 2);
    expect(state.setup.players.where((p) => p.isBot), hasLength(1));

    // Unterbrechen: das Spiel bleibt gespeichert.
    await tester.tap(find.byKey(const Key('leave-match')));
    await pumpFrames(tester, 3);
    await tester.tap(find.byKey(const Key('confirm-leave-match')));
    await tester.pumpAndSettle();
    expect(container.read(matchControllerProvider), isNull);
    expect(container.read(matchStoreProvider).currentMatch()?.setup.tournamentMatch, state.setup.tournamentMatch);
    expect(find.text('Fortsetzen'), findsOneWidget);

    // Turnier verwerfen.
    await tester.tap(find.byKey(const Key('tournament-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tournament-discard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-discard-tournament')));
    await tester.pumpAndSettle();
    expect(container.read(tournamentControllerProvider), isNull);
    expect(container.read(matchStoreProvider).currentMatch(), isNull);
  });
}
