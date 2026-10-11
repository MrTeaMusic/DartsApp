import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../profiles/presentation/active_player.dart';
import '../domain/goals.dart';
import '../domain/stats_calculator.dart';

/// Liest die Daten für Statistiken und verwaltet Ziele.
class StatsRepository {
  StatsRepository(this.db);
  final AppDatabase db;

  /// Neu berechnen, sobald sich Sessions des Spielers ändern.
  Stream<StatsCalculator> watchCalculator(int playerId) {
    final q = db.select(db.sessions)..where((s) => s.playerId.equals(playerId) & s.endedAt.isNotNull());
    return q.watch().asyncMap((sessions) async {
      final throws = await (db.select(db.throws)..where((t) => t.playerId.equals(playerId))).get();
      return StatsCalculator(sessions: sessions, throws: throws);
    });
  }

  Stream<List<GoalRow>> watchGoals(int playerId) =>
      (db.select(db.goals)
            ..where((g) => g.playerId.equals(playerId) & g.deletedAt.isNull())
            ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]))
          .watch();

  Future<int> addGoal(int playerId, GoalKind kind, double target) => db.into(db.goals).insert(GoalsCompanion.insert(
        playerId: playerId,
        kind: kind.name,
        target: target,
        createdAt: DateTime.now(),
        updatedAt: Value(DateTime.now()),
      ));

  Future<void> updateGoal(int id, double target) =>
      (db.update(db.goals)..where((g) => g.id.equals(id))).write(GoalsCompanion(target: Value(target), updatedAt: Value(DateTime.now())));

  /// Markiert das Ziel als gelöscht, damit der Abgleich es weitergibt.
  Future<void> deleteGoal(int id) {
    final now = DateTime.now();
    return (db.update(db.goals)..where((g) => g.id.equals(id)))
        .write(GoalsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }
}

final statsRepositoryProvider = Provider<StatsRepository>((ref) => StatsRepository(ref.watch(appDatabaseProvider)));

final statsCalculatorProvider = StreamProvider<StatsCalculator>((ref) {
  final playerId = ref.watch(activePlayerProvider)?.id;
  if (playerId == null) return const Stream.empty();
  return ref.watch(statsRepositoryProvider).watchCalculator(playerId);
});

final goalsProvider = StreamProvider<List<GoalRow>>((ref) {
  final playerId = ref.watch(activePlayerProvider)?.id;
  if (playerId == null) return const Stream.empty();
  return ref.watch(statsRepositoryProvider).watchGoals(playerId);
});

final goalProgressProvider = Provider<List<GoalProgress>>((ref) {
  final calc = ref.watch(statsCalculatorProvider).value;
  final goals = ref.watch(goalsProvider).value;
  if (calc == null || goals == null) return const [];
  return goalProgress(goals, calc);
});
