import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/autodarts_live/domain/live_stats.dart';
import 'package:dartlab/features/autodarts_live/domain/live_x01.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_controller.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_live_source.dart';

Segment seg(String name) => Segment.tryParse(name)!;

void main() {
  late FakeLiveSource source;
  late ProviderContainer c;
  late AppDatabase db;
  var now = DateTime(2026, 10, 14, 20);

  setUp(() async {
    now = DateTime(2026, 10, 14, 20);
    source = FakeLiveSource(clock: () => now);
    SharedPreferences.setMockInitialValues({'settings.sourceKind': 'autodartsLocal'});
    final sp = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(db),
      dartSourceFactoryProvider.overrideWithValue((_, _, _) => source),
    ]);
    c.listen(autodartsLiveProvider, (_, _) {});
  });

  tearDown(() async {
    final n = c.read(autodartsLiveProvider.notifier);
    c.dispose();
    await n.pendingWrites;
    await db.close();
  });

  AutodartsLiveController ctrl() => c.read(autodartsLiveProvider.notifier);
  LiveViewState view() => c.read(autodartsLiveProvider);

  Future<List<ThrowRow>> stored() async {
    await ctrl().pendingWrites;
    final s = await db.select(db.sessions).get();
    return GameRepository(db).throwsOf(s.where((x) => x.deletedAt == null).last.id);
  }

  Future<SessionRow> session() async {
    await ctrl().pendingWrites;
    return (await (db.select(db.sessions)..orderBy([(s) => OrderingTerm.desc(s.id)])).get()).first;
  }

  Map<String, Object?> metrics(SessionRow s) => ((jsonDecode(s.resultJson!) as Map)['metrics'] as Map).cast();

  group('ohne X01', () {
    test('Dart einer abgeschlossenen Aufnahme ändern: Wurf, Ergebnis und Ansicht', () async {
      source.visit(['T20', 'T20', 'T20']);
      source.visit(['S1', 'S5', 'S20']);
      expect(view().closedCount, 2);

      expect(ctrl().correctDart(0, 2, seg('S20')), isTrue);
      final rows = await stored();
      expect(rows.map((t) => t.segment), ['T20', 'T20', 'S20', 'S1', 'S5', 'S20']);
      expect(rows.map((t) => t.seq), [0, 1, 2, 3, 4, 5]);
      expect(rows.map((t) => t.visitIndex), [0, 0, 0, 1, 1, 1]);
      // Geändert: von Hand, ohne Koordinaten; die übrigen behalten sie.
      expect(rows.map((t) => t.source), [
        'autodartsLocal',
        'autodartsLocal',
        'manual',
        'autodartsLocal',
        'autodartsLocal',
        'autodartsLocal',
      ]);
      expect(rows.map((t) => t.x == null), [false, false, true, false, false, false]);
      expect(rows[2].y, isNull);
      expect(rows[2].rawJson, isNull);
      expect(rows[2].number, 20);
      expect(rows[2].multiplier, 1);
      expect(rows[2].score, 20);

      final s = await session();
      expect(s.dartCount, 6);
      expect(s.endedAt, isNotNull);
      expect(metrics(s)['points'], 60 + 60 + 20 + 26);
      expect(view().stats.points, 60 + 60 + 20 + 26);
      expect(view().recentVisits.first.map((d) => d.segment.name), ['S1', 'S5', 'S20']);
      expect(view().lastVisit!.map((d) => d.segment.name), ['S1', 'S5', 'S20']);
    });

    test('Dart entfernen und ganze Aufnahme löschen: Stellen und Nummern bleiben zusammenhängend', () async {
      source.visit(['T20', 'T20', 'T20']);
      source.visit(['S1', 'S5', 'S20']);
      source.visit(['D1', 'D2', 'D3']);
      expect(ctrl().removeDart(1, 1), isTrue);
      var rows = await stored();
      expect(rows.map((t) => t.segment), ['T20', 'T20', 'T20', 'S1', 'S20', 'D1', 'D2', 'D3']);
      expect(rows.map((t) => t.seq), List.generate(8, (i) => i));
      expect(rows.map((t) => t.visitIndex), [0, 0, 0, 1, 1, 2, 2, 2]);
      // Die übrigen Darts behalten ihre Koordinaten (nur der Dart fehlt).
      expect(rows.every((t) => t.x != null && t.source == 'autodartsLocal'), isTrue);

      expect(ctrl().removeVisit(0), isTrue);
      rows = await stored();
      expect(rows.map((t) => t.segment), ['S1', 'S20', 'D1', 'D2', 'D3']);
      expect(rows.map((t) => t.visitIndex), [0, 0, 1, 1, 1]);
      expect((await session()).dartCount, 5);
      expect(view().closedCount, 2);
      expect(view().stats.darts, 5);

      // Weitere Board-Darts hängen sich korrekt an.
      source.visit(['S3', 'S4', 'S5']);
      rows = await stored();
      expect(rows.map((t) => t.seq), List.generate(8, (i) => i));
      expect(rows.map((t) => t.visitIndex), [0, 0, 1, 1, 1, 2, 2, 2]);
    });

    test('Dart ergänzen: in abgeschlossene und laufende Aufnahme, höchstens drei', () async {
      source.visit(['T20', 'T20']);
      source.visit(['S1', 'S5', 'S20']);
      source.dart('D4');
      expect(ctrl().addDart(1, seg('S3')), isFalse, reason: 'schon drei Darts');
      expect(ctrl().addDart(0, seg('T19')), isTrue);
      expect(ctrl().addDart(2, seg('S2')), isTrue);
      expect(ctrl().addDart(5, seg('S2')), isFalse);
      final rows = await stored();
      expect(rows.map((t) => t.segment), ['T20', 'T20', 'T19', 'S1', 'S5', 'S20', 'D4', 'S2']);
      expect(rows.map((t) => t.visitIndex), [0, 0, 0, 1, 1, 1, 2, 2]);
      expect(rows.map((t) => t.source), [
        'autodartsLocal',
        'autodartsLocal',
        'manual',
        'autodartsLocal',
        'autodartsLocal',
        'autodartsLocal',
        'autodartsLocal',
        'manual',
      ]);
      expect(rows[2].x, isNull);
      expect((await session()).dartCount, 8);

      // Das Board spielt weiter: dritter Dart der Aufnahme, dann die nächste Aufnahme.
      source.dart('S9');
      source.takeout();
      source.visit(['S8']);
      final after = await stored();
      expect(after.map((t) => t.seq), List.generate(10, (i) => i));
      expect(after.map((t) => t.visitIndex), [0, 0, 0, 1, 1, 1, 2, 2, 2, 3]);
    });

    test('von Hand gesetzter Dart bleibt, die Korrektur vom Board ändert ihn nicht', () async {
      source.dart('T20');
      source.dart('T5');
      expect(ctrl().correctDart(0, 1, seg('S19')), isTrue);
      source.emit(DartCorrected(1, DartThrow(segment: seg('S1'), timestamp: now, source: DartSourceKind.autodartsLocal)));
      source.emit(DartUndone(now));
      expect(view().current.map((d) => d.segment.name), ['T20', 'S19']);
      var rows = await stored();
      expect(rows.map((t) => t.segment), ['T20', 'S19']);
      expect(rows.last.source, 'manual');

      // Der erste Dart folgt dem Board weiter.
      source.emit(DartCorrected(0, DartThrow(segment: seg('D20'), timestamp: now, source: DartSourceKind.autodartsLocal)));
      rows = await stored();
      expect(rows.map((t) => t.segment), ['D20', 'S19']);
      expect(rows.map((t) => t.source), ['autodartsLocal', 'manual']);
    });

    test('Dart in der laufenden Aufnahme gelöscht: Board-Korrektur ignoriert, nächste Aufnahme normal', () async {
      source.dart('T20');
      source.dart('T5');
      ctrl().removeDart(0, 0);
      source.emit(DartCorrected(0, DartThrow(segment: seg('D20'), timestamp: now, source: DartSourceKind.autodartsLocal)));
      source.emit(DartUndone(now));
      expect(view().current.map((d) => d.segment.name), ['T5']);
      source.takeout();
      source.dart('S1');
      source.emit(DartUndone(now));
      expect(view().current, isEmpty);
      expect((await stored()).map((t) => t.segment), ['T5']);
    });

    test('alle Darts gelöscht: Session verschwindet, der nächste Dart beginnt eine neue', () async {
      source.visit(['T20', 'T20', 'T20']);
      source.visit(['S1']);
      await ctrl().pendingWrites;
      expect(ctrl().removeVisit(1), isTrue);
      expect(ctrl().removeDart(0, 0), isTrue);
      expect(ctrl().removeDart(0, 0), isTrue);
      expect(ctrl().removeDart(0, 0), isTrue);
      await ctrl().pendingWrites;
      expect(view().stats.darts, 0);
      var sessions = await db.select(db.sessions).get();
      // Gelöscht wie im Verlauf: Löschmarke, keine Würfe, keine Dartzahl.
      expect(sessions.single.deletedAt, isNotNull);
      expect(sessions.single.dartCount, 0);
      expect(await db.select(db.throws).get(), isEmpty);
      // Die Reparatur beim Öffnen fasst die Löschmarke nicht an.
      expect(await repairLiveSessions(db), 0);
      expect((await db.select(db.sessions).get()).single.deletedAt, isNotNull);

      source.visit(['S20', 'S20', 'S20']);
      await ctrl().end();
      sessions = await db.select(db.sessions).get();
      expect(sessions.length, 2);
      final live = sessions.where((s) => s.deletedAt == null).single;
      expect(live.dartCount, 3);
      expect(view().sessionCount, 1, reason: 'keine zweite Session gezählt');
    });

    test('Dart in leere Session ergänzen legt die Session an (z. B. nach Umschalten)', () async {
      expect(ctrl().addDart(0, seg('T20')), isTrue);
      expect(ctrl().addDart(0, seg('T20')), isTrue);
      expect(view().current.map((d) => d.segment.name), ['T20', 'T20']);
      expect(view().sessionCount, 1);
      final rows = await stored();
      expect(rows.map((t) => t.segment), ['T20', 'T20']);
      expect(rows.every((t) => t.source == 'manual' && t.x == null), isTrue);
      final s = await session();
      expect(s.gameId, autodartsLiveGameId);
      expect(s.dartCount, 2);
      expect(s.endedAt, isNotNull);
      // Das Board hängt an die laufende Aufnahme an.
      source.dart('S1');
      expect((await stored()).map((t) => t.segment), ['T20', 'T20', 'S1']);
    });

    test('nach „Beenden“ ändert sich nichts mehr', () async {
      source.visit(['T20', 'T20', 'T20']);
      await ctrl().end();
      expect(ctrl().correctDart(0, 0, seg('S1')), isFalse);
      expect(ctrl().removeDart(0, 0), isFalse);
      expect(ctrl().addDart(1, seg('S1')), isFalse);
      expect(ctrl().removeVisit(0), isFalse);
      expect((await stored()).map((t) => t.segment), ['T20', 'T20', 'T20']);
    });

    test('Statistik-Seite: von Hand gesetzte Darts liefern keine Streupunkte', () async {
      source.visit(['T20', 'T20', 'T20']);
      ctrl().correctDart(0, 0, seg('T19'));
      final rows = await stored();
      expect(rows.where((t) => t.source == 'manual' && (t.x != null || t.y != null)), isEmpty);
    });
  });

  group('mit X01 mitzählen', () {
    setUp(() => ctrl().setX01(const LiveX01Config(startScore: 301)));

    Map<String, Object?> details(SessionRow s) => ((jsonDecode(s.resultJson!) as Map)['details'] as Map).cast();

    test('Korrektur rechnet Rest, Bust, „gezählt“ und Kennzahlen neu', () async {
      source.visit(['T20', 'T20', 'T20']); // 121
      source.visit(['T20', 'T20', 'S20']); // Rest 1 = Bust nach dem zweiten Dart, der dritte zählt nicht
      expect(view().x01!.remaining, 121);
      expect(view().x01!.busts, 1);
      var rows = await stored();
      expect(rows.map((t) => t.counted), [true, true, true, true, true, false]);

      // Zweiter Dart S19: 121 - 60 - 19 - 20 = 22, kein Bust, alle Darts zählen.
      expect(ctrl().correctDart(1, 1, seg('S19')), isTrue);
      expect(view().x01!.remaining, 22);
      expect(view().x01!.busts, 0);
      rows = await stored();
      expect(rows.map((t) => t.counted), everyElement(isTrue));
      var m = metrics(await session());
      expect(m['busts'], 0);
      expect(m['darts'], 6);
      expect(m['average'], closeTo((180 + 60 + 19 + 20) / 6 * 3, 0.01));

      // Zurück: wieder Bust, der letzte Dart zählt nicht, die Bust-Aufnahme 0 Punkte.
      expect(ctrl().correctDart(1, 1, seg('T20')), isTrue);
      expect(view().x01!.remaining, 121);
      rows = await stored();
      expect(rows.map((t) => t.counted), [true, true, true, true, true, false]);
      m = metrics(await session());
      expect(m['busts'], 1);
      expect(m['darts'], 5);
      expect(m['average'], closeTo(180 / 5 * 3, 0.01));
    });

    test('Checkout entsteht und verschwindet durch Korrekturen; Ergebnis und Reparatur stimmen', () async {
      source.visit(['T20', 'T20', 'T20']);
      source.visit(['T20', 'S11', 'BULL']); // 121 - 60 - 11 - 50 = 0
      expect(view().x01!.legsWon, 1);
      expect(view().x01!.remaining, 301);
      expect(view().x01!.highestFinish, 121);

      ctrl().correctDart(1, 2, seg('S5')); // 121 - 76 = 45
      expect(view().x01!.legsWon, 0);
      expect(view().x01!.remaining, 45);
      var s = await session();
      var m = metrics(s);
      expect(m['legsWon'], 0);
      expect(m['highestFinish'], 0);
      expect(m['darts'], 6);
      expect(s.dartCount, 6);

      // Dart entfernen und anderen Dart ergänzen: 121 - 60 - 50 = 11, dann S1 -> 10.
      ctrl().removeDart(1, 1);
      expect(view().x01!.remaining, 121 - 60 - 5);
      ctrl().correctDart(1, 1, seg('BULL'));
      expect(view().x01!.remaining, 11);
      ctrl().addDart(1, seg('S1'));
      expect(view().x01!.remaining, 10);
      expect((await stored()).map((t) => t.segment), ['T20', 'T20', 'T20', 'T20', 'BULL', 'S1']);

      // Reparatur nach einem Absturz rechnet aus den Würfen gleich.
      s = await session();
      m = metrics(s);
      await db.update(db.sessions).write(const SessionsCompanion(endedAt: Value(null)));
      expect(await repairLiveSessions(db), 1);
      final again = metrics(await session());
      expect(again['average'], m['average']);
      expect(again['legsWon'], m['legsWon']);
      expect(again['darts'], m['darts']);
    });

    test('„Leg verloren“ bleibt zwischen denselben Darts, wenn Darts davor entfernt oder ergänzt werden', () async {
      source.visit(['T20', 'T20', 'T20']);
      source.visit(['S20', 'S20', 'S20']);
      ctrl().markLeg(LegMarkKind.lost); // nach Dart 6
      source.visit(['T19', 'S1', 'S1']); // Leg 2: 301 - 59
      expect(view().x01!.legsLost, 1);
      expect(view().x01!.legs.single.darts, 6);
      expect(view().x01!.remaining, 301 - 59);

      ctrl().removeDart(0, 0);
      var x = view().x01!;
      expect(x.legsLost, 1);
      expect(x.legs.single.darts, 5, reason: 'Leg 1 hat jetzt fünf Darts');
      expect(x.remaining, 301 - 59, reason: 'Leg 2 unverändert');
      expect(metrics(await session())['legsLost'], 1);
      expect((details(await session())['marks'] as List).single, {'at': 5, 'kind': 'lost'});

      // Ergänzter Dart am Ende einer Aufnahme vor der Marke gehört noch ins alte Leg.
      ctrl().addDart(0, seg('S5'));
      x = view().x01!;
      expect(x.legs.single.darts, 6);
      expect(x.remaining, 301 - 59);
      expect((details(await session())['marks'] as List).single, {'at': 6, 'kind': 'lost'});

      // Eine ganze Aufnahme löschen: die Marke rückt um deren Darts vor.
      ctrl().removeVisit(0);
      x = view().x01!;
      expect(x.legs.single.darts, 3);
      expect(x.remaining, 301 - 59);
      expect((details(await session())['marks'] as List).single, {'at': 3, 'kind': 'lost'});

      // Die Darts von Leg 2 bleiben in Leg 2, auch in der Datenbank.
      final rows = await stored();
      expect(rows.map((t) => t.segment), ['S20', 'S20', 'S20', 'T19', 'S1', 'S1']);
      expect(rows.map((t) => t.visitIndex), [0, 0, 0, 1, 1, 1]);
    });

    test('Löscht man die Darts vor der Marke ganz, hat die Marke nichts mehr zu beenden', () async {
      source.visit(['T20', 'T20', 'T20']);
      ctrl().markLeg(LegMarkKind.lost);
      source.visit(['S20', 'S20', 'S20']);
      expect(view().x01!.legsLost, 1);
      ctrl().removeVisit(0);
      final x = view().x01!;
      expect(x.legsLost, 0, reason: 'ohne Darts im Leg ist die Marke wirkungslos');
      expect(x.remaining, 301 - 60);
    });

    test('Dart in die laufende Aufnahme nach „Leg verloren“ gehört ins neue Leg', () async {
      source.visit(['T20', 'T20', 'T20']);
      ctrl().markLeg(LegMarkKind.lost); // nach Dart 3, laufende Aufnahme noch leer
      expect(ctrl().addDart(1, seg('S20')), isTrue);
      final x = view().x01!;
      expect(x.legsLost, 1);
      expect(x.remaining, 301 - 20);
      expect(x.legDarts, 1);
    });

    test('von Hand ergänzter Dart rechnet in „X01 mitzählen“ mit und bleibt ohne Position', () async {
      source.visit(['T20', 'T20']);
      expect(ctrl().addDart(0, seg('T20')), isTrue);
      expect(view().x01!.remaining, 121);
      final rows = await stored();
      expect(rows.last.source, 'manual');
      expect(rows.last.x, isNull);
      expect(rows.last.counted, isTrue);
    });
  });
}
