import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../dart_source/domain/dart_event.dart';
import '../domain/engine/game_display.dart';
import '../domain/games/checkout/checkout_training.dart';

/// Kurzinfo einer gespielten Session, z. B. für "Zuletzt gespielt".
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.gameId,
    required this.startedAt,
    required this.finished,
    required this.dartCount,
    required this.metrics,
  });

  final int id;
  final String gameId;
  final DateTime startedAt;
  final bool finished;
  final int dartCount;
  final Map<String, num> metrics;
}

/// Speichert Sessions und Würfe. Einzige Stelle, die Spiele mit der
/// Datenbank verbindet.
class GameRepository {
  GameRepository(this.db);

  final AppDatabase db;

  Future<int> defaultPlayerId() async {
    final row = await (db.select(db.players)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.desc(p.isDefault), (p) => OrderingTerm.asc(p.id)])
          ..limit(1))
        .getSingleOrNull();
    if (row != null) return row.id;
    return db.insertDefaultPlayer();
  }

  Future<int> startSession({
    required int playerId,
    required String gameId,
    required Map<String, Object?> config,
    required int seed,
    DateTime? startedAt,
  }) =>
      db.into(db.sessions).insert(SessionsCompanion.insert(
            playerId: playerId,
            gameId: gameId,
            configJson: jsonEncode(config),
            seed: seed,
            startedAt: startedAt ?? DateTime.now(),
          ));

  Future<int> addThrow({
    required int sessionId,
    required int playerId,
    required String gameId,
    required int seq,
    required int visitIndex,
    required bool counted,
    required DartThrow dart,
  }) =>
      db.into(db.throws).insert(_companion(
            sessionId: sessionId,
            playerId: playerId,
            gameId: gameId,
            seq: seq,
            visitIndex: visitIndex,
            counted: counted,
            dart: dart,
          ));

  /// Ersetzt alle Würfe einer Session (nach Rückgängig/Korrektur).
  Future<void> replaceThrows({
    required int sessionId,
    required int playerId,
    required String gameId,
    required List<({DartThrow dart, int visitIndex, bool counted})> darts,
  }) =>
      db.transaction(() async {
        await (db.delete(db.throws)..where((t) => t.sessionId.equals(sessionId))).go();
        await db.batch((b) => b.insertAll(db.throws, [
              for (var i = 0; i < darts.length; i++)
                _companion(
                  sessionId: sessionId,
                  playerId: playerId,
                  gameId: gameId,
                  seq: i,
                  visitIndex: darts[i].visitIndex,
                  counted: darts[i].counted,
                  dart: darts[i].dart,
                ),
            ]));
      });

  ThrowsCompanion _companion({
    required int sessionId,
    required int playerId,
    required String gameId,
    required int seq,
    required int visitIndex,
    required bool counted,
    required DartThrow dart,
  }) =>
      ThrowsCompanion.insert(
        sessionId: sessionId,
        playerId: playerId,
        gameId: gameId,
        seq: seq,
        visitIndex: visitIndex,
        counted: Value(counted),
        segment: dart.segment.name,
        number: dart.segment.number,
        multiplier: dart.segment.multiplier,
        bed: dart.segment.bed.name,
        score: dart.segment.score,
        x: Value(dart.position?.x),
        y: Value(dart.position?.y),
        source: dart.source.name,
        timestamp: dart.timestamp,
        rawJson: Value(dart.raw == null ? null : jsonEncode(dart.raw)),
      );

  /// Schließt eine Session ab. Ohne Würfe wird sie gelöscht.
  Future<void> endSession(int sessionId, {required GameResult result, required bool finished, DateTime? endedAt}) async {
    final count = await _throwCount(sessionId);
    if (count == 0) {
      await (db.delete(db.sessions)..where((s) => s.id.equals(sessionId))).go();
      return;
    }
    await (db.update(db.sessions)..where((s) => s.id.equals(sessionId))).write(SessionsCompanion(
      endedAt: Value(endedAt ?? DateTime.now()),
      finished: Value(finished),
      resultJson: Value(jsonEncode(result.toJson())),
      dartCount: Value(count),
    ));
  }

  Future<int> _throwCount(int sessionId) async {
    final c = db.throws.id.count();
    final row = await (db.selectOnly(db.throws)
          ..addColumns([c])
          ..where(db.throws.sessionId.equals(sessionId)))
        .getSingle();
    return row.read(c) ?? 0;
  }

  /// Löscht eine abgeschlossene Session samt Würfen, z. B. eine falsch
  /// gespeicherte. Die Zeile bleibt als Markierung (`deletedAt`) stehen, damit
  /// der Abgleich das Löschen an die anderen Geräte weitergibt.
  Future<void> deleteSession(int sessionId, {DateTime? at}) => db.transaction(() async {
        await (db.delete(db.throws)..where((t) => t.sessionId.equals(sessionId))).go();
        await (db.update(db.sessions)..where((s) => s.id.equals(sessionId)))
            .write(SessionsCompanion(deletedAt: Value(at ?? DateTime.now()), dartCount: const Value(0)));
      });

  Future<List<ThrowRow>> throwsOf(int sessionId) =>
      (db.select(db.throws)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
          .get();

  /// Abgeschlossene Sessions, neueste zuerst.
  Stream<List<SessionSummary>> watchRecent({int limit = 20, int? playerId}) {
    final q = db.select(db.sessions)
      ..where((s) =>
          s.endedAt.isNotNull() &
          s.deletedAt.isNull() &
          (playerId == null ? const Constant(true) : s.playerId.equals(playerId)))
      ..orderBy([(s) => OrderingTerm.desc(s.startedAt)])
      ..limit(limit);
    return q.watch().map((rows) => [for (final r in rows) _summary(r)]);
  }

  /// Bester bisheriger Wert einer Kennzahl für ein Spiel (für Rekorde).
  Future<num?> bestMetric(String gameId, String metric, {bool higherIsBetter = true}) async {
    final rows = await (db.select(db.sessions)
          ..where((s) => s.gameId.equals(gameId) & s.finished.equals(true) & s.deletedAt.isNull()))
        .get();
    num? best;
    for (final r in rows) {
      final v = _summary(r).metrics[metric];
      if (v == null) continue;
      if (best == null || (higherIsBetter ? v > best : v < best)) best = v;
    }
    return best;
  }

  /// Checkout-Werte mit der schlechtesten Quote (mindestens [minAttempts]
  /// Versuche), schlechteste zuerst.
  Future<List<int>> weakCheckoutTargets({int limit = 15, int minAttempts = 2, int? playerId}) async {
    final rows = await (db.select(db.sessions)
          ..where((s) =>
              s.gameId.equals(CheckoutTraining.id) &
              s.resultJson.isNotNull() &
              s.deletedAt.isNull() &
              (playerId == null ? const Constant(true) : s.playerId.equals(playerId))))
        .get();
    final tries = <int, int>{};
    final hits = <int, int>{};
    for (final r in rows) {
      final decoded = _decode(r.resultJson);
      final details = decoded['details'];
      final list = details is Map ? details['attempts'] : null;
      if (list is! List) continue;
      for (final a in list) {
        final attempt = CheckoutAttempt.fromJson(a);
        if (attempt == null) continue;
        tries[attempt.target] = (tries[attempt.target] ?? 0) + 1;
        if (attempt.success) hits[attempt.target] = (hits[attempt.target] ?? 0) + 1;
      }
    }
    final eligible = tries.entries.where((e) => e.value >= minAttempts).toList()
      ..sort((a, b) {
        final ra = (hits[a.key] ?? 0) / a.value;
        final rb = (hits[b.key] ?? 0) / b.value;
        final byRate = ra.compareTo(rb);
        return byRate != 0 ? byRate : b.value.compareTo(a.value);
      });
    return [for (final e in eligible.take(limit)) e.key];
  }

  SessionSummary _summary(SessionRow r) {
    final decoded = _decode(r.resultJson);
    final m = decoded['metrics'];
    return SessionSummary(
      id: r.id,
      gameId: r.gameId,
      startedAt: r.startedAt,
      finished: r.finished,
      dartCount: r.dartCount,
      metrics: m is Map ? {for (final e in m.entries) if (e.value is num) '${e.key}': e.value as num} : const {},
    );
  }

  static Map<String, Object?> _decode(String? json) {
    if (json == null) return const {};
    try {
      final v = jsonDecode(json);
      return v is Map<String, Object?> ? v : const {};
    } on FormatException {
      return const {};
    }
  }
}

final gameRepositoryProvider = Provider<GameRepository>((ref) => GameRepository(ref.watch(appDatabaseProvider)));
