import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/elo_seed.dart';
import '../helpers/lite_app.dart';

/// Der Elo-Reiter ist in Lite einfach da (dieselbe Statistik) und hat keine
/// schreibenden Knöpfe.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  testWidgets('Lite zeigt den Elo-Reiter mit Bens Matches, ohne schreibende Knöpfe', (tester) async {
    final (:c, :cloud, :ben) = await pumpLiteWithBen(tester, prepare: (ben) async {
      final GameRepository games = ben.device.games;
      await seedEloHistory(games, await ben.device.me(), DateTime.now());
    });

    final tab = find.byKey(const Key('stats-tab-elo'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stats-list-elo')), findsOneWidget);
    expect(find.byKey(const Key('elo-hero')), findsOneWidget);
    expect(find.byKey(const Key('elo-empty')), findsNothing);
    final list = find.descendant(of: find.byKey(const Key('stats-list-elo')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const Key('elo-opponents')), 300, scrollable: list);
    await tester.scrollUntilVisible(find.byKey(const Key('elo-explain')), 300, scrollable: list);

    // Nur lesen: keine Schaltflächen zum Anlegen, Ändern, Löschen oder Importieren.
    final inTab = find.descendant(of: find.byKey(const Key('stats-list-elo')), matching: find.byWidgetPredicate((w) =>
        w is FilledButton || w is ElevatedButton || w is OutlinedButton || w is FloatingActionButton || w is IconButton));
    expect(inTab, findsNothing);
    for (final icon in [Icons.delete_outline_rounded, Icons.add_rounded, Icons.edit_rounded, Icons.upload_rounded, Icons.download_rounded]) {
      expect(find.byIcon(icon), findsNothing, reason: '$icon');
    }
    // Die Erklärung (nur lesen) geht auch in Lite.
    await tester.tap(find.byKey(const Key('elo-explain')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('elo-explain-sheet')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await shutdownApp(tester, c);
  });
}
