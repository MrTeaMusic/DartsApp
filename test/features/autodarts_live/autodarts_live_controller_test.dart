import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/autodarts_live/domain/live_stats.dart';
import 'package:dartlab/features/autodarts_live/domain/live_x01.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_controller.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/data/autodarts_local_source.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_board_manager.dart';
import '../../helpers/fake_live_source.dart';

/// `data` jeder Statusmeldung des echten Mitschnitts.
List<Map<String, Object?>> fixtureStates(String name) => [
      for (final line in File('test/fixtures/autodarts/$name').readAsLinesSync())
        if (line.trim().isNotEmpty)
          ((jsonDecode((jsonDecode(line) as Map)['payload'] as String) as Map)['data'] as Map).cast<String, Object?>(),
    ];

Future<void> until(bool Function() test) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!test()) {
    if (DateTime.now().isAfter(end)) throw StateError('Zeitüberschreitung');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<(ProviderContainer, AppDatabase)> container(DartSourceFactory factory, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'settings.sourceKind': 'autodartsLocal', ...prefs});
  final sp = await SharedPreferences.getInstance();
  final db = AppDatabase(NativeDatabase.memory());
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(sp),
    appDatabaseProvider.overrideWithValue(db),
    dartSourceFactoryProvider.overrideWithValue(factory),
  ]);
  return (c, db);
}

