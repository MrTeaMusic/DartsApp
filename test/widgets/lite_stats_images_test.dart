import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/lite_app.dart';
import '../helpers/scatter_seed.dart';

/// Die Bilder der Statistik (Scheibe mit Wurfpunkten, Heatmap) gibt es in
/// Lite genauso wie in der Hauptapp.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  Future<void> openTab(WidgetTester tester, String key) async {
    final tab = find.byKey(Key('stats-tab-$key'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, String tab, Key target) async {
    final list = find.descendant(of: find.byKey(Key('stats-list-$tab')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(target), 300, scrollable: list);
    await tester.pumpAndSettle();
  }

  testWidgets('Streuung, Doppel und Heatmap zeigen die Scheibe mit den Würfen', (tester) async {
    final (:c, :cloud, :ben) = await pumpLiteWithBen(tester, prepare: (ben) async {
      final GameRepository games = ben.device.games;
      await seedScatter(games, await ben.device.me(), DateTime.now(), scale: 0.5);
    });

    await openTab(tester, 'scoring');
    await reveal(tester, 'scoring', const Key('stats-heatmap'));
    expect(find.byKey(const Key('stats-heatmap')), findsOneWidget);

    await openTab(tester, 'doubles');
    await reveal(tester, 'doubles', const Key('double-scatter'));
    expect(find.byKey(const Key('double-scatter')), findsOneWidget);

    await openTab(tester, 'scatter');
    await reveal(tester, 'scatter', const Key('scatter-board-view'));
    expect(find.byKey(const Key('scatter-board-view')), findsOneWidget);
    await reveal(tester, 'scatter', const Key('scatter-focus-view'));
    expect(find.byKey(const Key('scatter-focus-view')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shutdownApp(tester, c);
  });
}
