import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/history_seed.dart';
import '../helpers/pump_app.dart';

typedef _Ids = ({int x01, int match, int cricket, int aborted});

Future<(ProviderContainer, _Ids)> _app(WidgetTester tester, {Size size = const Size(1280, 900)}) async {
  final c = await pumpApp(tester, size: size);
  final player = await c.read(profileRepositoryProvider).resolve(null);
  final ids = await seedHistory(c.read(gameRepositoryProvider), player, DateTime.now());
  await tester.pumpAndSettle();
  return (c, ids);
}

Finder _inDetail(Finder f) => find.descendant(of: find.byKey(const Key('session-detail')), matching: f);

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  final list = find.descendant(of: find.byKey(const Key('session-detail')), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(f, 300, scrollable: list);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Verlauf: Liste → Detail → Löschen', (tester) async {
    final (c, ids) = await _app(tester);
    c.read(routerProvider).go(Routes.stats);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stats-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('history-${ids.x01}')), findsOneWidget);
    expect(find.byKey(Key('history-${ids.match}')), findsOneWidget);

    // Filter: nur Matches, dann nur Training.
    await tester.tap(find.byKey(const Key('history-filter-matches')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('history-${ids.match}')), findsOneWidget);
    expect(find.byKey(Key('history-${ids.x01}')), findsNothing);
    await tester.tap(find.byKey(const Key('history-filter-training')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('history-${ids.match}')), findsNothing);
    expect(find.byKey(Key('history-${ids.x01}')), findsOneWidget);

    await tester.tap(find.byKey(Key('history-${ids.x01}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-detail')), findsOneWidget);
    expect(find.text('X01-Solo'), findsWidgets);
    expect(find.byKey(const Key('session-status')), findsOneWidget);
    await _scrollTo(tester, find.byKey(const Key('session-finish-attempts')));
    expect(_inDetail(find.textContaining('Darts aufs Finish')), findsOneWidget);

    // Löschen mit Rückfrage; Abbrechen ändert nichts.
    await tester.tap(find.byKey(const Key('session-delete-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-delete-dialog')), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-detail')), findsOneWidget);

    await tester.tap(find.byKey(const Key('session-delete-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Session gelöscht'), findsOneWidget);
    expect(find.byKey(Key('history-${ids.x01}')), findsNothing);
    expect(find.byKey(Key('history-${ids.cricket}')), findsOneWidget);

    final db = c.read(appDatabaseProvider);
    final row = await (db.select(db.sessions)..where((s) => s.id.equals(ids.x01))).getSingle();
    expect(row.deletedAt, isNotNull);
    expect(await (db.select(db.throws)..where((t) => t.sessionId.equals(ids.x01))).get(), isEmpty);
  });

  testWidgets('Match im Detail: Ergebnis beider Spieler und jedes Leg', (tester) async {
    final (c, ids) = await _app(tester, size: const Size(390, 844));
    c.read(routerProvider).go(Routes.session(ids.match));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-match-result')), findsOneWidget);
    expect(find.byKey(const Key('session-match-score')), findsOneWidget);
    expect((tester.widget<Text>(find.byKey(const Key('session-match-score')))).data, '2 : 1');
    expect(_inDetail(find.text('Robo')), findsWidgets);
    expect(find.text('Sieg'), findsOneWidget);
    for (final leg in [1, 2, 3]) {
      await _scrollTo(tester, find.byKey(Key('session-leg-info-$leg')));
      expect(find.byKey(Key('session-leg-info-$leg')), findsOneWidget);
    }
    final infos = [
      for (final leg in [1, 2, 3])
        if (find.byKey(Key('session-leg-info-$leg')).evaluate().isNotEmpty)
          tester.widget<Text>(find.byKey(Key('session-leg-info-$leg'))).data!,
    ];
    expect(infos.where((t) => t.startsWith('Robo')), isNotEmpty, reason: 'ein Leg ging an den Bot');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Start: Zuletzt gespielt öffnet die Session', (tester) async {
    final (_, ids) = await _app(tester);
    final tile = find.byKey(Key('home-recent-${ids.match}'));
    await tester.scrollUntilVisible(tile, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-match-result')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-list')), findsOneWidget);
  });
}
