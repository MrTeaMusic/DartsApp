import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/history_seed.dart';
import '../helpers/online_seed.dart';
import '../helpers/pump_app.dart';

/// Training (X01-Solo, Checkout, Highscore) und Online-Matches mit
/// nervösem D16 der letzten drei Wochen. Gibt die neueste Live-Session zurück.
Future<int> seedOnline(ProviderContainer c) async {
  final repo = c.read(gameRepositoryProvider);
  final player = await c.read(profileRepositoryProvider).resolve(null);
  final day = DateTime.now();
  DateTime at(int daysAgo, int hour) => DateTime(day.year, day.month, day.day - daysAgo, hour);
  for (var i = 0; i < 5; i++) {
    await seedTraining(repo, player, 'x01', const {'startScore': 501, 'legs': 2}, at(i * 4 + 1, 17), seed: 10 + i, average: 62);
    await seedTraining(repo, player, 'checkout', const {'mode': 'random', 'min': 2, 'max': 40, 'attempts': 15}, at(i * 4 + 2, 17),
        seed: 20 + i, average: 62);
    await seedTraining(repo, player, 'highscore_hunt', const {}, at(i * 4 + 3, 17), seed: 40 + i, average: 62);
  }
  late int last;
  for (var i = 5; i >= 0; i--) {
    last = await seedOnlineMatch(repo, player, at(i * 3, 20),
        seed: 30 + i, average: 54, legs: 4, opponentMin: 9, opponentMax: 15, nervous: const {16: 0.8, 8: 0.6});
  }
  return last;
}

Future<Finder> openOnlineTab(WidgetTester tester) async {
  await tester.tap(find.text('Statistik').first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('stats-tab-online')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('stats-tab-online')));
  await tester.pumpAndSettle();
  return find.descendant(of: find.byKey(const Key('stats-list-online')), matching: find.byType(Scrollable)).first;
}

void main() {
  testWidgets('Ohne Live-Sessions: Hinweis mit Weg zu Autodarts Live, kein Spielfilter', (tester) async {
    await pumpApp(tester, size: const Size(390, 844));
    await openOnlineTab(tester);
    expect(find.byKey(const Key('online-empty')), findsOneWidget);
    expect(find.text('Noch keine Online-Matches'), findsOneWidget);
    expect(find.byKey(const Key('stats-game')), findsNothing);
    await tester.tap(find.byKey(const Key('online-open-live')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stats-list-online')), findsNothing);
  });

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets('Online-Reiter: Kennzahlen, Vergleich, Doppel, Matches mit Legs (${size.width.toInt()} px)', (tester) async {
      final c = await pumpApp(tester, size: size);
      final last = await seedOnline(c);
      final list = await openOnlineTab(tester);

      expect(find.byKey(const Key('online-matches')), findsOneWidget);
      expect(find.byKey(const Key('online-average')), findsOneWidget);
      // Verlauf: andere Kennzahl wählen.
      await tester.scrollUntilVisible(find.byKey(const Key('online-trend-first9')), 300, scrollable: list);
      await tester.ensureVisible(find.byKey(const Key('online-trend-first9')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('online-trend-first9')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('online-compare')), 300, scrollable: list);
      expect(find.byKey(const Key('online-compare-average')), findsOneWidget);
      expect(find.byKey(const Key('online-compare-doubleRate')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('online-doubles')), 300, scrollable: list);
      await tester.scrollUntilVisible(find.byKey(const Key('online-double-16')), 200, scrollable: list);
      expect(find.byKey(const Key('online-double-16')), findsOneWidget);

      // Match aufklappen: Legs, dann alle Aufnahmen in der Detailansicht.
      await tester.scrollUntilVisible(find.byKey(Key('online-match-$last')), 300, scrollable: list);
      await tester.ensureVisible(find.byKey(Key('online-match-$last')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('online-match-$last')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('online-leg-$last-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byKey(Key('online-match-open-$last')), 200, scrollable: list);
      await tester.ensureVisible(find.byKey(Key('online-match-open-$last')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('online-match-open-$last')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session-detail')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Zu wenig Training: Vergleich erklärt, was fehlt', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    final player = await c.read(profileRepositoryProvider).resolve(null);
    await seedOnlineMatch(c.read(gameRepositoryProvider), player, DateTime.now().subtract(const Duration(hours: 3)), legs: 2);
    final list = await openOnlineTab(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('online-compare-empty')), 300, scrollable: list);
    expect(find.text('Noch zu wenig für den Vergleich'), findsOneWidget);
    expect(find.textContaining('(mind. 90 Darts)'), findsWidgets);
  });

  testWidgets('Verlauf: Live-Sessions unter „Matches“', (tester) async {
    final c = await pumpApp(tester);
    final player = await c.read(profileRepositoryProvider).resolve(null);
    final repo = c.read(gameRepositoryProvider);
    final live = await seedOnlineMatch(repo, player, DateTime.now().subtract(const Duration(hours: 2)), legs: 3,
        opponentMin: 9, opponentMax: 14);
    final x01 = await seedTraining(repo, player, 'x01', const {'startScore': 501}, DateTime.now().subtract(const Duration(hours: 5)));
    c.read(routerProvider).go(Routes.history);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('history-online-$live')), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-filter-matches')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('history-$live')), findsOneWidget);
    expect(find.byKey(Key('history-$x01')), findsNothing);
    expect(find.textContaining('Legs '), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-filter-training')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('history-$live')), findsNothing);
    expect(find.byKey(Key('history-$x01')), findsOneWidget);
  });
}
