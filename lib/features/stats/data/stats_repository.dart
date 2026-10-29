import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../profiles/presentation/active_player.dart';
import '../../progress/domain/achievement_tracker.dart';
import '../domain/goals.dart';
import '../domain/stats_calculator.dart';

/// Liest die Daten für Statistiken und verwaltet Ziele.
class StatsRepository {
  StatsRepository(this.db);
  final AppDatabase db;

  /// Neu berechnen, sobald sich abgeschlossene Sessions des Spielers ändern.
  ///
  /// Würfe werden nur für neue oder geänderte Sessions geladen (siehe
  /// [CalculatorLoader]); ändert sich nichts (z. B. beim Start eines Spiels,
  /// dessen Session noch offen ist), kommt kein neuer Rechner.
  Stream<StatsCalculator> watchCalculator(int playerId) {
    final q = db.select(db.sessions)
      ..where((s) => s.playerId.equals(playerId) & s.endedAt.isNotNull() & s.deletedAt.isNull());
    final loader = CalculatorLoader(db, playerId);
    return q.watch().asyncMap(loader.next).where((c) => c != null).cast<StatsCalculator>();
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

/// Kennung der gespeicherten Würfe einer Session. Würfe werden nur eingefügt
/// oder gelöscht, nie geändert, und ihre IDs werden nicht wiederverwendet:
/// Gleiche Anzahl und gleiche kleinste und größte ID heißt gleiche Würfe.
typedef _ThrowsKey = ({int count, int minId, int maxId});

/// Baut den [StatsCalculator] eines Spielers Schritt für Schritt: Die Würfe
/// abgeschlossener Sessions ändern sich nicht mehr, deshalb werden sie nur
/// einmal geladen und danach nur die neuer oder geänderter Sessions.
///
/// Vorher wurden nach jeder Änderung an den Sessions (auch beim Start eines
/// Spiels) alle Würfe des Spielers neu gelesen, und das Umwandeln der Zeilen
/// hielt die Oberfläche bei langer Geschichte spürbar an.
class CalculatorLoader {
  CalculatorLoader(this.db, this.playerId);
  final AppDatabase db;
  final int playerId;

  final Map<int, ({SessionRow row, _ThrowsKey key, List<ThrowRow> throws})> _loaded = {};
  StatsCalculator? _last;

  /// Sessions je Abfrage. Die Zeilen einer Abfrage werden am Stück in
  /// Dart-Objekte umgewandelt; kleine Stücke halten die Oberfläche beim
  /// ersten Laden (alle Würfe) flüssig: Die Antwort jeder Abfrage kommt aus
  /// dem Datenbank-Isolat, dazwischen kommen Frames dran.
  static const int _chunk = 25;

  /// Rechner für die abgeschlossenen Sessions [sessions]; `null`, wenn sich
  /// seit dem letzten Rechner nichts geändert hat (und der Tag derselbe ist,
  /// denn der Rechner rechnet Zeiträume ab heute).
  Future<StatsCalculator?> next(List<SessionRow> sessions) async {
    final keys = await _throwsKeys();
    const none = (count: 0, minId: 0, maxId: 0);
    final stale = <int>[];
    for (final s in sessions) {
      final have = _loaded[s.id];
      if (have == null || have.row != s || have.key != (keys[s.id] ?? none)) stale.add(s.id);
    }
    final now = DateTime.now();
    final last = _last;
    if (stale.isEmpty &&
        last != null &&
        _loaded.length == sessions.length &&
        StatsCalculator.dayOf(last.now) == StatsCalculator.dayOf(now)) {
      return null;
    }
    final fresh = <int, List<ThrowRow>>{for (final id in stale) id: []};
    for (var i = 0; i < stale.length; i += _chunk) {
      final ids = stale.sublist(i, i + _chunk > stale.length ? stale.length : i + _chunk);
      for (final t in await _throwsOf(ids)) {
        fresh[t.sessionId]!.add(t);
      }
    }
    final ids = {for (final s in sessions) s.id};
    _loaded.removeWhere((id, _) => !ids.contains(id));
    for (final s in sessions) {
      final throws = fresh[s.id];
      if (throws != null) _loaded[s.id] = (row: s, key: keys[s.id] ?? none, throws: throws);
    }
    final staleIds = stale.toSet();
    return _last = StatsCalculator(
      sessions: sessions,
      throws: [for (final s in sessions) ..._loaded[s.id]!.throws],
      now: now,
      previous: last,
      unchanged: {for (final id in ids) if (!staleIds.contains(id)) id},
    );
  }

  /// Spalten der Würfe ohne `raw_json`: Die Rohdaten (bei Autodarts je Dart
  /// ein JSON-Text) braucht keine Auswertung, sie würden das Laden aber etwa
  /// verdoppeln. [ThrowRow.rawJson] bleibt hier deshalb `null`.
  late final String _columns = [
    for (final c in db.throws.$columns)
      if (c.name != db.throws.rawJson.name) c.name,
  ].join(', ');

  /// Würfe der Sessions [ids] des Spielers, nach ID sortiert.
  Future<List<ThrowRow>> _throwsOf(List<int> ids) async {
    final rows = await db.customSelect(
      'SELECT $_columns FROM throws WHERE player_id = ? AND session_id IN (${List.filled(ids.length, '?').join(', ')}) '
      'ORDER BY id',
      variables: [Variable<int>(playerId), for (final id in ids) Variable<int>(id)],
      readsFrom: {db.throws},
    ).get();
    return [for (final r in rows) db.throws.map(r.data)];
  }

  /// Anzahl, kleinste und größte ID der Würfe je Session des Spielers.
  Future<Map<int, _ThrowsKey>> _throwsKeys() async {
    final t = db.throws;
    final count = t.id.count();
    final minId = t.id.min();
    final maxId = t.id.max();
    final rows = await (db.selectOnly(t)
          ..addColumns([t.sessionId, count, minId, maxId])
          ..where(t.playerId.equals(playerId))
          ..groupBy([t.sessionId]))
        .get();
    return {
      for (final r in rows)
        r.read(t.sessionId)!: (count: r.read(count) ?? 0, minId: r.read(minId) ?? 0, maxId: r.read(maxId) ?? 0),
    };
  }
}

final statsRepositoryProvider = Provider<StatsRepository>((ref) => StatsRepository(ref.watch(appDatabaseProvider)));

final statsCalculatorProvider = StreamProvider<StatsCalculator>((ref) {
  final playerId = ref.watch(activePlayerProvider)?.id;
  if (playerId == null) return const Stream.empty();
  // Die Erfolge und das Tagesziel lesen jeden neuen Rechner sofort; ihre
  // Auswertung je Session wird vorher in kleinen Stücken erledigt, damit der
  // erste Rechner nach dem Start die Oberfläche nicht am Stück anhält.
  return ref.watch(statsRepositoryProvider).watchCalculator(playerId).asyncMap((calc) async {
    await AchievementTracker.warmUp(calc);
    return calc;
  });
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

/// Haus-Elo des aktiven Profils, aus demselben Rechner wie die Statistik
/// (die Sessions und ihre Ergebnisse sind dort schon geladen und
/// zwischengespeichert). `null`, solange der Rechner noch lädt. Die Rechnung
/// läuft erst, wenn jemand sie liest, und ist ein Durchlauf über die Matches.
final houseEloProvider = Provider<HouseEloReport?>((ref) => ref.watch(statsCalculatorProvider).value?.houseElo);
