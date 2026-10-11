import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/backup/data/backup_service.dart';
import 'package:dartlab/features/plans/data/plan_repository.dart';
import 'package:dartlab/features/plans/domain/training_plan.dart';
import 'package:dartlab/features/sync/data/sync_store.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sync_device.dart';

/// Beide Richtungen, wie ein vollständiger Abgleich.
Future<void> sync(Device a, Device b) async {
  await b.store.merge(await a.store.bundle());
  await a.store.merge(await b.store.bundle());
}

/// Nur über die Manifeste (Hub-Protokoll, `/manifest`).
Future<void> syncMeta(Device client, Device hub) async {
  await hub.store.mergeMeta(await client.store.manifest());
  await client.store.mergeMeta(await hub.store.manifest());
}

const _steps = [PlanStep(gameId: 'bull_drill', config: {'visits': 2})];

extension on Device {
  PlanRepository get plans => PlanRepository(db);
  Future<List<TrainingPlanRow>> planRows() => db.select(db.trainingPlans).get();
  Future<void> stamp(String uid, DateTime at) =>
      (db.update(db.trainingPlans)..where((p) => p.uid.equals(uid))).write(TrainingPlansCompanion(updatedAt: Value(at)));
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Device a;
  late Device b;
  setUp(() {
    a = Device();
    b = Device();
  });
  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  test('eigener Plan landet auf dem anderen Gerät, zweiter Abgleich ändert nichts', () async {
    final id = await a.plans.create(name: 'Abendrunde', description: 'kurz', steps: _steps);
    await sync(a, b);
    final onB = (await b.plans.byId(id))!;
    expect(onB.name, 'Abendrunde');
    expect(onB.description, 'kurz');
    expect(onB.steps, _steps);
    final again = await b.store.merge(await a.store.bundle());
    expect(again.changedAnything, isFalse);
  });

  test('neuere Änderung gewinnt, in beide Richtungen', () async {
    final id = await a.plans.create(name: 'Plan', steps: _steps);
    await sync(a, b);
    await a.plans.update(id, name: 'Alt', now: DateTime(2030, 1, 1));
    await b.plans.update(id, name: 'Neu', steps: const [PlanStep(gameId: 'cricket')], now: DateTime(2030, 1, 2));
    await sync(a, b);
    for (final dev in [a, b]) {
      final p = (await dev.plans.byId(id))!;
      expect(p.name, 'Neu');
      expect(p.steps.single.gameId, 'cricket');
    }
  });

  test('Gleichstand: beide Seiten kommen zum selben Ergebnis', () async {
    final id = await a.plans.create(name: 'Plan', steps: _steps);
    await sync(a, b);
    final at = DateTime(2030, 5, 5, 12);
    await a.plans.update(id, name: 'Anton', now: at);
    await b.plans.update(id, name: 'Berta', now: at);
    await sync(a, b);
    await sync(a, b);
    final na = (await a.plans.byId(id))!.name;
    final nb = (await b.plans.byId(id))!.name;
    expect(na, nb);
    expect(na, 'Berta', reason: 'größerer Inhalt gewinnt');

    // Löschen gewinnt gegen Ändern bei gleicher Zeit.
    final at2 = DateTime(2030, 6, 6, 12);
    await a.plans.delete(id, at: at2);
    await b.plans.update(id, name: 'Zeta', now: at2);
    await sync(a, b);
    expect(await a.plans.byId(id), isNull);
    expect(await b.plans.byId(id), isNull);
  });

  test('Löschen wird weitergegeben und kommt über ein drittes Gerät nicht zurück', () async {
    final id = await a.plans.create(name: 'Weg damit', steps: _steps);
    await sync(a, b);
    final c = Device();
    addTearDown(c.db.close);
    await sync(b, c);
    expect(await c.plans.byId(id), isNotNull);

    await a.plans.delete(id, at: DateTime.now().add(const Duration(seconds: 5)));
    await sync(a, b);
    expect(await b.plans.byId(id), isNull);
    expect((await b.planRows()).single.deletedAt, isNotNull, reason: 'Markierung bleibt');

    // c hat den alten Stand und gleicht danach mit b ab.
    await sync(c, b);
    expect(await b.plans.byId(id), isNull);
    expect(await c.plans.byId(id), isNull);

    // Ein neues Gerät bekommt nur die Markierung.
    final d = Device();
    addTearDown(d.db.close);
    final r = await d.store.merge(await a.store.bundle());
    expect(r.plans, 0);
    expect((await d.planRows()).single.deletedAt, isNotNull);
  });

