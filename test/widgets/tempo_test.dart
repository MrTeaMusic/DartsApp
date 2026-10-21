import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_controller.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/games/bull_drill.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:dartlab/features/matches/presentation/match_routes.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_live_source.dart';
import '../helpers/pump_app.dart';
import '../helpers/tempo_seed.dart';

Future<void> frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> openTempoTab(WidgetTester tester) async {
  await tester.tap(find.text('Statistik').first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('stats-tab-tempo')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('stats-tab-tempo')));
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String key) {
  final f = find.byKey(Key(key));
  final w = tester.widget(f);
  if (w is Text) return w.data ?? '';
  // Kachel: der Wert steht im FittedBox.
  return tester.widget<Text>(find.descendant(of: find.descendant(of: f, matching: find.byType(FittedBox)), matching: find.byType(Text)).first).data ?? '';
}

final base = DateTime(2026, 10, 14, 20);

/// Dart vom Board mit Zeit [seconds] nach [base].
DartThrow timed(String name, double seconds, {DartSourceKind source = DartSourceKind.autodartsLocal}) => DartThrow(
      segment: Segment.tryParse(name)!,
      timestamp: base.add(Duration(milliseconds: (seconds * 1000).round())),
      source: source,
    );

void main() {
  group('Reiter Tempo', () {
    for (final size in [const Size(1440, 900), const Size(390, 844)]) {
      testWidgets('Mit Daten: Kennzahlen, Verlauf, Punkte je Tempo, Training/Match/Online (${size.width.toInt()} px)', (tester) async {
        final c = await pumpApp(tester, size: size);
        final player = await c.read(profileRepositoryProvider).resolve(null);
        await seedTempo(c.read(gameRepositoryProvider), player, DateTime.now());
        await openTempoTab(tester);

        expect(find.byKey(const Key('tempo-empty')), findsNothing);
        expect(textOf(tester, 'tempo-per-dart'), isNot('–'));
        for (final k in ['tempo-per-dart', 'tempo-per-visit', 'tempo-with-takeout']) {
          expect(find.descendant(of: find.byKey(Key(k)), matching: find.textContaining(RegExp(r'^\d+,\d s$|^\d+ s$'))), findsOneWidget, reason: k);
        }
        expect(find.textContaining('zu wenig Daten'), findsNothing);
        final list = find.descendant(of: find.byKey(const Key('stats-list-tempo')), matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(find.byKey(const Key('tempo-bands')), 300, scrollable: list);
        for (final b in ['fast', 'medium', 'slow']) {
          expect(find.byKey(Key('tempo-band-$b')), findsOneWidget);
        }
        await tester.scrollUntilVisible(find.byKey(const Key('tempo-groups')), 300, scrollable: list);
        for (final g in ['training', 'match', 'live']) {
          expect(find.byKey(Key('tempo-group-$g')), findsOneWidget);
        }
        // Mit Takeout nur im Training: Match und Online zeigen einen Strich.
        expect(textOf(tester, 'tempo-group-match-takeout'), '–');
        expect(textOf(tester, 'tempo-group-live-takeout'), '–');
        expect(textOf(tester, 'tempo-group-training-takeout'), endsWith(' s'));
        await tester.scrollUntilVisible(find.byKey(const Key('tempo-rules')), 300, scrollable: list);
        expect(find.byKey(const Key('tempo-used')), findsOneWidget);
        await tester.scrollUntilVisible(find.byKey(const Key('tempo-trend')), -600, scrollable: list);
        expect(find.byKey(const Key('tempo-trend-empty')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Ohne Daten: Hinweis auf das Board, Regeln bleiben', (tester) async {
      await pumpApp(tester, size: const Size(390, 844));
      await openTempoTab(tester);
      expect(find.byKey(const Key('tempo-empty')), findsOneWidget);
      expect(find.text('Noch keine Wurfzeiten'), findsOneWidget);
      expect(find.byKey(const Key('tempo-per-dart')), findsNothing);
      expect(find.byKey(const Key('tempo-empty-skipped')), findsNothing);
      expect(find.byKey(const Key('tempo-rules')), findsOneWidget);
    });

    testWidgets('Simulator und manuelle Eingabe werden ausgelassen und genannt', (tester) async {
      final c = await pumpApp(tester, size: const Size(390, 844));
      final player = await c.read(profileRepositoryProvider).resolve(null);
      final repo = c.read(gameRepositoryProvider);
      final start = DateTime.now().subtract(const Duration(hours: 3));
      await seedTempoSession(repo, player, 'highscore_hunt', start, visits: 14, source: 'simulator');
      await seedTempoSession(repo, player, 'highscore_hunt', start.add(const Duration(hours: 1)), visits: 14, source: 'manual');
      await openTempoTab(tester);
      expect(find.byKey(const Key('tempo-empty')), findsOneWidget);
      expect(find.text('Im Zeitraum: 2 Sessions ohne verlässliche Zeiten.'), findsOneWidget);
    });

    testWidgets('Zu wenig Aufnahmen: „zu wenig Daten“ statt einer Zahl', (tester) async {
      final c = await pumpApp(tester, size: const Size(390, 844));
      final player = await c.read(profileRepositoryProvider).resolve(null);
      await seedTempoSession(c.read(gameRepositoryProvider), player, 'highscore_hunt',
          DateTime.now().subtract(const Duration(hours: 2)),
          visits: 3);
      await openTempoTab(tester);
      expect(find.byKey(const Key('tempo-empty')), findsNothing);
      expect(textOf(tester, 'tempo-per-dart'), '–');
      expect(find.textContaining('Zu wenig Daten (6 von 10)'), findsOneWidget);
      final list = find.descendant(of: find.byKey(const Key('stats-list-tempo')), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.byKey(const Key('tempo-trend-empty')), 300, scrollable: list);
      expect(find.textContaining('mindestens zwei Wochen'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('tempo-band-fast')), 300, scrollable: list);
      expect(find.descendant(of: find.byKey(const Key('tempo-band-fast')), matching: find.text('zu wenig Daten')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Optionen', () {
    testWidgets('Standard an, Schalter wird gespeichert', (tester) async {
      final c = await pumpApp(tester, size: const Size(390, 844));
      expect(c.read(settingsProvider).tempoHint, isTrue);
      c.read(routerProvider).go(Routes.settings);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('tempo-hint-switch')), 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('tempo-hint-switch'))).value, isTrue);
      await tester.tap(find.byKey(const Key('tempo-hint-switch')));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).tempoHint, isFalse);
      expect(c.read(sharedPreferencesProvider).getBool('settings.tempoHint'), isFalse);
    });
  });

  group('Hinweis in der Spielansicht', () {
    Future<ProviderContainer> startMatch(WidgetTester tester, {Size size = const Size(1440, 900), Map<String, Object> prefs = const {}}) async {
      final c = await pumpApp(tester, size: size, prefs: prefs);
      await c.read(matchControllerProvider.notifier).start(const MatchSetup(
            format: MatchFormat(startScore: 501, legsToWin: 2),
            players: [MatchPlayer.human('Ben'), MatchPlayer.human('Gast')],
          ));
      c.read(routerProvider).go(MatchRoutes.play);
      await frames(tester);
      await tester.pump();
      return c;
    }

    void matchDarts(ProviderContainer c, List<DartThrow> darts) {
      final controller = c.read(matchControllerProvider.notifier);
      for (final dart in darts) {
        controller.handle(DartThrown(dart));
      }
    }

    for (final size in [const Size(1440, 900), const Size(390, 844)]) {
      testWidgets('Arena-Match: leise Zeile mit der Aufnahmezeit, ohne Uhr (${size.width.toInt()} px)', (tester) async {
        final c = await startMatch(tester, size: size);
        // Noch kein Dart: keine Zeile.
        expect(find.byKey(const Key('tempo-hint')), findsNothing);
        matchDarts(c, [timed('T20', 0), timed('S20', 3.2)]);
        await frames(tester);
        expect(find.byKey(const Key('tempo-hint')), findsOneWidget);
        expect(textOf(tester, 'tempo-hint'), 'Aufnahme 3,2 s');
        matchDarts(c, [timed('S5', 7.4)]);
        await frames(tester);
        expect(textOf(tester, 'tempo-hint'), 'Aufnahme 7,4 s');
        // Die Zeile ändert sich nur mit einem Dart, nicht mit der Zeit.
        await tester.pump(const Duration(seconds: 30));
        expect(textOf(tester, 'tempo-hint'), 'Aufnahme 7,4 s');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Rückgängig: die Zeit folgt den übrigen Darts', (tester) async {
      final c = await startMatch(tester);
      matchDarts(c, [timed('T20', 0), timed('S20', 3.2), timed('S5', 7.4)]);
      await frames(tester);
      expect(textOf(tester, 'tempo-hint'), 'Aufnahme 7,4 s');
      c.read(matchControllerProvider.notifier).handle(DartUndone(DateTime.now()));
      await frames(tester);
      expect(textOf(tester, 'tempo-hint'), 'Aufnahme 3,2 s');
    });

    testWidgets('Pause zwischen Aufnahmen: die Zeile bleibt bei der letzten Aufnahme des Spielers', (tester) async {
      final c = await startMatch(tester);
      matchDarts(c, [timed('T20', 0), timed('S20', 3), timed('S5', 6)]);
      c.read(matchControllerProvider.notifier).handle(TakeoutFinished(base));
      // Gast wirft, danach ist Ben wieder dran (Pause von zwei Minuten dazwischen).
      matchDarts(c, [timed('S1', 40), timed('S1', 44), timed('S1', 47)]);
      c.read(matchControllerProvider.notifier).handle(TakeoutFinished(base));
      matchDarts(c, [timed('T19', 170)]);
      await frames(tester);
      // Ben: eine Aufnahme mit drei Darts (6 s) und der erste Dart der nächsten; die Pause stört nicht.
      expect(textOf(tester, 'tempo-hint'), 'Aufnahme 6,0 s');
    });

    testWidgets('Simulator und manuelle Eingabe: keine Zeile', (tester) async {
      final c = await startMatch(tester);
      matchDarts(c, [
        timed('T20', 0, source: DartSourceKind.simulator),
        timed('S20', 3.2, source: DartSourceKind.simulator),
        timed('S5', 6, source: DartSourceKind.manual),
      ]);
      await frames(tester);
      expect(find.byKey(const Key('tempo-hint')), findsNothing);
    });

    testWidgets('In den Optionen aus: keine Zeile', (tester) async {
      final c = await startMatch(tester, prefs: {'settings.tempoHint': false});
      matchDarts(c, [timed('T20', 0), timed('S20', 3.2)]);
      await frames(tester);
      expect(find.byKey(const Key('tempo-hint')), findsNothing);
      await c.read(settingsProvider.notifier).update((s) => s.copyWith(tempoHint: true));
      await frames(tester);
      expect(textOf(tester, 'tempo-hint'), 'Aufnahme 3,2 s');
    });

    testWidgets('Match in der Ansicht des Looks: Zeile in der Aufnahme-Karte', (tester) async {
      final c = await startMatch(tester, size: const Size(390, 844), prefs: {'settings.playView': 'look'});
      matchDarts(c, [timed('T20', 0), timed('S20', 2.5)]);
      await frames(tester);
      expect(textOf(tester, 'tempo-hint'), 'Aufnahme 2,5 s');
      expect(tester.takeException(), isNull);
    });

    for (final (name, prefs) in [
      ('Arena', <String, Object>{}),
      ('Look', <String, Object>{'settings.playView': 'look'}),
    ]) {
      testWidgets('X01-Solo ($name): Zeile nach zwei Darts', (tester) async {
        final c = await pumpApp(tester, size: const Size(390, 844), prefs: prefs);
        await c.read(activeGameProvider.notifier).start(X01Solo.definition, {'startScore': 501, 'legs': 1}, seed: 1);
        c.read(routerProvider).go(Routes.play);
        await frames(tester);
        await tester.pump();
        expect(find.byKey(const Key('tempo-hint')), findsNothing);
        final controller = c.read(activeGameProvider.notifier);
        controller.handle(DartThrown(timed('T20', 0)));
        controller.handle(DartThrown(timed('T20', 3.6)));
        await frames(tester);
        expect(textOf(tester, 'tempo-hint'), 'Aufnahme 3,6 s');
        await c.read(activeGameProvider.notifier).end();
      });
    }

    testWidgets('Anderes Trainingsspiel (Bull-Drill): Zeile in der Aufnahme-Karte', (tester) async {
      final c = await pumpApp(tester, size: const Size(390, 844));
      await c.read(activeGameProvider.notifier).start(BullDrill.definition, const {}, seed: 1);
      c.read(routerProvider).go(Routes.play);
      await frames(tester);
      await tester.pump();
      final controller = c.read(activeGameProvider.notifier);
      controller.handle(DartThrown(timed('BULL', 0)));
      controller.handle(DartThrown(timed('S25', 4.0)));
      await frames(tester);
      expect(textOf(tester, 'tempo-hint'), 'Aufnahme 4,0 s');
      expect(tester.takeException(), isNull);
      await controller.end();
    });
  });

  group('Autodarts Live', () {
    late FakeLiveSource live;
    DartSource factory(DartSourceKind kind, String host, int port) =>
        kind == DartSourceKind.autodartsLocal ? live = FakeLiveSource() : testSourceFactory(kind, host, port);

    Future<ProviderContainer> open(WidgetTester tester, {Size size = const Size(1280, 800), Map<String, Object> prefs = const {}}) async {
      final c = await pumpApp(tester, size: size, factory: factory, prefs: {'settings.sourceKind': 'autodartsLocal', ...prefs});
      c.read(routerProvider).go(Routes.games);
      await frames(tester);
      await tester.tap(find.byKey(const Key('open-autodarts-live')));
      await frames(tester);
      return c;
    }

    testWidgets('Aufnahmezeit nach zwei Darts, Ø je Dart erst mit genug Abständen', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('tempo-hint')), findsNothing);
      live.dart('T20', time: base);
      live.dart('S20', time: base.add(const Duration(milliseconds: 3100)));
      live.dart('S5', time: base.add(const Duration(milliseconds: 6400)));
      live.takeout();
      await frames(tester);
      expect(textOf(tester, 'tempo-hint'), 'Aufnahme 6,4 s');
      // Fünf weitere Aufnahmen im gleichen Tempo: zehn Abstände, jetzt auch der Median.
      for (var i = 1; i <= 5; i++) {
        final t = base.add(Duration(seconds: 25 * i));
        live.dart('T20', time: t);
        live.dart('S20', time: t.add(const Duration(milliseconds: 3200)));
        live.dart('S5', time: t.add(const Duration(milliseconds: 6400)));
        live.takeout();
      }
      await frames(tester);
      expect(textOf(tester, 'tempo-hint'), 'Aufnahme 6,4 s · Ø 3,2 s je Dart');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Von Hand ergänzter Dart (ohne echte Zeit): keine Zeile', (tester) async {
      await open(tester);
      live.dart('T20', time: base);
      live.dart('S20', time: base.add(const Duration(milliseconds: 3100)));
      live.takeout();
      await frames(tester);
      expect(find.byKey(const Key('tempo-hint')), findsOneWidget);
      // Dart 3 von Hand ergänzen: die Aufnahme hat danach eine unsichere Zeit.
      final container = ProviderScope.containerOf(tester.element(find.byKey(const Key('tempo-hint'))));
      container.read(autodartsLiveProvider.notifier).addDart(0, Segment.single(1));
      await frames(tester);
      expect(find.byKey(const Key('tempo-hint')), findsNothing);
    });

    testWidgets('Optionen aus: keine Zeile im Live-Bildschirm', (tester) async {
      await open(tester, prefs: {'settings.tempoHint': false});
      live.dart('T20', time: base);
      live.dart('S20', time: base.add(const Duration(milliseconds: 3100)));
      await frames(tester);
      expect(find.byKey(const Key('tempo-hint')), findsNothing);
    });
  });
}
