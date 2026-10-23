import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../autodarts_live/domain/live_stats.dart';
import '../../games/data/game_repository.dart';
import '../domain/import_plan.dart';

/// Ausgang des Speicherns.
enum ImportSaveStatus {
  /// Neue Session angelegt.
  imported,

  /// Vorhandene Session desselben Matches ersetzt (nur auf ausdrücklichen
  /// Wunsch).
  replaced,

  /// Dieses Match (Autodarts-Id) ist schon da, nichts geändert.
  duplicate,
}

class ImportSaveResult {
  const ImportSaveResult(this.status, this.sessionId, {this.overlap});

  final ImportSaveStatus status;
  final int sessionId;

  /// Eine Live-Aufzeichnung (Autodarts Live) aus demselben Zeitraum. Ihre
  /// Darts zählen zusätzlich zum Import, solange eine der beiden Sessions
  /// bleibt.
  final SessionRow? overlap;
}

/// Schreibt importierte Matches in die vorhandenen Tabellen: eine Session
/// `x01_live` mit den eigenen Darts, alles Weitere (Gegner, Legs, Aufnahmen
/// des Gegners) im Ergebnis. Kein eigenes Schema.
class AutodartsImportRepository {
  AutodartsImportRepository(this.db) : _games = GameRepository(db);

  final AppDatabase db;
  final GameRepository _games;

  /// Zeitpuffer für die Suche nach einer überschneidenden Live-Aufzeichnung.
  static const Duration overlapSlack = Duration(minutes: 10);

  /// Die Session, die zu diesem Autodarts-Match gehört (nicht gelöscht).
  Future<SessionRow?> findByMatchId(String matchId) async {
    final rows = await (db.select(db.sessions)
          ..where((s) => s.gameId.equals(importGameId) & s.deletedAt.isNull() & s.configJson.contains(matchId)))
        .get();
    for (final r in rows) {
      final config = _decode(r.configJson);
      final info = config['import'];
      if (info is Map && info['id'] == matchId) return r;
    }
    return null;
  }

  /// Eine mitgeschriebene Live-Session (kein Import) des Profils, die sich
  /// mit dem Match überschneidet.
  Future<SessionRow?> findLiveOverlap(ImportPlan plan, int playerId) async {
    final from = plan.startedAt.subtract(overlapSlack);
    final to = plan.endedAt.add(overlapSlack);
    final rows = await (db.select(db.sessions)
          ..where((s) =>
              s.playerId.equals(playerId) &
              s.deletedAt.isNull() &
              s.gameId.isIn([autodartsLiveGameId, autodartsLiveX01GameId]) &
              s.startedAt.isSmallerOrEqualValue(to)))
        .get();
    for (final r in rows) {
      if (_decode(r.configJson)['import'] is Map) continue;
      final end = r.endedAt ?? r.startedAt;
      if (!end.isBefore(from)) return r;
    }
    return null;
  }

  Future<ImportSaveResult> save(ImportPlan plan, {required int playerId, bool replace = false}) =>
      db.transaction(() async {
        final existing = await findByMatchId(plan.id);
        if (existing != null && !replace) return ImportSaveResult(ImportSaveStatus.duplicate, existing.id);

        final int sessionId;
        if (existing != null) {
          sessionId = existing.id;
          await (db.delete(db.throws)..where((t) => t.sessionId.equals(sessionId))).go();
          await (db.update(db.sessions)..where((s) => s.id.equals(sessionId))).write(SessionsCompanion(
            configJson: Value(jsonEncode(plan.config)),
            startedAt: Value(plan.startedAt),
          ));
        } else {
          sessionId = await _games.startSession(
            playerId: playerId,
            gameId: importGameId,
            config: plan.config,
            seed: 0,
            startedAt: plan.startedAt,
          );
        }
        final target = existing?.playerId ?? playerId;
        await db.batch((b) => b.insertAll(db.throws, [
              for (final (i, d) in plan.darts.indexed)
                ThrowsCompanion.insert(
                  sessionId: sessionId,
                  playerId: target,
                  gameId: importGameId,
                  seq: i,
                  visitIndex: d.visitIndex,
                  counted: Value(d.counted),
                  segment: d.segment.name,
                  number: d.segment.number,
                  multiplier: d.segment.multiplier,
                  bed: d.segment.bed.name,
                  score: d.segment.score,
                  x: Value(d.position?.x),
                  y: Value(d.position?.y),
                  source: importThrowSource,
                  timestamp: d.at,
                ),
            ]));
        await _games.endSession(sessionId, result: plan.result, finished: plan.finished, endedAt: plan.endedAt);
        final overlap = existing == null ? await findLiveOverlap(plan, target) : null;
        return ImportSaveResult(
          existing == null ? ImportSaveStatus.imported : ImportSaveStatus.replaced,
          sessionId,
          overlap: overlap,
        );
      });

  static Map<String, Object?> _decode(String json) {
    try {
      final v = jsonDecode(json);
      return v is Map<String, Object?> ? v : const {};
    } on FormatException {
      return const {};
    }
  }
}
