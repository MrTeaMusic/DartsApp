import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../sync/data/sync_store.dart';

export '../../sync/data/sync_store.dart' show MergeResult;

/// Ergebnis eines Imports.
typedef ImportResult = MergeResult;

/// Die Datei ist kein DartLab-Backup oder beschädigt.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => 'BackupFormatException: $message';
}

/// Export und Import aller Daten.
///
/// * JSON: vollständige Sicherung (Profile, Sessions, Würfe, Ziele,
///   eigene Trainingspläne), lässt
///   sich wieder importieren.
/// * CSV: Würfe bzw. Sessions als Tabelle für Excel/Numbers, nur Export.
class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  static const String format = 'dartlab-backup';

  /// 2: geräteübergreifende IDs (`uid`), Zeiten als ISO-Text, gelöschte
  /// Profile und Ziele als Markierung.
  /// 3: zusätzlich eigene Trainingspläne (`plans`).
  /// Versionen 1 und 2 werden weiter gelesen.
  static const int version = 3;

  // ---------------------------------------------------------------- JSON

  /// Alle Daten, oder nur die eines Profils.
  Future<Map<String, Object?>> exportData({int? playerId, DateTime? now}) async {
    final bundle = await SyncStore(db).bundle(playerId: playerId, includeOpen: true);
    return {
      'format': format,
      'version': version,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      ...bundle.toJson(),
    };
  }

  Expression<bool> _player(GeneratedColumn<int> column, int? playerId) =>
      playerId == null ? const Constant(true) : column.equals(playerId);

  Future<String> exportJson({int? playerId}) async =>
      const JsonEncoder.withIndent('  ').convert(await exportData(playerId: playerId));

  /// Importiert ein JSON-Backup und führt es mit den vorhandenen Daten
  /// zusammen (wie beim Abgleich, siehe [SyncStore]). Bereits vorhandene
  /// Sessions werden übersprungen.
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
    final v = decoded['version'];
    if (v is! int || v > version) {
      throw BackupFormatException('Unbekannte Version: $v');
    }
    try {
      return await SyncStore(db).merge(SyncBundle.fromJson(decoded));
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
