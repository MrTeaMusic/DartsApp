import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../stats/domain/stats_calculator.dart';
import '../domain/quiz_answer.dart';
import '../domain/quiz_config.dart';

/// Persönliche Bestwerte im Quiz.
class QuizBests {
  const QuizBests({this.timedCorrect, this.bestStreak, this.fastestSeconds, this.sessions = 0});

  /// Meiste richtige Antworten in einem vollen Durchgang „Zeit“.
  final int? timedCorrect;

  /// Längste Serie richtiger Antworten (beide Modi).
  final int? bestStreak;

  /// Schnellste durchschnittliche Antwortzeit (Durchgänge mit mindestens
  /// [minAnswersForPace] Antworten und mindestens der Hälfte richtig).
  final double? fastestSeconds;
  final int sessions;

  static const int minAnswersForPace = 10;

  static QuizBests of(Iterable<SessionRow> rows) {
    int? timed;
    int? streak;
    double? fastest;
    var n = 0;
    for (final r in rows) {
      n++;
      final m = StatsCalculator.metricsOf(r);
      final config = QuizConfig.fromJson(StatsCalculator.decode(r.configJson));
      final correct = m['correct']?.toInt();
      if (config.timed && r.finished && correct != null && (timed == null || correct > timed)) timed = correct;
      final s = m['bestStreak']?.toInt();
      if (s != null && s > 0 && (streak == null || s > streak)) streak = s;
      final answered = m['answered'] ?? 0;
      final rate = m['correctRate'] ?? 0;
      final avg = m['avgSeconds']?.toDouble();
      if (avg != null && answered >= minAnswersForPace && rate >= 0.5 && (fastest == null || avg < fastest)) fastest = avg;
    }
    return QuizBests(timedCorrect: timed, bestStreak: streak, fastestSeconds: fastest, sessions: n);
  }
}

/// Speichert Quiz-Durchgänge als Sessions mit eigener Spiel-ID, aber ohne
/// Würfe: Verlauf und Statistik zeigen sie, Wurf-Kennzahlen (Average,
/// Checkout-Quote, Darts) bleiben unberührt.
class QuizRepository {
  QuizRepository(this.db);
  final AppDatabase db;

  /// Legt die abgeschlossene Session an; ohne Antworten passiert nichts.
  /// Gibt die Session-ID zurück (`null` ohne Antworten).
  Future<int?> save({
    required int playerId,
    required QuizConfig config,
    required List<QuizAnswer> answers,
    required DateTime startedAt,
    required DateTime endedAt,
    required bool finished,
    int seed = 0,
  }) async {
    if (answers.isEmpty) return null;
    return db.into(db.sessions).insert(SessionsCompanion.insert(
          playerId: playerId,
          gameId: checkoutQuizGameId,
          configJson: jsonEncode(config.toJson()),
          seed: seed,
          startedAt: startedAt,
          endedAt: Value(endedAt),
          updatedAt: Value(endedAt),
          finished: Value(finished),
          resultJson: Value(jsonEncode(quizResult(config, answers).toJson())),
          // Keine Würfe: die Dartzahl bleibt 0.
        ));
  }

  Future<List<SessionRow>> _sessions(int playerId) => (db.select(db.sessions)
        ..where((s) =>
            s.playerId.equals(playerId) &
            s.gameId.equals(checkoutQuizGameId) &
            s.endedAt.isNotNull() &
            s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.startedAt), (s) => OrderingTerm.asc(s.id)]))
      .get();

  /// Alle bisherigen Antworten des Spielers, älteste zuerst (für die
  /// Wiederholung schwacher Reste).
  Future<List<QuizAnswer>> history(int playerId) async => [
        for (final r in await _sessions(playerId)) ...quizAnswersOf(StatsCalculator.decode(r.resultJson)),
      ];

  Future<QuizBests> bests(int playerId) async => QuizBests.of(await _sessions(playerId));

  /// Bestwerte und Antworten mit einer Abfrage.
  Future<({QuizBests bests, List<QuizAnswer> history})> load(int playerId) async {
    final rows = await _sessions(playerId);
    return (
      bests: QuizBests.of(rows),
      history: [for (final r in rows) ...quizAnswersOf(StatsCalculator.decode(r.resultJson))],
    );
  }
}

final quizRepositoryProvider = Provider<QuizRepository>((ref) => QuizRepository(ref.watch(appDatabaseProvider)));
