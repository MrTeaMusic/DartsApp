import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/backup/data/backup_files.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/profiles/presentation/active_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/darts.dart';
import '../helpers/pump_app.dart';

class FakeFiles implements BackupFiles {
  final saved = <String, String>{};
  String? toOpen;

  @override
  Future<String?> save(String fileName, String content, {required String mimeType, required String extension}) async {
    saved[fileName] = content;
    return '/tmp/$fileName';
  }

  @override
  Future<String?> openJson() async => toOpen;

  @override
  Future<String?> openText() async => toOpen;
}

/// Legt eine Highscore-Session mit drei Würfen von heute an.
Future<void> seed(ProviderContainer c, {int? playerId}) async {
  final repo = c.read(gameRepositoryProvider);
  final player = playerId ?? await c.read(profileRepositoryProvider).resolve(null);
  final sid = await repo.startSession(playerId: player, gameId: 'highscore_hunt', config: const {}, seed: 1);
  for (final (i, n) in ['T20', 'T20', 'S20'].indexed) {
    await repo.addThrow(sessionId: sid, playerId: player, gameId: 'highscore_hunt', seq: i, visitIndex: 0, counted: true, dart: d(n));
  }
  await repo.endSession(sid, result: const GameResult(metrics: {'points': 140, 'average': 140.0}, summary: []), finished: true);
}

/// Legt eine Bob's-27-Session an: D1 zweimal getroffen, D2 verfehlt.
Future<void> seedBobs(ProviderContainer c) async {
  final repo = c.read(gameRepositoryProvider);
  final player = await c.read(profileRepositoryProvider).resolve(null);
  final sid = await repo.startSession(playerId: player, gameId: 'bobs_27', config: const {}, seed: 1);
  for (final (i, n) in ['D1', 'S1', 'D1', 'S2', 'S2', 'MISS'].indexed) {
    await repo.addThrow(
        sessionId: sid, playerId: player, gameId: 'bobs_27', seq: i, visitIndex: i ~/ 3, counted: true, dart: d(n));
  }
  await repo.endSession(sid,
      result: const GameResult(metrics: {'score': 27, 'hits': 2, 'darts': 6}, summary: []), finished: false);
}

