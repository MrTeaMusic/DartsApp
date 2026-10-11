import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/builtin_plans.dart';
import '../domain/training_plan.dart';

/// Eigene Trainingspläne anlegen, ändern, löschen und Plan-Durchläufe
/// speichern. Feste Pläne kommen aus [BuiltinPlans].
class PlanRepository {
  PlanRepository(this.db);
  final AppDatabase db;

  static TrainingPlan fromRow(TrainingPlanRow r) => TrainingPlan(
        id: r.uid,
        name: r.name,
        description: r.description,
        steps: PlanStep.decodeList(r.stepsJson),
      );

  SimpleSelectStatement<$TrainingPlansTable, TrainingPlanRow> _custom() => db.select(db.trainingPlans)
    ..where((p) => p.deletedAt.isNull())
    ..orderBy([(p) => OrderingTerm.asc(p.createdAt), (p) => OrderingTerm.asc(p.id)]);

  /// Eigene Pläne (ohne gelöschte), älteste zuerst.
  Stream<List<TrainingPlan>> watchCustom() => _custom().watch().map((rows) => [for (final r in rows) fromRow(r)]);

  Future<List<TrainingPlan>> custom() async => [for (final r in await _custom().get()) fromRow(r)];

  /// Fester oder eigener Plan; `null`, wenn es ihn nicht (mehr) gibt.
  Future<TrainingPlan?> byId(String id) async {
    if (TrainingPlan.isBuiltinId(id)) return BuiltinPlans.byId(id);
    final row = await (db.select(db.trainingPlans)..where((p) => p.uid.equals(id) & p.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : fromRow(row);
  }

  Stream<TrainingPlan?> watchById(String id) {
    if (TrainingPlan.isBuiltinId(id)) return Stream.value(BuiltinPlans.byId(id));
    return (db.select(db.trainingPlans)..where((p) => p.uid.equals(id) & p.deletedAt.isNull()))
        .watchSingleOrNull()
        .map((r) => r == null ? null : fromRow(r));
  }

  /// Legt einen eigenen Plan an und gibt seine ID (`uid`) zurück.
  Future<String> create({required String name, String description = '', required List<PlanStep> steps, DateTime? now}) async {
    final n = TrainingPlan.cleanName(name);
    if (n.isEmpty) throw ArgumentError('Name fehlt');
    final at = now ?? DateTime.now();
    final uid = newUid();
    await db.into(db.trainingPlans).insert(TrainingPlansCompanion.insert(
          uid: Value(uid),
          name: n,
          description: Value(TrainingPlan.cleanDescription(description)),
          stepsJson: PlanStep.encodeList(steps),
          createdAt: at,
          updatedAt: Value(at),
        ));
    return uid;
  }

  /// Ändert einen eigenen Plan. Feste Pläne lassen sich nicht ändern.
  Future<void> update(String id, {String? name, String? description, List<PlanStep>? steps, DateTime? now}) async {
    if (TrainingPlan.isBuiltinId(id)) throw ArgumentError('Feste Pläne sind nicht änderbar');
    final n = name == null ? null : TrainingPlan.cleanName(name);
    if (n != null && n.isEmpty) throw ArgumentError('Name fehlt');
    await (db.update(db.trainingPlans)..where((p) => p.uid.equals(id) & p.deletedAt.isNull())).write(TrainingPlansCompanion(
      name: n == null ? const Value.absent() : Value(n),
      description: description == null ? const Value.absent() : Value(TrainingPlan.cleanDescription(description)),
      stepsJson: steps == null ? const Value.absent() : Value(PlanStep.encodeList(steps)),
      updatedAt: Value(now ?? DateTime.now()),
    ));
  }

  /// Kopie eines festen oder eigenen Plans als neuer eigener Plan.
  Future<String> duplicate(TrainingPlan plan, {required String name}) =>
      create(name: name, description: plan.description, steps: plan.steps);

  /// Markiert einen eigenen Plan als gelöscht, damit der Abgleich es
  /// weitergibt.
  Future<void> delete(String id, {DateTime? at}) async {
    if (TrainingPlan.isBuiltinId(id)) throw ArgumentError('Feste Pläne sind nicht löschbar');
    final now = at ?? DateTime.now();
    await (db.update(db.trainingPlans)..where((p) => p.uid.equals(id)))
        .write(TrainingPlansCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  // ------------------------------------------------------- Durchläufe

  static PlanRun runFromRow(PlanRunRow r) => PlanRun(
        id: r.id,
        uid: r.uid,
        planId: r.planId,
        planName: r.planName,
        steps: PlanStep.decodeList(r.stepsJson),
        playerId: r.playerId,
        startedAt: r.startedAt,
        finishedAt: r.finishedAt,
        currentStep: r.currentStep,
        results: StepResult.decodeList(r.resultsJson),
      );

  /// Beginnt einen neuen Durchlauf. Ein offener Durchlauf desselben Plans
  /// für das Profil wird verworfen (sauberer Neustart).
  Future<PlanRun> startRun(TrainingPlan plan, {required int playerId, DateTime? now}) async {
    await discardOpenRuns(plan.id, playerId: playerId);
    final id = await db.into(db.planRuns).insert(PlanRunsCompanion.insert(
          planId: plan.id,
          planName: plan.name,
          stepsJson: PlanStep.encodeList(plan.steps),
          playerId: playerId,
          startedAt: now ?? DateTime.now(),
        ));
    return (await run(id))!;
  }

  Future<PlanRun?> run(int id) async {
    final row = await (db.select(db.planRuns)..where((r) => r.id.equals(id))).getSingleOrNull();
    return row == null ? null : runFromRow(row);
  }

  Stream<PlanRun?> watchRun(int id) =>
      (db.select(db.planRuns)..where((r) => r.id.equals(id))).watchSingleOrNull().map((r) => r == null ? null : runFromRow(r));

  /// Letzter offener Durchlauf eines Plans für ein Profil.
  Future<PlanRun?> openRun(String planId, {required int playerId}) async {
    final row = await _openQuery(planId, playerId).getSingleOrNull();
    return row == null ? null : runFromRow(row);
  }

  Stream<PlanRun?> watchOpenRun(String planId, {required int playerId}) =>
      _openQuery(planId, playerId).watchSingleOrNull().map((r) => r == null ? null : runFromRow(r));

  SimpleSelectStatement<$PlanRunsTable, PlanRunRow> _openQuery(String planId, int playerId) => db.select(db.planRuns)
    ..where((r) => r.planId.equals(planId) & r.playerId.equals(playerId) & r.finishedAt.isNull())
    ..orderBy([(r) => OrderingTerm.desc(r.id)])
    ..limit(1);

  Future<void> discardOpenRuns(String planId, {required int playerId}) =>
      (db.delete(db.planRuns)..where((r) => r.planId.equals(planId) & r.playerId.equals(playerId) & r.finishedAt.isNull())).go();

  /// Speichert das Ergebnis eines Schritts und geht zum nächsten. Ein
  /// zweites Ergebnis für denselben Schritt ersetzt das erste.
  Future<PlanRun> recordStep(int runId, StepResult result) async {
    final current = (await run(runId))!;
    final results = [for (final r in current.results) if (r.step != result.step) r, result]
      ..sort((a, b) => a.step.compareTo(b.step));
    final next = result.step + 1 > current.currentStep ? result.step + 1 : current.currentStep;
    await (db.update(db.planRuns)..where((r) => r.id.equals(runId))).write(PlanRunsCompanion(
      resultsJson: Value(StepResult.encodeList(results)),
      currentStep: Value(next.clamp(0, current.steps.length)),
    ));
    return (await run(runId))!;
  }

  Future<PlanRun> finishRun(int runId, {DateTime? at}) async {
    await (db.update(db.planRuns)..where((r) => r.id.equals(runId)))
        .write(PlanRunsCompanion(finishedAt: Value(at ?? DateTime.now())));
    return (await run(runId))!;
  }
}

final planRepositoryProvider = Provider<PlanRepository>((ref) => PlanRepository(ref.watch(appDatabaseProvider)));

final customPlansProvider = StreamProvider<List<TrainingPlan>>((ref) => ref.watch(planRepositoryProvider).watchCustom());