void main() {
  test('echter Mitschnitt über den echten Board-Manager-Client: Aufnahmen, Speichern, kein einziger Befehl', () async {
    final board = await FakeBoardManager.start();
    board
      ..greet = true
      ..state = {'connected': true, 'running': true, 'status': 'Throw', 'event': 'Takeout finished', 'numThrows': 0};
    late AutodartsLocalSource source;
    final (c, db) = await container(
      (kind, host, port) => source = AutodartsLocalSource(host: '127.0.0.1', port: board.port, random: math.Random(1)),
      prefs: {'settings.autodartsHost': '127.0.0.1', 'settings.autodartsPort': board.port},
    );
    final sub = c.listen(autodartsLiveProvider, (_, _) {});
    await until(() => source.status.phase == SourcePhase.connected && board.sockets.isNotEmpty);
    expect(source.listenOnly, isTrue);

    // Auch ein ausdrücklicher Befehl geht im Live-Modus nicht raus.
    expect(await source.send(AutodartsCommand.reset), isFalse);
    expect(await source.send(AutodartsCommand.start), isFalse);
    expect(await source.send(AutodartsCommand.stop), isFalse);

    for (final s in fixtureStates('board-manager-2.0.2-windows.jsonl')) {
      board.push(s);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await until(() => c.read(autodartsLiveProvider).stats.visits == 2 && c.read(autodartsLiveProvider).current.isEmpty);

    final live = c.read(autodartsLiveProvider);
    expect(live.stats.darts, 6);
    expect(live.recentVisits.map((v) => [for (final d in v) d.segment.name]), [
      ['S12', 'MISS', 'S20'],
      ['T20', 'T20', 'T5'],
    ]);
    expect(live.stats.points, 60 + 60 + 15 + 12 + 0 + 20);
    expect(live.stats.misses, 1);

    await c.read(autodartsLiveProvider.notifier).end();
    final sessions = await db.select(db.sessions).get();
    expect(sessions.single.gameId, autodartsLiveGameId);
    expect(sessions.single.dartCount, 6);
    expect(sessions.single.endedAt, isNotNull);
    final throws = await GameRepository(db).throwsOf(sessions.single.id);
    expect(throws.map((t) => t.segment), ['T20', 'T20', 'T5', 'S12', 'MISS', 'S20']);
    expect(throws.map((t) => t.visitIndex), [0, 0, 0, 1, 1, 1]);
    expect(throws.every((t) => t.x != null && t.source == 'autodartsLocal'), isTrue);

    // Die Statistik sieht die Session wie jede andere.
    final calc = StatsCalculator(sessions: sessions, throws: throws);
    expect(calc.report(StatsPeriod.all).darts, 6);
    expect(calc.report(StatsPeriod.all).scoringAverage, closeTo(167 / 6 * 3, 0.01));

    sub.close();
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Nur mitgehört: WebSocket (und höchstens Status), nie Befehle oder
    // die Pfade mit dem API-Schlüssel.
    expect(board.requests, isNotEmpty);
    for (final r in board.requests) {
      expect(r, anyOf('GET /api/events', 'GET /api/state'), reason: r);
    }
    expect(board.requests.where((r) => r.contains('/api/system') || r.contains('/api/config')), isEmpty);
    await board.close();
    await db.close();
  });

  test('nach dem Schließen gibt die Quelle Befehle wieder frei', () async {
    final board = await FakeBoardManager.start();
    late AutodartsLocalSource source;
    final (c, db) = await container((kind, host, port) => source = AutodartsLocalSource(host: '127.0.0.1', port: board.port));
    final sub = c.listen(autodartsLiveProvider, (_, _) {});
    expect(source.listenOnly, isTrue);
    sub.close();
    await Future<void>.delayed(Duration.zero);
    expect(source.listenOnly, isFalse);
    c.dispose();
    await board.close();
    await db.close();
  });

  group('mit Testquelle', () {
    late FakeLiveSource source;
    late ProviderContainer c;
    late AppDatabase db;
    var now = DateTime(2026, 10, 14, 20);

    setUp(() async {
      now = DateTime(2026, 10, 14, 20);
      source = FakeLiveSource(clock: () => now);
      (c, db) = await container((_, _, _) => source);
      c.listen(autodartsLiveProvider, (_, _) {});
    });

    tearDown(() async {
      final n = c.read(autodartsLiveProvider.notifier);
      c.dispose();
      // Beim Schließen speichert der Controller noch die laufende Session.
      await n.pendingWrites;
      await db.close();
    });

    AutodartsLiveController ctrl() => c.read(autodartsLiveProvider.notifier);

    test('jeder Dart wird sofort gespeichert, auch ohne Beenden (App geschlossen)', () async {
      source.visit(['T20', 'T20', 'T20']);
      source.dart('S20');
      await ctrl().pendingWrites;
      final sessions = await db.select(db.sessions).get();
      // Erste Aufnahme: Session sofort zwischengespeichert und damit sichtbar.
      expect(sessions.single.endedAt, isNotNull);
      expect(sessions.single.dartCount, 3);
      expect((await db.select(db.throws).get()).length, 4);

      // Simuliert einen Abbruch: endedAt fehlt, Dartzahl veraltet.
      await (db.update(db.sessions)).write(const SessionsCompanion(endedAt: Value(null), dartCount: Value(0)));
      expect(await repairLiveSessions(db), 1);
      final repaired = (await db.select(db.sessions).get()).single;
      expect(repaired.dartCount, 4);
      expect(repaired.endedAt, isNotNull);
      expect(await repairLiveSessions(db), 0);
    });

    test('lange Pause teilt die Session', () async {
      source.visit(['T20', 'T20', 'T20']);
      now = now.add(const Duration(minutes: 25));
      source.visit(['S1', 'S1', 'S1']);
      await ctrl().end();
      final sessions = await (db.select(db.sessions)..orderBy([(s) => OrderingTerm(expression: s.id)])).get();
      expect(sessions.map((s) => s.dartCount), [3, 3]);
      expect(sessions.map((s) => s.startedAt.minute), [0, 25]);
      expect(c.read(autodartsLiveProvider).sessionCount, 2);
    });

    test('Korrektur am Board ersetzt den gespeicherten Dart', () async {
      source.dart('T20');
      source.dart('S5');
      source.emit(DartCorrected(1, DartThrow(segment: Segment.tryParse('S1')!, timestamp: now, source: DartSourceKind.autodartsLocal)));
      source.emit(DartUndone(now));
      await ctrl().end();
      final throws = await db.select(db.throws).get();
      expect(throws.map((t) => t.segment), ['T20']);
    });

    test('X01 mitzählen: Rest, Checkout, Leg verloren und Speichern wie ein Match', () async {
      ctrl().setX01(const LiveX01Config(startScore: 301));
      source.visit(['T20', 'T20', 'T20']); // 121
      source.visit(['T20', 'T20', 'S20']); // Bust bei Rest 1
      expect(c.read(autodartsLiveProvider).x01!.remaining, 121);
      source.visit(['T20', 'S11', 'BULL']); // 121 - 60 - 11 - 50 = 0
      final x = c.read(autodartsLiveProvider).x01!;
      expect(x.legsWon, 1);
      expect(x.remaining, 301);
      source.visit(['T20', 'T20', 'T20']);
      ctrl().markLeg(LegMarkKind.lost);
      expect(c.read(autodartsLiveProvider).x01!.legsLost, 1);
      expect(c.read(autodartsLiveProvider).x01!.remaining, 301);
      await ctrl().end();

      final s = (await db.select(db.sessions).get()).single;
      expect(s.gameId, autodartsLiveX01GameId);
      final m = (jsonDecode(s.resultJson!) as Map)['metrics'] as Map;
      expect(m['legsWon'], 1);
      expect(m['legsLost'], 1);
      expect(m['highestFinish'], 121);
      expect(m['busts'], 1);
      // Bust-Aufnahme zählt 0: (180 + 0 + 121 + 180) / 11 gezählte Darts.
      expect(m['darts'], 11);
      expect((m['average'] as num).toDouble(), closeTo(481 / 11 * 3, 0.01));
      final throws = await db.select(db.throws).get();
      expect(throws.where((t) => !t.counted).length, 1, reason: 'Dart nach dem Bust');

      // Reparatur rechnet mit den gespeicherten Leg-Markierungen gleich.
      await (db.update(db.sessions)).write(const SessionsCompanion(endedAt: Value(null)));
      await repairLiveSessions(db);
      final again = (jsonDecode((await db.select(db.sessions).get()).single.resultJson!) as Map)['metrics'] as Map;
      expect(again['legsLost'], 1);
      expect(again['average'], m['average']);
    });

    test('Umschalten von X01 beginnt eine neue Session', () async {
      source.visit(['T20', 'T20', 'T20']);
      ctrl().setX01(const LiveX01Config());
      source.visit(['S20', 'S20', 'S20']);
      await ctrl().end();
      final ids = (await db.select(db.sessions).get()).map((s) => s.gameId);
      expect(ids, [autodartsLiveGameId, autodartsLiveX01GameId]);
    });

    test('ohne Darts bleibt keine leere Session zurück', () async {
      await ctrl().end();
      expect(await db.select(db.sessions).get(), isEmpty);
    });

    test('Ergebnis ohne X01 hat keinen Average-Schlüssel', () async {
      source.visit(['T20', 'S1', 'MISS']);
      await ctrl().end();
      final r = jsonDecode((await db.select(db.sessions).get()).single.resultJson!) as Map;
      expect((r['metrics'] as Map).containsKey('average'), isFalse);
    });
  });
}
