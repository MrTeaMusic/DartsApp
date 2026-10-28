import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/stats/data/stats_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/elo_seed.dart';
import '../helpers/history_seed.dart';
import '../helpers/pump_app.dart';

/// Im Session-Detail eines gewerteten Matches steht „Haus-Elo vorher → nachher“.
void main() {
  testWidgets('gewertetes Match zeigt die Elo-Zeile, Training und abgebrochene Matches nicht', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    final repo = c.read(gameRepositoryProvider);
    final me = await c.read(profileRepositoryProvider).resolve(null);
    final ids = await seedEloHistory(repo, me, DateTime.now());
    final training = await seedTraining(repo, me, 'x01', const {'startScore': 501, 'legs': 1}, DateTime.now().subtract(const Duration(days: 1)), seed: 3);
    final aborted = await seedEloMatch(repo, me, DateTime.now().subtract(const Duration(hours: 5)), EloKind.bot, finished: false);
    await tester.pumpAndSettle();
    // Der Rechner lädt im Hintergrund; dann steht der Bericht bereit.
    for (var i = 0; i < 200 && (c.read(houseEloProvider)?.matches ?? 0) < 25; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    final step = c.read(houseEloProvider)!.stepOf(ids[7])!;

    c.read(routerProvider).go(Routes.session(ids[7]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-match-result')), findsOneWidget);
    final line = find.byKey(const Key('session-match-elo'));
    await tester.scrollUntilVisible(line, 300, scrollable: find.byType(Scrollable).first);
    expect(line, findsOneWidget);
    final after = step.after.round();
    expect(find.textContaining('${step.before.round()} → $after'), findsOneWidget);

    c.read(routerProvider).go(Routes.session(aborted));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-match-elo')), findsNothing);
    c.read(routerProvider).go(Routes.session(training));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-match-elo')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
