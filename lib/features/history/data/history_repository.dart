import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../games/data/game_repository.dart';
import '../../profiles/presentation/active_player.dart';
import '../domain/session_history.dart';

/// Liest abgeschlossene Sessions für den Spielverlauf. Gelöscht wird über
/// [GameRepository.deleteSession].
class HistoryRepository {
  HistoryRepository(this.db);
  final AppDatabase db;

  /// Abgeschlossene, nicht gelöschte Sessions eines Profils, neueste zuerst.
  Stream<List<SessionRow>> watchSessions(int playerId) => (db.select(db.sessions)
        ..where((s) => s.playerId.equals(playerId) & s.endedAt.isNotNull() & s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.desc(s.startedAt), (s) => OrderingTerm.desc(s.id)]))
      .watch();

  Future<SessionRow?> session(int id) =>
      (db.select(db.sessions)..where((s) => s.id.equals(id) & s.deletedAt.isNull())).getSingleOrNull();

  Future<String> playerName(int playerId) async =>
      (await (db.select(db.players)..where((p) => p.id.equals(playerId))).getSingleOrNull())?.name ?? '';
}

final historyRepositoryProvider = Provider<HistoryRepository>((ref) => HistoryRepository(ref.watch(appDatabaseProvider)));

/// Verlauf des aktiven Profils.
final historyProvider = StreamProvider<List<HistoryEntry>>((ref) {
  final playerId = ref.watch(activePlayerProvider)?.id;
  if (playerId == null) return const Stream.empty();
  return ref
      .watch(historyRepositoryProvider)
      .watchSessions(playerId)
      .map((rows) => [for (final r in rows) HistoryEntry(r)]);
});

/// Gewählter Filter der Verlaufsliste.
final historyFilterProvider = NotifierProvider<HistoryFilterChoice, HistoryFilter>(HistoryFilterChoice.new);

class HistoryFilterChoice extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => HistoryFilter.all;
  void set(HistoryFilter f) => state = f;
}

/// Detailansicht einer Session; `null`, wenn es sie nicht (mehr) gibt.
final sessionDetailProvider = FutureProvider.autoDispose.family<SessionDetail?, int>((ref, id) async {
  final repo = ref.watch(historyRepositoryProvider);
  final row = await repo.session(id);
  if (row == null) return null;
  final throws = await ref.watch(gameRepositoryProvider).throwsOf(id);
  return buildSessionDetail(row, throws, playerName: await repo.playerName(row.playerId));
});
