import 'dart:io';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/plans/data/plan_repository.dart';
import 'package:dartlab/features/plans/domain/builtin_plans.dart';
import 'package:dartlab/features/plans/domain/training_plan.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const _steps = [
  PlanStep(gameId: 'bull_drill', config: {'visits': 2}),
  PlanStep(gameId: 'checkout', config: {'min': 2, 'max': 40}, note: 'Doppel'),
];

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late AppDatabase db;
  late PlanRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = PlanRepository(db);
  });
  tearDown(() => db.close());

  group('eigene Pläne', () {
    test('anlegen, lesen, ändern', () async {
      final id = await repo.create(name: '  Abendrunde ', description: 'kurz', steps: _steps);
      expect(id, hasLength(32));
      final plan = (await repo.byId(id))!;
      expect(plan.name, 'Abendrunde');
      expect(plan.description, 'kurz');
      expect(plan.steps, _steps);
      expect(plan.builtIn, isFalse);

      final row1 = await db.select(db.trainingPlans).getSingle();
      expect(row1.updatedAt, isNotNull);
      await repo.update(id, name: 'Neu', steps: _steps.reversed.toList(), now: DateTime(2030));
      final changed = (await repo.byId(id))!;
      expect(changed.name, 'Neu');
      expect(changed.description, 'kurz');
      expect(changed.steps.first.gameId, 'checkout');
      expect((await db.select(db.trainingPlans).getSingle()).updatedAt, DateTime(2030));
    });

    test('ohne Namen geht es nicht', () async {
      expect(() => repo.create(name: '   ', steps: _steps), throwsArgumentError);
      final id = await repo.create(name: 'A', steps: _steps);
      expect(() => repo.update(id, name: ''), throwsArgumentError);
    });

    test('Löschen hinterlässt eine Markierung, Liste ohne gelöschte', () async {
      final a = await repo.create(name: 'A', steps: _steps);
      await repo.create(name: 'B', steps: _steps);
      await repo.delete(a);
      expect((await repo.custom()).map((p) => p.name), ['B']);
      expect(await repo.byId(a), isNull);
      final row = await (db.select(db.trainingPlans)..where((p) => p.uid.equals(a))).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(row.updatedAt, row.deletedAt);
      expect(await repo.watchCustom().first, hasLength(1));
    });

    test('festen Plan kopieren ergibt einen änderbaren eigenen Plan', () async {
      final warmup = BuiltinPlans.all.first;
      final id = await repo.duplicate(warmup, name: 'Mein Aufwärmen');
      final copy = (await repo.byId(id))!;
      expect(copy.steps, warmup.steps);
      expect(copy.description, warmup.description);
      expect(copy.id, isNot(warmup.id));
      await repo.update(id, steps: copy.steps.sublist(1));
      expect((await repo.byId(id))!.steps, hasLength(warmup.steps.length - 1));
      // Das Original bleibt unverändert und unveränderbar.
      expect(BuiltinPlans.byId(warmup.id)!.steps, hasLength(warmup.steps.length));
      expect(() => repo.update(warmup.id, name: 'x'), throwsArgumentError);
      expect(() => repo.delete(warmup.id), throwsArgumentError);
      expect(await repo.byId(warmup.id), same(warmup));
    });
  });

  group('Durchläufe', () {
    late int me;
    setUp(() async => me = await ProfileRepository(db).resolve(null));

    test('Schritte speichern, fortsetzen, abschließen', () async {
      final id = await repo.create(name: 'A', steps: _steps);
      final plan = (await repo.byId(id))!;
      var run = await repo.startRun(plan, playerId: me);
      expect(run.currentStep, 0);
      expect(run.planName, 'A');
      expect(run.steps, _steps);

      run = await repo.recordStep(run.id, const StepResult(step: 0, status: StepStatus.done, sessionUid: 's1', summary: [('points', '50')]));
      expect(run.currentStep, 1);
      // Nochmal derselbe Schritt ersetzt das Ergebnis, Fortschritt bleibt.
      run = await repo.recordStep(run.id, const StepResult(step: 0, status: StepStatus.aborted, sessionUid: 's2'));
      expect(run.currentStep, 1);
      expect(run.results.single.sessionUid, 's2');

      // Plan nachträglich ändern: der Durchlauf behält seine Schritte.
      await repo.update(id, steps: const [PlanStep(gameId: 'cricket')]);
      final open = (await repo.openRun(id, playerId: me))!;
      expect(open.id, run.id);
      expect(open.steps, _steps);

      run = await repo.recordStep(run.id, const StepResult(step: 1, status: StepStatus.done));
      expect(run.allStepsDone, isTrue);
      run = await repo.finishRun(run.id);
      expect(run.finished, isTrue);
      expect(await repo.openRun(id, playerId: me), isNull);
    });

    test('Neustart verwirft den offenen Durchlauf', () async {
      final plan = BuiltinPlans.all.first;
      final first = await repo.startRun(plan, playerId: me);
      await repo.recordStep(first.id, const StepResult(step: 0, status: StepStatus.done));
      final second = await repo.startRun(plan, playerId: me);
      expect(await repo.run(first.id), isNull);
      expect((await repo.openRun(plan.id, playerId: me))!.id, second.id);
      expect(second.currentStep, 0);
    });
  });

  test('Migration von Version 3 legt die Plan-Tabellen an, wiederholbar', () async {
    final dir = await Directory.systemTemp.createTemp('dartlab');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    // Datenbank wie in Version 3: ohne Plan-Tabellen.
    final v3 = AppDatabase(NativeDatabase(file));
    final me = await ProfileRepository(v3).resolve(null);
    await v3.customStatement('DROP TABLE plan_runs');
    await v3.customStatement('DROP TABLE training_plans');
    await v3.customStatement('PRAGMA user_version = 3');
    await v3.close();

    final v4 = AppDatabase(NativeDatabase(file));
    final repo4 = PlanRepository(v4);
    final id = await repo4.create(name: 'Nach Migration', steps: _steps);
    await repo4.startRun((await repo4.byId(id))!, playerId: me);
    expect((await v4.select(v4.players).get()).single.uid, defaultPlayerUid);
    await v4.close();

    // Ein abgebrochener Lauf hat die Tabellen schon angelegt, die Version
    // aber nicht erhöht: der Schritt läuft erneut und behält die Daten.
    final raw = sqlite3.open(file.path);
    raw.execute('PRAGMA user_version = 3');
    raw.close();
    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect((await PlanRepository(again).custom()).single.name, 'Nach Migration');
    expect(await again.select(again.planRuns).get(), hasLength(1));
    final indexes = await again.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE '%_uid'").get();
    expect(indexes.map((r) => r.read<String>('name')), containsAll(['training_plans_uid', 'plan_runs_uid']));
    final version = await again.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 5);
  });
}
