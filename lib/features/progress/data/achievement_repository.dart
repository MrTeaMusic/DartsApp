import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/achievements.dart';

/// Speichert, wann Erfolgs-Stufen freigeschaltet wurden.
class AchievementRepository {
  AchievementRepository(this.db);
  final AppDatabase db;

  Stream<List<AchievementRow>> watchUnlocks(int playerId) =>
      (db.select(db.achievements)..where((a) => a.playerId.equals(playerId))).watch();

  Future<List<AchievementRow>> unlocks(int playerId) =>
      (db.select(db.achievements)..where((a) => a.playerId.equals(playerId))).get();

  /// Legt fehlende Stufen an ([tiers]: Schlüssel aus [tierKey] → Datum).
  /// Vorhandene bleiben unverändert. Gibt die Zahl neuer Zeilen zurück.
  Future<int> addUnlocks(int playerId, Map<String, DateTime> tiers) async {
    if (tiers.isEmpty) return 0;
    final existing = {for (final r in await unlocks(playerId)) tierKey(r.achievementId, r.tier)};
    final missing = tiers.entries.where((e) => !existing.contains(e.key)).toList();
    if (missing.isEmpty) return 0;
    await db.batch((b) {
      for (final e in missing) {
        final i = e.key.lastIndexOf('#');
        b.insert(
          db.achievements,
          AchievementsCompanion.insert(
            playerId: playerId,
            achievementId: e.key.substring(0, i),
            tier: int.parse(e.key.substring(i + 1)),
            unlockedAt: e.value,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
    return missing.length;
  }
}

final achievementRepositoryProvider = Provider<AchievementRepository>((ref) => AchievementRepository(ref.watch(appDatabaseProvider)));
