import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';

/// Ergebnis eines Imports.
class ImportResult {
  const ImportResult({required this.players, required this.sessions, required this.throws, required this.goals, required this.skipped});
  final int players;
  final int sessions;
  final int throws;
  final int goals;

  /// Sessions, die schon vorhanden waren.
  final int skipped;
}

/// Die Datei ist kein DartLab-Backup oder beschädigt.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => 'BackupFormatException: $message';
}

/// Export und Import aller Daten.
///
/// * JSON: vollständige Sicherung (Profile, Sessions, Würfe, Ziele), lässt
///   sich wieder importieren.
/// * CSV: Würfe bzw. Sessions als Tabelle für Excel/Numbers, nur Export.
class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  static const String format = 'dartlab-backup';
  static const int version = 1;

  // ---------------------------------------------------------------- JSON

  /// Alle Daten, oder nur die eines Profils.
  Future<Map<String, Object?>> exportData({int? playerId, DateTime? now}) async {
    final players = await (db.select(db.players)..where((p) => _player(p.id, playerId))).get();
    final sessions = await (db.select(db.sessions)
          ..where((s) => _player(s.playerId, playerId))
          ..orderBy([(s) => OrderingTerm.asc(s.id)]))
        .get();
    final throws = await (db.select(db.throws)
          ..where((t) => _player(t.playerId, playerId))
          ..orderBy([(t) => OrderingTerm.asc(t.sessionId), (t) => OrderingTerm.asc(t.seq)]))
        .get();
    final goals = await (db.select(db.goals)..where((g) => _player(g.playerId, playerId))).get();
    return {
      'format': format,
      'version': version,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'players': [for (final p in players) p.toJson()],
      'sessions': [for (final s in sessions) s.toJson()],
      'throws': [for (final t in throws) t.toJson()],
      'goals': [for (final g in goals) g.toJson()],
    };
  }

  Expression<bool> _player(GeneratedColumn<int> column, int? playerId) =>
      playerId == null ? const Constant(true) : column.equals(playerId);

  Future<String> exportJson({int? playerId}) async =>
      const JsonEncoder.withIndent('  ').convert(await exportData(playerId: playerId));

  /// Importiert ein JSON-Backup und führt es mit den vorhandenen Daten
  /// zusammen. Profile werden über den Namen zugeordnet, bereits vorhandene
  /// Sessions (gleiches Profil, Spiel, Startzeit und Seed) übersprungen.
  Future<ImportResult> importJson(String text) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw BackupFormatException('Kein gültiges JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != format) {
      throw const BackupFormatException('Keine DartLab-Sicherung');
    }
    final Map<String, dynamic> data = decoded;
    final v = data['version'];
    if (v is! int || v > version) {
      throw BackupFormatException('Unbekannte Version: $v');
    }
    List<Map<String, dynamic>> list(String key) {
      final l = data[key];
      if (l is! List) return const [];
      return [for (final e in l) if (e is Map<String, dynamic>) e];
    }

    try {
      return await db.transaction(() async {
        final players = [for (final j in list('players')) Player.fromJson(j)];
        final sessions = [for (final j in list('sessions')) SessionRow.fromJson(j)];
        final throws = [for (final j in list('throws')) ThrowRow.fromJson(j)];
        final goals = [for (final j in list('goals')) GoalRow.fromJson(j)];

        // Profile über den Namen zuordnen.
        final existing = await db.select(db.players).get();
        final playerMap = <int, int>{};
        var newPlayers = 0;
        for (final p in players) {
          final match = existing.where((e) => e.name == p.name).firstOrNull;
          if (match != null) {
            playerMap[p.id] = match.id;
          } else {
            playerMap[p.id] = await db.into(db.players).insert(PlayersCompanion.insert(name: p.name, createdAt: p.createdAt));
            newPlayers++;
          }
        }

        // Sessions, Duplikate überspringen.
        final sessionMap = <int, int>{};
        var skipped = 0;
        for (final s in sessions) {
          final player = playerMap[s.playerId];
          if (player == null) continue;
          final dup = await (db.select(db.sessions)
                ..where((x) =>
                    x.playerId.equals(player) &
                    x.gameId.equals(s.gameId) &
                    x.startedAt.equals(s.startedAt) &
                    x.seed.equals(s.seed))
                ..limit(1))
              .getSingleOrNull();
          if (dup != null) {
            skipped++;
            continue;
          }
          sessionMap[s.id] = await db.into(db.sessions).insert(
                s.toCompanion(true).copyWith(id: const Value.absent(), playerId: Value(player)),
              );
        }

        var newThrows = 0;
        await db.batch((b) {
          for (final t in throws) {
            final session = sessionMap[t.sessionId];
            final player = playerMap[t.playerId];
            if (session == null || player == null) continue;
            b.insert(
              db.throws,
              t.toCompanion(true).copyWith(id: const Value.absent(), sessionId: Value(session), playerId: Value(player)),
            );
            newThrows++;
          }
        });

        // Ziele nur übernehmen, wenn das Profil diese Art noch nicht hat.
        var newGoals = 0;
        for (final g in goals) {
          final player = playerMap[g.playerId];
          if (player == null) continue;
          final has = await (db.select(db.goals)..where((x) => x.playerId.equals(player) & x.kind.equals(g.kind))).get();
          if (has.isNotEmpty) continue;
          await db.into(db.goals).insert(g.toCompanion(true).copyWith(id: const Value.absent(), playerId: Value(player)));
          newGoals++;
        }

        return ImportResult(
          players: newPlayers,
          sessions: sessionMap.length,
          throws: newThrows,
          goals: newGoals,
          skipped: skipped,
        );
      });
    } on TypeError catch (e) {
      throw BackupFormatException('Beschädigte Daten: $e');
    }
  }

  // ----------------------------------------------------------------- CSV

  /// Alle Würfe als CSV (Komma-getrennt, UTF-8 mit BOM für Excel).
  Future<String> exportThrowsCsv({int? playerId}) async {
    final players = {for (final p in await db.select(db.players).get()) p.id: p.name};
    final throws = await (db.select(db.throws)
          ..where((t) => _player(t.playerId, playerId))
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp), (t) => OrderingTerm.asc(t.seq)]))
        .get();
    return csv(
      ['timestamp', 'player', 'game', 'session', 'visit', 'dart', 'segment', 'number', 'multiplier', 'score', 'counted', 'x', 'y', 'source'],
      [
        for (final t in throws)
          [
            t.timestamp.toIso8601String(),
            players[t.playerId] ?? '',
            t.gameId,
            t.sessionId,
            t.visitIndex + 1,
            t.seq + 1,
            t.segment,
            t.number,
            t.multiplier,
            t.score,
            t.counted ? 1 : 0,
            t.x,
            t.y,
            t.source,
          ],
      ],
    );
  }

  /// Alle Sessions mit ihren Kennzahlen als CSV.
  Future<String> exportSessionsCsv({int? playerId}) async {
    final players = {for (final p in await db.select(db.players).get()) p.id: p.name};
    final sessions = await (db.select(db.sessions)
          ..where((s) => _player(s.playerId, playerId) & s.endedAt.isNotNull())
          ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]))
        .get();
    final rows = <List<Object?>>[];
    final metricKeys = <String>{};
    final metrics = <Map<String, Object?>>[];
    for (final s in sessions) {
      Map<String, Object?> m = const {};
      try {
        final d = jsonDecode(s.resultJson ?? '{}');
        if (d is Map && d['metrics'] is Map) m = Map<String, Object?>.from(d['metrics'] as Map);
      } on FormatException {
        // Kaputte Ergebnisse als leer behandeln.
      }
      metrics.add(m);
      metricKeys.addAll(m.keys);
    }
    final keys = metricKeys.toList()..sort();
    for (final (i, s) in sessions.indexed) {
      rows.add([
        s.id,
        s.startedAt.toIso8601String(),
        s.endedAt?.toIso8601String(),
        players[s.playerId] ?? '',
        s.gameId,
        s.finished ? 1 : 0,
        s.dartCount,
        s.configJson,
        for (final k in keys) metrics[i][k],
      ]);
    }
    return csv(['session', 'started', 'ended', 'player', 'game', 'finished', 'darts', 'config', ...keys], rows);
  }

  /// Baut CSV nach RFC 4180 mit BOM.
  static String csv(List<String> header, List<List<Object?>> rows) {
    String cell(Object? v) {
      if (v == null) return '';
      final s = v is double ? (v == v.roundToDouble() ? v.toStringAsFixed(1) : '$v') : '$v';
      if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
      return s;
    }

    final b = StringBuffer('﻿')..write(header.map(cell).join(','));
    for (final r in rows) {
      b
        ..write('\r\n')
        ..write(r.map(cell).join(','));
    }
    b.write('\r\n');
    return b.toString();
  }
}

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(ref.watch(appDatabaseProvider)));
