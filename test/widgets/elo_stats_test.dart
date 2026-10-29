import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/stats/data/stats_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/elo_seed.dart';
import '../helpers/pump_app.dart';

// Alle Daten sind synthetisch (Ben, Anna, Bots, erfundene Online-Namen).

Future<void> openEloTab(WidgetTester tester) async {
  await tester.tap(find.text('Statistik').first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('stats-tab-elo')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('stats-tab-elo')));
  await tester.pumpAndSettle();
}

Finder get eloList => find.descendant(of: find.byKey(const Key('stats-list-elo')), matching: find.byType(Scrollable)).first;

Future<void> reveal(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(find.byKey(key), 300, scrollable: eloList);
  await tester.pumpAndSettle();
}

Future<List<int>> seed(ProviderContainer c) async {
  final repo = c.read(gameRepositoryProvider);
  final me = await c.read(profileRepositoryProvider).resolve(null);
  return seedEloHistory(repo, me, DateTime.now());
}

Text valueOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key)));

void main() {
  testWidgets('Reiter steht nach „Online“; ohne Matches: Leerzustand, Kennzahlen „–“, keine Aktionen', (tester) async {
    await pumpApp(tester, size: const Size(390, 844));
    await openEloTab(tester);

    final tabs = [
      for (final t in tester.widgetList<Tab>(find.descendant(of: find.byKey(const Key('stats-tabs')), matching: find.byType(Tab)))) t.text,
    ];
    expect(tabs.indexOf('Elo'), tabs.indexOf('Online') + 1);

    expect(find.byKey(const Key('elo-empty')), findsOneWidget);
    expect(find.textContaining('Spiele ein paar Matches'), findsOneWidget);
    expect(valueOf(tester, 'elo-value').data, '–');
    expect(valueOf(tester, 'elo-peak').data, '–');
    expect(find.byKey(const Key('elo-chart')), findsNothing);
    expect(find.byKey(const Key('elo-opponents')), findsNothing);
    expect(find.text('0 von 3 gewerteten Matches'), findsOneWidget);
    // Der Spielfilter gilt hier nicht.
    expect(find.byKey(const Key('stats-game')), findsNothing);
    // Die Erklärung ist da.
    await reveal(tester, const Key('elo-explain'));
    expect(find.byKey(const Key('elo-explain')), findsOneWidget);
  });

  testWidgets('weniger als drei gewertete Matches: Leerzustand mit Fortschritt', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    final repo = c.read(gameRepositoryProvider);
    final me = await c.read(profileRepositoryProvider).resolve(null);
    await seedEloMatch(repo, me, DateTime.now().subtract(const Duration(days: 3)), EloKind.bot, opponent: 'CPU 40', botAverage: 40);
    await seedEloMatch(repo, me, DateTime.now().subtract(const Duration(days: 2)), EloKind.local, opponent: 'Anna', won: false);
    // Ein abgebrochenes Match und Training zählen nicht.
    await seedEloMatch(repo, me, DateTime.now().subtract(const Duration(days: 1)), EloKind.bot, finished: false);
    await openEloTab(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('elo-empty')), findsOneWidget);
    expect(find.text('2 von 3 gewerteten Matches'), findsOneWidget);
    expect(valueOf(tester, 'elo-value').data, '–');
    expect(find.text('1–1'), findsOneWidget);
    expect(find.byKey(const Key('elo-chart')), findsNothing);
  });

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets('mit Matches: Kennzahlen, Verlauf, Gegner, Siege und Niederlagen (${size.width.toInt()} px)', (tester) async {
      final c = await pumpApp(tester, size: size);
      await seed(c);
      await openEloTab(tester);
      // Alles Wichtige kommt aus demselben Bericht wie im Rechner.
      final report = c.read(houseEloProvider)!;
      expect(report.matches, 25);

      expect(valueOf(tester, 'elo-value').data, '${report.current.round()}');
      expect(valueOf(tester, 'elo-peak').data, '${report.peak!.round()}');
      expect(find.byKey(const Key('elo-trend')), findsOneWidget);
      expect(find.text('${report.wins}–${report.losses}'), findsOneWidget);
      expect(find.text('25'), findsWidgets);

      await reveal(tester, const Key('elo-chart'));
      await reveal(tester, const Key('elo-opponents'));
      expect(find.byKey(const Key('elo-opponent-online:lukas77')), findsOneWidget);
      expect(find.byKey(const Key('elo-opponent-local:anna')), findsOneWidget);
      await reveal(tester, const Key('elo-best'));
      expect(find.byKey(const Key('elo-best-0')), findsOneWidget);
      expect(find.byKey(const Key('elo-best-2')), findsOneWidget);
      expect(find.byKey(const Key('elo-best-3')), findsNothing, reason: 'je drei Einträge');
      await reveal(tester, const Key('elo-worst'));
      expect(find.byKey(const Key('elo-worst-0')), findsOneWidget);
      expect(find.byKey(const Key('elo-worst-3')), findsNothing);
      await reveal(tester, const Key('elo-explain'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Gegner-Tabelle: Filter Online, Bots, Mitspieler; Zeitraum', (tester) async {
    final c = await pumpApp(tester, size: const Size(1280, 900));
    await seed(c);
    await openEloTab(tester);
    await reveal(tester, const Key('elo-opponents'));

    Finder row(String id) => find.byKey(Key('elo-opponent-$id'));
    // Alle: Bots, Online und Mitspieler (sieben Gegner in der Demo).
    for (final id in ['bot:cpu 40@40', 'bot:cpu 55@55', 'bot:cpu 70@70', 'online:lukas77', 'online:dartfee', 'online:pfeilwurf', 'local:anna']) {
      expect(row(id), findsOneWidget, reason: id);
    }
    // Sortiert nach Matches: Anna (5) vor CPU 70 (3).
    expect(tester.getTopLeft(row('local:anna')).dy, lessThan(tester.getTopLeft(row('bot:cpu 70@70')).dy));

    await tester.tap(find.byKey(const Key('elo-filter-online')));
    await tester.pumpAndSettle();
    expect(row('online:lukas77'), findsOneWidget);
    expect(row('bot:cpu 55@55'), findsNothing);
    expect(row('local:anna'), findsNothing);

    await tester.tap(find.byKey(const Key('elo-filter-bots')));
    await tester.pumpAndSettle();
    expect(row('bot:cpu 55@55'), findsOneWidget);
    expect(row('online:lukas77'), findsNothing);
    expect(find.text('Bot · Ø 55'), findsWidgets);

    await tester.tap(find.byKey(const Key('elo-filter-local')));
    await tester.pumpAndSettle();
    expect(row('local:anna'), findsOneWidget);
    expect(row('bot:cpu 55@55'), findsNothing);

    // Zeitraum 7 Tage: unter den Mitspielern bleibt Anna (vor 5 Tagen) mit nur diesem Match.
    await tester.tap(find.byKey(const Key('period-week')));
    await tester.pumpAndSettle();
    await reveal(tester, const Key('elo-opponents'));
    expect(row('local:anna'), findsOneWidget);
    expect(find.descendant(of: row('local:anna'), matching: find.text('1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('elo-filter-all')));
    await tester.pumpAndSettle();
    expect(row('bot:cpu 55@55'), findsNothing, reason: 'nicht im Zeitraum');
    expect(row('bot:cpu 40@40'), findsOneWidget, reason: 'vor zwei Tagen');
  });

  testWidgets('„Wie wird das berechnet?“ öffnet die Erklärung', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    await seed(c);
    await openEloTab(tester);
    await reveal(tester, const Key('elo-explain'));
    await tester.tap(find.byKey(const Key('elo-explain')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('elo-explain-sheet')), findsOneWidget);
    expect(find.textContaining('Haus-Elo'), findsWidgets);
    expect(find.textContaining('12 Punkte je Average-Punkt'), findsOneWidget);
    await tester.ensureVisible(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('elo-explain-sheet')), findsNothing);
  });

  testWidgets('Zeitraum begrenzt den Verlauf, Kennzahlen bleiben gesamt', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    await seed(c);
    await openEloTab(tester);
    final before = valueOf(tester, 'elo-value').data;
    await tester.tap(find.byKey(const Key('period-week')));
    await tester.pumpAndSettle();
    expect(valueOf(tester, 'elo-value').data, before);
    await reveal(tester, const Key('elo-chart'));
    expect(find.byKey(const Key('elo-chart')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
