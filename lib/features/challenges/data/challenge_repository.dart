import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/challenge.dart';

/// Speichert das beste Ergebnis je Challenge und Profil.
class ChallengeRepository {
  ChallengeRepository(this.db);
  final AppDatabase db;

  static ChallengeBest _best(ChallengeResultRow r) => ChallengeBest(
        challengeId: r.challengeId,
        stars: r.stars,
        best: r.best,
        attempts: r.attempts,
        achievedAt: r.achievedAt,
      );

  Stream<List<ChallengeBest>> watchResults(int playerId) =>
      (db.select(db.challengeResults)..where((r) => r.playerId.equals(playerId)))
          .watch()
          .map((rows) => [for (final r in rows) _best(r)]);

  Future<List<ChallengeBest>> results(int playerId) async =>
      [for (final r in await (db.select(db.challengeResults)..where((r) => r.playerId.equals(playerId))).get()) _best(r)];

  Future<ChallengeBest?> result(int playerId, String challengeId) async {
    final row = await (db.select(db.challengeResults)
          ..where((r) => r.playerId.equals(playerId) & r.challengeId.equals(challengeId)))
        .getSingleOrNull();
    return row == null ? null : _best(row);
  }

  /// Speichert einen regulär beendeten Versuch. Sterne und Bestwert werden
  /// nur verbessert, nie verschlechtert. Gibt das vorherige Ergebnis zurück.
  Future<ChallengeBest?> record(int playerId, Challenge challenge, {required int stars, num? score, DateTime? at}) =>
      db.transaction(() async {
        final now = at ?? DateTime.now();
        final previous = await result(playerId, challenge.id);
        if (previous == null) {
          await db.into(db.challengeResults).insert(ChallengeResultsCompanion.insert(
                playerId: playerId,
                challengeId: challenge.id,
                stars: Value(stars),
                best: Value(score?.toDouble()),
                attempts: const Value(1),
                achievedAt: now,
                updatedAt: now,
              ));
          return null;
        }
        final moreStars = stars > previous.stars;
        final betterScore = score != null && challenge.better(score, previous.best);
        await (db.update(db.challengeResults)
              ..where((r) => r.playerId.equals(playerId) & r.challengeId.equals(challenge.id)))
            .write(ChallengeResultsCompanion(
          stars: Value(moreStars ? stars : previous.stars),
          best: Value((betterScore ? score : previous.best)?.toDouble()),
          attempts: Value(previous.attempts + 1),
          achievedAt: Value(moreStars || betterScore ? now : previous.achievedAt),
          updatedAt: Value(now),
        ));
        return previous;
      });
}

final challengeRepositoryProvider = Provider<ChallengeRepository>((ref) => ChallengeRepository(ref.watch(appDatabaseProvider)));
