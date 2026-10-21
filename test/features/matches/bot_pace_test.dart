import 'dart:math' as math;

import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/matches/domain/bot_pace.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:dartlab/features/matches/presentation/match_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/pump_app.dart';

/// Zwei Bots, damit der Test nur das Tempo prüft (kein Mensch, keine Quelle).
const botVsBot = MatchSetup(
  format: MatchFormat(startScore: 501, legsToWin: 3),
  players: [MatchPlayer.bot('Anna', average: 60), MatchPlayer.bot('Bert', average: 60)],
);

void main() {
  group('BotPace', () {
    test('Zügig sind die alten Zeiten, Gemütlich der neue Standard', () {
      expect(BotPace.defaultPace, BotPace.relaxed);
      expect((BotPace.quick.firstDartMs, BotPace.quick.betweenDartsMs, BotPace.quick.takeoutMs), (1200, 850, 1600));
      expect((BotPace.relaxed.firstDartMs, BotPace.relaxed.betweenDartsMs, BotPace.relaxed.takeoutMs), (2400, 1700, 2800));
    });

    test('Sehr gemütlich ist das 1,6-fache von Gemütlich', () {
      expect(BotPace.veryRelaxed.firstDartMs, 2400 * 1.6);
      expect(BotPace.veryRelaxed.betweenDartsMs, 1700 * 1.6);
      expect(BotPace.veryRelaxed.takeoutMs, 2800 * 1.6);
    });

    test('byName: bekannte Namen, sonst Gemütlich', () {
      for (final p in BotPace.values) {
        expect(BotPace.byName(p.name), p);
      }
      expect(BotPace.byName(null), BotPace.relaxed);
      expect(BotPace.byName('quatsch'), BotPace.relaxed);
    });
  });

  group('BotTiming', () {
    test('Ohne Angaben: die Zeiten von Gemütlich, ohne Streuung', () {
      const t = BotTiming();
      expect(t.firstDart, const Duration(milliseconds: 2400));
      expect(t.betweenDarts, const Duration(milliseconds: 1700));
      expect(t.takeout, const Duration(milliseconds: 2800));
      expect(t.jitter, 0);
      expect(t.jittered(t.firstDart, math.Random(1)), t.firstDart);
    });

    test('forPace übernimmt die Zeiten und streut mit 15 %', () {
      final t = BotTiming.forPace(BotPace.quick);
      expect(t.firstDart, const Duration(milliseconds: 1200));
      expect(t.betweenDarts, const Duration(milliseconds: 850));
      expect(t.takeout, const Duration(milliseconds: 1600));
      expect(t.jitter, 0.15);
    });

    test('Streuung bleibt innerhalb von +-15 % und nutzt beide Seiten', () {
      final t = BotTiming.forPace(BotPace.relaxed);
      final random = math.Random(42);
      var lo = double.infinity;
      var hi = 0.0;
      for (var i = 0; i < 2000; i++) {
        final d = t.jittered(t.firstDart, random).inMicroseconds / t.firstDart.inMicroseconds;
        lo = math.min(lo, d);
        hi = math.max(hi, d);
        expect(d, inInclusiveRange(0.85, 1.15));
      }
      expect(lo, lessThan(0.9));
      expect(hi, greaterThan(1.1));
    });

    test('Mit festem Startwert ist die Streuung reproduzierbar', () {
      final t = BotTiming.forPace(BotPace.veryRelaxed);
      List<Duration> run() {
        final r = math.Random(5);
        return [for (var i = 0; i < 5; i++) t.jittered(t.takeout, r)];
      }

      expect(run(), run());
    });
  });

  group('Einstellung', () {
    test('Standard Gemütlich, gespeicherte Wahl wird geladen, Unbekanntes ignoriert', () async {
      SharedPreferences.setMockInitialValues({});
      expect(AppSettings.load(await SharedPreferences.getInstance()).botPace, BotPace.relaxed);
      SharedPreferences.setMockInitialValues({'settings.botPace': 'quick'});
      expect(AppSettings.load(await SharedPreferences.getInstance()).botPace, BotPace.quick);
      SharedPreferences.setMockInitialValues({'settings.botPace': 'warp'});
      expect(AppSettings.load(await SharedPreferences.getInstance()).botPace, BotPace.relaxed);
    });

    test('Speichern und der Zeitgeber folgt der Wahl', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(sp)]);
      addTearDown(c.dispose);
      expect(c.read(botTimingProvider).betweenDarts, const Duration(milliseconds: 1700));
      await c.read(settingsProvider.notifier).update((s) => s.copyWith(botPace: BotPace.veryRelaxed));
      expect(sp.getString('settings.botPace'), 'veryRelaxed');
      expect(c.read(botTimingProvider).betweenDarts, const Duration(milliseconds: 2720));
      await c.read(settingsProvider.notifier).update((s) => s.copyWith(botPace: BotPace.quick));
      expect(c.read(botTimingProvider).firstDart, const Duration(milliseconds: 1200));
    });

    testWidgets('Optionen: Bot-Tempo wählen wird gespeichert', (tester) async {
      final c = await pumpApp(tester);
      c.read(routerProvider).go(Routes.settings);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('bot-pace-selector')), 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Der Bot lässt dir Zeit, etwa zwei Sekunden pro Dart'), findsOneWidget);
      await tester.tap(find.text('Sehr gemütlich'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).botPace, BotPace.veryRelaxed);
      expect(c.read(sharedPreferencesProvider).getString('settings.botPace'), 'veryRelaxed');
      expect(find.text('Der Bot wirft ganz ruhig, knapp drei Sekunden pro Dart'), findsOneWidget);
      await tester.tap(find.text('Zügig'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).botPace, BotPace.quick);
    });
  });

  group('Tempo im Match', () {
    int darts(ProviderContainer c) => c.read(matchControllerProvider)!.session.records.length;
    int current(ProviderContainer c) => c.read(matchControllerProvider)!.match.current;

    Future<ProviderContainer> startBots(WidgetTester tester, {BotTiming timing = const BotTiming()}) async {
      final c = await pumpApp(tester, overrides: [
        botTimingProvider.overrideWithValue(timing),
        botRandomProvider.overrideWithValue(math.Random(1)),
        botPaceRandomProvider.overrideWithValue(math.Random(2)),
      ]);
      await c.read(matchControllerProvider.notifier).start(botVsBot);
      return c;
    }

    testWidgets('Eine Aufnahme mit drei Bot-Darts dauert mit den Standardzeiten 8,6 s', (tester) async {
      final c = await startBots(tester);
      // Erster Dart nach 2400 ms.
      await tester.pump(const Duration(milliseconds: 2399));
      expect(darts(c), 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(darts(c), 1);
      // Zweiter und dritter Dart je 1700 ms später.
      await tester.pump(const Duration(milliseconds: 1699));
      expect(darts(c), 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(darts(c), 2);
      await tester.pump(const Duration(milliseconds: 1700));
      expect(darts(c), 3);
      expect(current(c), 0, reason: 'Darts bleiben stehen (Takeout)');
      // Takeout nach 2800 ms: der nächste Bot ist dran.
      await tester.pump(const Duration(milliseconds: 2799));
      expect(current(c), 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(current(c), 1);
      expect(darts(c), 3);
      // Den Caller ausklingen lassen (Zeitlimit der Ansage), dann aufräumen.
      await c.read(matchControllerProvider.notifier).close();
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Mit Streuung bleibt jede Wartezeit innerhalb von +-15 %', (tester) async {
      final c = await startBots(tester, timing: BotTiming.forPace(BotPace.relaxed));
      await tester.pump(const Duration(milliseconds: 2400 * 85 ~/ 100 - 1));
      expect(darts(c), 0, reason: 'nicht vor 85 % der Zeit');
      await tester.pump(const Duration(milliseconds: 2400 * 30 ~/ 100 + 2));
      expect(darts(c), 1, reason: 'spätestens nach 115 % der Zeit');
      await c.read(matchControllerProvider.notifier).close();
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Im Hintergrund wirft der Bot nicht, danach macht er weiter', (tester) async {
      final c = await startBots(tester);
      final controller = c.read(matchControllerProvider.notifier);
      await tester.pump(const Duration(milliseconds: 2400));
      expect(darts(c), 1);
      controller.pauseBot();
      await tester.pump(const Duration(minutes: 5));
      expect(darts(c), 1);
      controller.resumeBot();
      await tester.pump(const Duration(milliseconds: 1699));
      expect(darts(c), 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(darts(c), 2);
      // Doppeltes Fortsetzen ist harmlos.
      controller.resumeBot();
      await c.read(matchControllerProvider.notifier).close();
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Spielansicht: App im Hintergrund hält den Bot an, zurück geht es weiter', (tester) async {
      final c = await pumpApp(tester, overrides: [
        botTimingProvider.overrideWithValue(const BotTiming()),
        botRandomProvider.overrideWithValue(math.Random(1)),
      ]);
      await c.read(matchControllerProvider.notifier).start(const MatchSetup(
        format: MatchFormat(startScore: 501, legsToWin: 3),
        players: [MatchPlayer.human('Ben'), MatchPlayer.bot('Robo', average: 60)],
        firstStarter: 1,
      ));
      c.read(routerProvider).go(MatchRoutes.play);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 1400));
      expect(darts(c), 1);
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 2));
      expect(darts(c), 1, reason: 'im Hintergrund wirft der Bot nicht');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 1699));
      expect(darts(c), 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(darts(c), 2);
      await c.read(matchControllerProvider.notifier).close();
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Verlassen hält den Bot an, auch wenn er gerade pausiert war', (tester) async {
      final c = await startBots(tester);
      final controller = c.read(matchControllerProvider.notifier);
      controller.pauseBot();
      await controller.close();
      expect(c.read(matchControllerProvider), isNull);
      await tester.pump(const Duration(minutes: 1));
      // Ein neues Match startet wieder mit Bot-Zug (die Pause gilt nicht weiter).
      await controller.start(botVsBot);
      await tester.pump(const Duration(milliseconds: 2400));
      expect(darts(c), 1);
      await controller.close();
      await tester.pump(const Duration(minutes: 1));
      await c.read(matchControllerProvider.notifier).close();
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