Future<void> openStats(WidgetTester tester) async {
  await tester.tap(find.text('Statistik').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Statistik ohne Daten zeigt Hinweis, Serie und Ziele', (tester) async {
    await pumpApp(tester);
    await openStats(tester);
    expect(find.text('Noch keine Daten'), findsOneWidget);
    expect(find.byKey(const Key('streak-card')), findsOneWidget);
    expect(find.text('0 Tage'), findsOneWidget);
    expect(find.byKey(const Key('goals-card')), findsOneWidget);
  });

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets('Statistik mit Daten: alle Reiter (${size.width.toInt()} px)', (tester) async {
      final c = await pumpApp(tester, size: size);
      await seed(c);
      await seedBobs(c);
      await openStats(tester);

      // Überblick
      expect(find.byKey(const Key('stat-average')), findsOneWidget);
      expect(find.text('140,0'), findsWidgets);
      expect(find.text('1 Tag'), findsOneWidget);
      expect(find.text('Heute trainiert · Rekord: 1'), findsOneWidget);
      final overview = find.byKey(const Key('stats-list-overview'));
      await tester.dragUntilVisible(find.byKey(const Key('stats-activity')), overview, const Offset(0, -300));
      expect(find.byKey(const Key('stats-activity')), findsOneWidget);

      // Scoring
      await tester.tap(find.byKey(const Key('stats-tab-scoring')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stat-scoring-average')), findsOneWidget);
      expect(find.byKey(const Key('stat-180s')), findsOneWidget);
      final scoring = find.byKey(const Key('stats-list-scoring'));
      await tester.dragUntilVisible(find.byKey(const Key('stats-heatmap')), scoring, const Offset(0, -300));
      expect(find.byKey(const Key('stats-heatmap')), findsOneWidget);

      // Doppel & Finish: Bob's 27 mit D1 (2 von 3) und D2 (0 von 3).
      await tester.tap(find.byKey(const Key('stats-tab-doubles')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stat-double-rate')), findsOneWidget);
      expect(find.text('33,3 %'), findsWidgets);
      final doubles = find.byKey(const Key('stats-list-doubles'));
      await tester.dragUntilVisible(find.byKey(const Key('double-1')), doubles, const Offset(0, -300));
      expect(find.descendant(of: find.byKey(const Key('double-1')), matching: find.text('2/3')), findsOneWidget);

      // Spiele
      await tester.tap(find.byKey(const Key('stats-tab-games')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stats-game-trend')), findsOneWidget);

      // Rekorde
      await tester.tap(find.byKey(const Key('stats-tab-records')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('record-highestVisit')), findsOneWidget);

      await tester.tap(find.byKey(const Key('period-week')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Spielfilter und Kennzahl im Verlauf wählen', (tester) async {
    final c = await pumpApp(tester);
    await seed(c);
    await seedBobs(c);
    await openStats(tester);
    expect(find.byKey(const Key('stat-average')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stats-game')));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Bob's 27").last);
    await tester.pumpAndSettle();
    // Bob's 27 hat keinen Average, aber eine Double-Quote.
    expect(find.byKey(const Key('stat-average')), findsNothing);
    expect(find.text('33,3 %'), findsWidgets);

    await tester.tap(find.byKey(const Key('stats-tab-games')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('metric-score')), findsOneWidget);
    await tester.tap(find.byKey(const Key('metric-hits')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('metric-hits'))).selected, isTrue);

    await tester.tap(find.byKey(const Key('stats-game')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alle Spiele').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stats-tab-overview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stat-average')), findsOneWidget);
  });

  testWidgets('Ziel anlegen und Fortschritt sehen', (tester) async {
    final c = await pumpApp(tester);
    await seed(c);
    await openStats(tester);
    await tester.tap(find.byKey(const Key('goal-add')));
    await tester.pumpAndSettle();
    expect(find.text('Sessions pro Woche'), findsWidgets);
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goal-weeklySessions')), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
    final db = c.read(appDatabaseProvider);
    final goals = await db.select(db.goals).get();
    expect(goals.single.target, 5);
  });

  testWidgets('Profil anlegen wechselt das aktive Profil, Statistik ist pro Profil', (tester) async {
    final c = await pumpApp(tester);
    await seed(c);
    await tester.tap(find.text('Optionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-name')), 'Gast');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    expect(c.read(activePlayerProvider)?.name, 'Gast');
    expect(find.text('Gast'), findsOneWidget);

    await openStats(tester);
    expect(find.text('Noch keine Daten'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Gast'), findsOneWidget);

    // Zurück zu "Ich": die Session ist wieder da.
    final me = (await c.read(profileRepositoryProvider).players()).firstWhere((p) => p.name == 'Ich');
    await c.read(activePlayerIdProvider.notifier).select(me.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stat-average')), findsOneWidget);
  });

  testWidgets('Profil löschen fragt nach', (tester) async {
    final c = await pumpApp(tester);
    final guest = await c.read(profileRepositoryProvider).create('Gast');
    await seed(c, playerId: guest);
    await tester.tap(find.text('Optionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('profile-menu-$guest')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-delete')));
    await tester.pumpAndSettle();
    expect(find.text('„Gast“ löschen?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-delete-confirm')));
    await tester.pumpAndSettle();
    expect((await c.read(profileRepositoryProvider).players()).map((p) => p.name), ['Ich']);
    expect(await c.read(appDatabaseProvider).select(c.read(appDatabaseProvider).sessions).get(), isEmpty);
  });

  testWidgets('Export und Import über die Optionen', (tester) async {
    final files = FakeFiles();
    final c = await pumpApp(tester, overrides: [backupFilesProvider.overrideWithValue(files)]);
    await seed(c);
    await tester.tap(find.text('Optionen').first);
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).last;

    await tester.scrollUntilVisible(find.byKey(const Key('export-json')), 300, scrollable: scrollable);
    await tester.ensureVisible(find.byKey(const Key('export-json')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-json')));
    await tester.pumpAndSettle();
    final json = files.saved.entries.single;
    expect(json.key, startsWith('dartlab-backup-'));
    expect(jsonDecode(json.value)['format'], 'dartlab-backup');
    expect(find.textContaining('Gespeichert: /tmp/dartlab-backup-'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('export-throws')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-throws')));
    await tester.pumpAndSettle();
    expect(files.saved.keys.where((k) => k.startsWith('dartlab-wuerfe-')).length, 1);

    files.toOpen = json.value;
    await tester.scrollUntilVisible(find.byKey(const Key('import-json')), 300, scrollable: scrollable);
    await tester.ensureVisible(find.byKey(const Key('import-json')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-json')));
    await tester.pumpAndSettle();
    expect(find.textContaining('(1 schon vorhanden)'), findsOneWidget);

    files.toOpen = 'kaputt';
    await tester.tap(find.byKey(const Key('import-json')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Datei nicht lesbar'), findsOneWidget);
  });
}
