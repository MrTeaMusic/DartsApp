import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';

/// Spielerprofile anlegen, umbenennen, löschen.
class ProfileRepository {
  ProfileRepository(this.db);
  final AppDatabase db;

  static const int maxNameLength = 40;

  SimpleSelectStatement<$PlayersTable, Player> _active() => db.select(db.players)
    ..where((p) => p.deletedAt.isNull())
    ..orderBy([(p) => OrderingTerm.asc(p.id)]);

  /// Aktive Profile (ohne gelöschte).
  Stream<List<Player>> watchPlayers() => _active().watch();

  Future<List<Player>> players() => _active().get();

  static String clean(String name) {
    final t = name.trim();
    return t.length > maxNameLength ? t.substring(0, maxNameLength) : t;
  }

  Future<int> create(String name) {
    final n = clean(name);
    if (n.isEmpty) throw ArgumentError('Name fehlt');
    final now = DateTime.now();
    return db.into(db.players).insert(PlayersCompanion.insert(name: n, createdAt: now, updatedAt: Value(now)));
  }

  Future<void> rename(int id, String name) async {
    final n = clean(name);
    if (n.isEmpty) return;
    await (db.update(db.players)..where((p) => p.id.equals(id))).write(PlayersCompanion(name: Value(n), updatedAt: Value(DateTime.now())));
  }

  /// Löscht ein Profil mit allen Sessions, Würfen und Zielen. Das letzte
  /// Profil bleibt immer erhalten. Gibt `false` zurück, wenn nichts gelöscht
  /// wurde.
  Future<bool> delete(int id, {DateTime? at}) => db.transaction(() async {
        final all = await players();
        if (all.length <= 1 || !all.any((p) => p.id == id)) return false;
        await (db.delete(db.sessions)..where((s) => s.playerId.equals(id))).go();
        await (db.delete(db.throws)..where((t) => t.playerId.equals(id))).go();
        await (db.delete(db.goals)..where((g) => g.playerId.equals(id))).go();
        // Markierung statt Löschen, damit andere Geräte es beim Abgleich erfahren.
        final now = at ?? DateTime.now();
        await (db.update(db.players)..where((p) => p.id.equals(id))).write(
              PlayersCompanion(isDefault: const Value(false), deletedAt: Value(now), updatedAt: Value(now)),
            );
        // Es gibt immer genau ein Standardprofil.
        final rest = await players();
        if (!rest.any((p) => p.isDefault)) {
          await (db.update(db.players)..where((p) => p.id.equals(rest.first.id)))
              .write(const PlayersCompanion(isDefault: Value(true)));
        }
        return true;
      });

  /// Gültige Spieler-ID: [preferred], falls vorhanden, sonst das
  /// Standardprofil (wird bei Bedarf angelegt).
  Future<int> resolve(int? preferred) async {
    final all = await players();
    if (preferred != null && all.any((p) => p.id == preferred)) return preferred;
    final def = all.where((p) => p.isDefault).firstOrNull ?? all.firstOrNull;
    if (def != null) return def.id;
    return db.insertDefaultPlayer();
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(appDatabaseProvider)));
