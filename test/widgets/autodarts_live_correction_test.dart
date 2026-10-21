import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/autodarts_live/domain/live_x01.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_controller.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_live_source.dart';
import '../helpers/pump_app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeLiveSource live;

  DartSource factory(DartSourceKind kind, String host, int port) =>
      kind == DartSourceKind.autodartsLocal ? live = FakeLiveSource() : testSourceFactory(kind, host, port);

  Future<ProviderContainer> open(WidgetTester tester, {required Size size}) async {
    final c = await pumpApp(tester, size: size, factory: factory, prefs: {'settings.sourceKind': 'autodartsLocal', 'settings.playView': 'look'});
    c.read(routerProvider).go(Routes.games);
    await settle(tester);
    await tester.tap(find.byKey(const Key('open-autodarts-live')));
    await settle(tester);
    return c;
  }

  /// Scrollt die Liste des Bildschirms, bis das Widget gebaut ist.
  Future<void> reveal(WidgetTester tester, String key) async {
    final f = find.byKey(Key(key));
    if (f.evaluate().isNotEmpty) return;
    for (final list in ['live-left', 'live-list']) {
      final l = find.byKey(Key(list));
      if (l.evaluate().isEmpty) continue;
      await tester.scrollUntilVisible(f, 200, scrollable: find.descendant(of: l, matching: find.byType(Scrollable)).first);
      await settle(tester);
      return;
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await reveal(tester, key);
    final f = find.byKey(Key(key));
    await tester.ensureVisible(f);
    await settle(tester);
    await tester.tap(f);
    await settle(tester);
  }

  /// Feld im geöffneten Blatt wählen (Multiplikator über `fix-double`/`fix-triple`).
  Future<void> pick(WidgetTester tester, String key, {String? multiplier}) async {
    if (multiplier != null) await tapKey(tester, multiplier);
    await tapKey(tester, key);
  }

  Future<List<String>> storedSegments(ProviderContainer c) async {
    await c.read(autodartsLiveProvider.notifier).pendingWrites;
    final db = c.read(appDatabaseProvider);
    final s = await db.select(db.sessions).get();
    final rows = await GameRepository(db).throwsOf(s.last.id);
    return [for (final r in rows) '${r.segment}${r.source == 'manual' ? '*' : ''}'];
  }

  Finder chipText(int slot, String text) =>
      find.descendant(of: find.byKey(Key('live-slot-$slot')), matching: find.text(text));

  testWidgets('Handy: Dart der laufenden Aufnahme korrigieren, markiert, bleibt bei Board-Korrektur', (tester) async {
    final c = await open(tester, size: const Size(390, 844));
    live.visit(['T20', 'T20', 'T20']);
    live.dart('S5');
    live.dart('S1');
    await settle(tester);
    expect(find.byKey(const Key('live-fix-hint')), findsOneWidget);
    expect(find.byTooltip('Von Hand korrigiert'), findsNothing);

    await tester.tap(find.byKey(const Key('live-slot-0')));
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('live-fix-title'))).data, 'Aufnahme 2 · Dart 1');
    expect(tester.widget<Text>(find.byKey(const Key('live-fix-subtitle'))).data, 'Vom Board erkannt: S5');
    await pick(tester, 'fix-19', multiplier: 'fix-triple');
    // Sheet zu, Dart korrigiert und markiert.
    expect(find.byKey(const Key('live-fix-title')), findsNothing);
    expect(chipText(0, 'T19'), findsOneWidget);
    expect(find.byTooltip('Von Hand korrigiert'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('live-visit-score'))).data, '58');
    expect(await storedSegments(c), ['T20', 'T20', 'T20', 'T19*', 'S1']);

    // Der Dart bleibt, auch wenn das Board seinen Stand meldet.
    live.emit(DartCorrected(0, DartThrow(segment: Segment.tryParse('D1')!, timestamp: DateTime.now(), source: DartSourceKind.autodartsLocal)));
    await settle(tester);
    expect(chipText(0, 'T19'), findsOneWidget);

    // Erneut öffnen: „Von Hand gesetzt“.
    await tester.tap(find.byKey(const Key('live-slot-0')));
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('live-fix-subtitle'))).data, 'Von Hand gesetzt: T19');
    await tapKey(tester, 'fix-miss');
    expect(chipText(0, 'MISS'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('live-visit-score'))).data, '1');
  });

  testWidgets('Handy: Dart entfernen und freien Platz zum Ergänzen antippen', (tester) async {
    final c = await open(tester, size: const Size(390, 844));
    live.dart('T20');
    live.dart('S5');
    await settle(tester);

    await tester.tap(find.byKey(const Key('live-slot-0')));
    await settle(tester);
    await tapKey(tester, 'live-fix-remove-dart');
    expect(find.byKey(const Key('live-fix-title')), findsNothing);
    expect(chipText(0, 'S5'), findsOneWidget);
    expect(await storedSegments(c), ['S5']);

    // Der erste freie Platz ist ein „+“; die übrigen sind nicht antippbar.
    await tester.tap(find.byKey(const Key('live-slot-1')));
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('live-fix-title'))).data, 'Dart ergänzen · Aufnahme 1');
    expect(find.byKey(const Key('live-fix-remove-dart')), findsNothing, reason: 'Ergänzen hat nur die Feldauswahl');
    await pick(tester, 'fix-bull');
    expect(chipText(1, 'BULL'), findsOneWidget);
    expect(await storedSegments(c), ['S5', 'BULL*']);
    expect(find.byTooltip('Von Hand korrigiert'), findsOneWidget);

    live.dart('S7');
    await settle(tester);
    expect(await storedSegments(c), ['S5', 'BULL*', 'S7']);
  });

  testWidgets('Desktop: letzte Aufnahmen korrigieren und Darts ergänzen', (tester) async {
    final c = await open(tester, size: const Size(1280, 800));
    live.visit(['T20', 'T20', 'T20']);
    live.visit(['S1', 'S5']);
    live.visit(['D4', 'D5', 'D6']);
    await settle(tester);
    // Neueste zuerst: #3, #2, #1.
    await reveal(tester, 'live-recent-2');
    Finder number(int row, String text) =>
        find.descendant(of: find.byKey(Key('live-recent-$row')), matching: find.text(text));
    expect(number(0, '#3'), findsOneWidget);
    expect(number(2, '#1'), findsOneWidget);
    expect(find.byKey(const Key('live-recent-0-add')), findsNothing, reason: 'drei Darts');
    expect(find.byKey(const Key('live-recent-1-add')), findsOneWidget);

    // Abgeschlossene Aufnahme #1, zweiter Dart.
    await tapKey(tester, 'live-recent-2-dart-1');
    expect(tester.widget<Text>(find.byKey(const Key('live-fix-title'))).data, 'Aufnahme 1 · Dart 2');
    await pick(tester, 'fix-20', multiplier: 'fix-double');
    expect(find.descendant(of: find.byKey(const Key('live-recent-2-dart-1')), matching: find.text('D20')), findsOneWidget);
    expect(find.byTooltip('Von Hand korrigiert'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('live-darts'))).data, '8');
    expect(await storedSegments(c), ['T20', 'D20*', 'T20', 'S1', 'S5', 'D4', 'D5', 'D6']);

    // Vergessenen Dart in #2 ergänzen.
    await tapKey(tester, 'live-recent-1-add');
    expect(tester.widget<Text>(find.byKey(const Key('live-fix-title'))).data, 'Dart ergänzen · Aufnahme 2');
    await pick(tester, 'fix-20');
    expect(tester.widget<Text>(find.byKey(const Key('live-darts'))).data, '9');
    expect(find.byKey(const Key('live-recent-1-add')), findsNothing);
    expect(await storedSegments(c), ['T20', 'D20*', 'T20', 'S1', 'S5', 'S20*', 'D4', 'D5', 'D6']);
  });

  testWidgets('Desktop: ganze Aufnahme löschen mit Rückfrage', (tester) async {
    final c = await open(tester, size: const Size(1280, 800));
    live.visit(['T20', 'T20', 'T20']);
    live.visit(['S1', 'S5']);
    live.visit(['D4', 'D5', 'D6']);
    await settle(tester);

    await tapKey(tester, 'live-recent-1-dart-0');
    await tapKey(tester, 'live-fix-remove-visit');
    expect(find.byKey(const Key('live-fix-remove-visit-dialog')), findsOneWidget);
    expect(find.text('Aufnahme 2 löschen?'), findsOneWidget);
    expect(find.textContaining('Die 2 Darts dieser Aufnahme'), findsOneWidget);
    // Abbrechen lässt alles, wie es ist.
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(await storedSegments(c), ['T20', 'T20', 'T20', 'S1', 'S5', 'D4', 'D5', 'D6']);

    await tapKey(tester, 'live-recent-1-dart-0');
    await tapKey(tester, 'live-fix-remove-visit');
    await tester.tap(find.byKey(const Key('live-fix-remove-visit-confirm')));
    await settle(tester);
    expect(find.text('Aufnahme 2 gelöscht'), findsOneWidget);
    expect(await storedSegments(c), ['T20', 'T20', 'T20', 'D4', 'D5', 'D6']);
    expect(tester.widget<Text>(find.byKey(const Key('live-darts'))).data, '6');
    expect(find.byKey(const Key('live-recent-2')), findsNothing, reason: 'nur noch zwei Aufnahmen');
    expect(find.descendant(of: find.byKey(const Key('live-recent-1')), matching: find.text('#1')), findsOneWidget);
  });

  testWidgets('X01 mitzählen: Rest und Leg-Stand folgen der Korrektur', (tester) async {
    final c = await open(tester, size: const Size(390, 844));
    c.read(autodartsLiveProvider.notifier).setX01(const LiveX01Config(startScore: 301));
    await settle(tester);
    live.visit(['T20', 'T20', 'T20']);
    live.visit(['T20', 'S11', 'BULL']); // Checkout
    await settle(tester);
    expect(c.read(autodartsLiveProvider).x01!.legsWon, 1);

    // Die laufende Aufnahme ist leer: das nächste Leg beginnt bei 301.
    expect(tester.widget<Text>(find.byKey(const Key('live-visit-score'))).data, '301');
    await tester.tap(find.byKey(const Key('live-slot-0')));
    await settle(tester);
    await pick(tester, 'fix-1');
    expect(tester.widget<Text>(find.byKey(const Key('live-visit-score'))).data, '300');

    live.dart('S20');
    await settle(tester);
    await tester.tap(find.byKey(const Key('live-slot-1')));
    await settle(tester);
    await tapKey(tester, 'live-fix-remove-dart');
    expect(c.read(autodartsLiveProvider).x01!.remaining, 300);
    expect(await storedSegments(c), ['T20', 'T20', 'T20', 'T20', 'S11', 'BULL', 'S1*']);
  });
}
