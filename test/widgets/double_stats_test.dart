import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Bob's 27 mit zwei Aufnahmen (D1, D2); mit [positions] wie im Simulator.
Future<void> bobs(ProviderContainer c, List<List<String>> visits, {bool positions = true}) async {
  final repo = c.read(gameRepositoryProvider);
  final player = await c.read(profileRepositoryProvider).resolve(null);
  final sid = await repo.startSession(playerId: player, gameId: 'bobs_27', config: const {}, seed: 1);
  var seq = 0;
  for (final (v, visit) in visits.indexed) {
    for (final name in visit) {
      final seg = Segment.tryParse(name)!;
      final dart = DartThrow(
        segment: seg,
        timestamp: DateTime.now(),
        source: positions ? DartSourceKind.simulator : DartSourceKind.manual,
        position: !positions ? null : (seg.isMiss ? BoardGeometry.polar(1.08, BoardGeometry.angleOf(v + 1)) : BoardGeometry.centerOf(seg)),
      );
      await repo.addThrow(sessionId: sid, playerId: player, gameId: 'bobs_27', seq: seq++, visitIndex: v, counted: true, dart: dart);
    }
  }
  await repo.endSession(sid, result: const GameResult(metrics: {'score': 27}, summary: []), finished: false);
}

void main() {
  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets('Doppel-Reiter: Fokus, Daneben-Richtung, Tipp (${size.width.toInt()} px)', (tester) async {
      final c = await pumpApp(tester, size: size);
      // D1: 7 Darts, 3 Treffer, 2 außen, 2 innen. D2: 6 Darts, 1 Treffer, 3 innen, 1 seitlich, 1 außen.
      await bobs(c, [
        ['D1', 'MISS', 'S1'],
        ['S2', 'S2', 'D2'],
      ]);
      await bobs(c, [
        ['D1', 'D1', 'MISS'],
        ['D3', 'MISS', 'S2'],
      ]);
      await bobs(c, [
        ['S1'],
      ], positions: false);
      await tester.tap(find.text('Statistik').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('stats-tab-doubles')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stats-tab-doubles')));
      await tester.pumpAndSettle();
      final list = find.descendant(of: find.byKey(const Key('stats-list-doubles')), matching: find.byType(Scrollable)).first;

      // Standard: das meistgeworfene Doppel (D1).
      await tester.scrollUntilVisible(find.byKey(const Key('double-summary')), 200, scrollable: list);
      expect(find.text('D1: 43\u00a0% Treffer, daneben meist außen (29\u00a0%)'), findsOneWidget);
      expect(find.byKey(const Key('double-scatter')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('double-scatter-hint')), 200, scrollable: list);
      expect(find.text('Nur Würfe mit Position (Simulator, Autodarts): 6 von 7 Darts'), findsOneWidget);

      // D2 wählen.
      final chip = find.byKey(const Key('double-chip-2'));
      await tester.scrollUntilVisible(chip, -100, scrollable: list);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('double-summary')), 200, scrollable: list);
      expect(find.text('D2: 17\u00a0% Treffer, daneben meist innen (50\u00a0%)'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('double-miss-side')), matching: find.textContaining('17\u00a0%')), findsOneWidget);
      // Verlauf braucht Daten aus zwei Zeiträumen.
      await tester.scrollUntilVisible(find.byKey(const Key('double-trend')), 200, scrollable: list);
      expect(find.textContaining('Verlauf ab 5 Versuchen'), findsOneWidget);

      // Checkout gegen Training und Tipp.
      await tester.scrollUntilVisible(find.byKey(const Key('double-rate-training')), 200, scrollable: list);
      expect(find.descendant(of: find.byKey(const Key('double-rate-training')), matching: find.text('31\u00a0%')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('double-rate-checkout')), matching: find.text('–')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('double-tip')), 200, scrollable: list);
      expect(find.text('Dein bestes Doppel ist D1 (43\u00a0%). Stell dich beim Stellen lieber darauf.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Doppel-Reiter ohne Positionen zeigt Hinweis statt Punkten', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    await bobs(c, [
      ['D1', 'S1', 'S1'],
    ], positions: false);
    await tester.tap(find.text('Statistik').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('stats-tab-doubles')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stats-tab-doubles')));
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byKey(const Key('stats-list-doubles')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const Key('double-scatter-hint')), 200, scrollable: list);
    expect(find.textContaining('keine Würfe mit Position'), findsOneWidget);
    expect(find.text('Nur Würfe mit Position (Simulator, Autodarts): 0 von 3 Darts'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('double-tip')), 200, scrollable: list);
    expect(find.textContaining('Ab 5 Versuchen auf mindestens zwei Doppel'), findsOneWidget);
  });
}