  test('Abgleich über die Manifeste (Hub-Protokoll) nimmt Pläne mit', () async {
    final id = await a.plans.create(name: 'Über den Hub', steps: _steps);
    await syncMeta(a, b);
    expect((await b.plans.byId(id))!.name, 'Über den Hub');
    final m = SyncManifest.fromJson(jsonDecode(jsonEncode((await a.store.manifest()).toJson())) as Map<String, Object?>);
    expect(m.plans.single['uid'], id);
  });

  test('Fingerabdruck ändert sich mit den Plänen', () async {
    final before = await a.store.signature();
    final id = await a.plans.create(name: 'X', steps: _steps);
    final created = await a.store.signature();
    expect(created, isNot(before));
    await a.stamp(id, DateTime(2031));
    expect(await a.store.signature(), isNot(created));
  });

  test('gleich benannte Pläne von zwei Geräten bleiben zwei Pläne', () async {
    await a.plans.create(name: 'Gleich', steps: _steps);
    await b.plans.create(name: 'Gleich', steps: _steps);
    await sync(a, b);
    expect(await a.plans.custom(), hasLength(2));
    expect(await b.plans.custom(), hasLength(2));
  });

  group('Backup', () {
    test('Version 3 enthält eigene Pläne und stellt sie wieder her', () async {
      final id = await a.plans.create(name: 'Gesichert', steps: _steps);
      final deleted = await a.plans.create(name: 'Gelöscht', steps: _steps);
      await a.plans.delete(deleted);
      final json = await BackupService(a.db).exportJson();
      final data = jsonDecode(json) as Map<String, Object?>;
      expect(data['version'], 3);
      expect(data['plans'], hasLength(2));

      final r = await BackupService(b.db).importJson(json);
      expect(r.plans, 1);
      expect((await b.plans.byId(id))!.steps, _steps);
      expect(await b.plans.byId(deleted), isNull);
      expect((await BackupService(b.db).importJson(json)).changedAnything, isFalse);
    });

    test('Backup eines Profils nimmt die Pläne mit', () async {
      await a.plans.create(name: 'Für alle', steps: _steps);
      final data = await BackupService(a.db).exportData(playerId: await a.me());
      expect(data['plans'], hasLength(1));
    });

    test('Version 2 ohne Pläne lässt sich weiter importieren', () async {
      final v2 = {
        'format': 'dartlab-backup',
        'version': 2,
        'players': [
          {'id': 1, 'uid': defaultPlayerUid, 'name': 'Ich', 'createdAt': '2026-10-01T10:00:00.000Z'},
        ],
        'sessions': const [],
        'throws': const [],
        'goals': [
          {
            'uid': 'g1',
            'playerUid': defaultPlayerUid,
            'kind': 'weeklySessions',
            'target': 4.0,
            'createdAt': '2026-10-01T10:00:00.000Z',
          },
        ],
      };
      final r = await BackupService(b.db).importJson(jsonEncode(v2));
      expect(r.goals, 1);
      expect(r.plans, 0);
      expect(await b.planRows(), isEmpty);
    });

    test('kaputte Plan-Einträge werden übersprungen', () async {
      final r = await b.store.merge(SyncBundle.fromJson({
        'plans': [
          {'uid': 'p1', 'name': '', 'stepsJson': '[]'},
          {'name': 'ohne uid', 'stepsJson': '[]'},
          {'uid': 'p2', 'name': 'ok', 'stepsJson': '[{"gameId":"game_from_the_future"}]', 'createdAt': '2026-10-01T10:00:00.000Z'},
        ],
      }));
      expect(r.plans, 1);
      final plan = (await b.plans.byId('p2'))!;
      expect(plan.steps.single.available, isFalse);
    });
  });
}
