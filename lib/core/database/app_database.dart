import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'uid.dart';

export 'uid.dart';

part 'app_database.g.dart';

/// Spielerprofile. Standard ist ein Profil "Ich".
///
/// Gelöschte Profile bleiben mit [deletedAt] als Markierung stehen, damit das
/// Löschen beim Abgleich auch auf anderen Geräten ankommt.
@TableIndex(name: 'players_uid', columns: {#uid}, unique: true)
class Players extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  /// Geräteübergreifend eindeutig, siehe [newUid].
  TextColumn get uid => text().clientDefault(newUid)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// Eine gespielte Trainingseinheit (ein Spiel).
@DataClassName('SessionRow')
@TableIndex(name: 'sessions_uid', columns: {#uid}, unique: true)
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uid => text().clientDefault(newUid)();
  IntColumn get playerId => integer().references(Players, #id)();
  TextColumn get gameId => text()();
  TextColumn get configJson => text()();
  IntColumn get seed => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// Regulär zu Ende gespielt (nicht abgebrochen).
  BoolColumn get finished => boolean().withDefault(const Constant(false))();
  TextColumn get resultJson => text().nullable()();
  IntColumn get dartCount => integer().withDefault(const Constant(0))();
}

/// Jeder einzelne Dart mit Zeitstempel und Rohdaten, damit Statistiken
/// später neu berechnet werden können.
@DataClassName('ThrowRow')
@TableIndex(name: 'throws_session', columns: {#sessionId})
@TableIndex(name: 'throws_time', columns: {#timestamp})
class Throws extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(Sessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get playerId => integer().references(Players, #id)();
  TextColumn get gameId => text()();

  /// Reihenfolge innerhalb der Session (0, 1, 2 …).
  IntColumn get seq => integer()();
  IntColumn get visitIndex => integer()();

  /// Hat der Dart im Spiel gezählt (nicht nach Bust/Checkout ignoriert)?
  BoolColumn get counted => boolean().withDefault(const Constant(true))();

  /// Kurzname wie "T20", "25", "BULL", "MISS".
  TextColumn get segment => text()();
  IntColumn get number => integer()();
  IntColumn get multiplier => integer()();
  TextColumn get bed => text()();
  IntColumn get score => integer()();
  RealColumn get x => real().nullable()();
  RealColumn get y => real().nullable()();

  /// simulator, manual, autodartsLocal
  TextColumn get source => text()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get rawJson => text().nullable()();
}

/// Persönliche Ziele eines Spielers, z. B. "5 Sessions pro Woche".
@DataClassName('GoalRow')
@TableIndex(name: 'goals_uid', columns: {#uid}, unique: true)
class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uid => text().clientDefault(newUid)();
  IntColumn get playerId => integer().references(Players, #id, onDelete: KeyAction.cascade)();

  /// Art des Ziels, siehe `GoalKind`.
  TextColumn get kind => text()();
  RealColumn get target => real()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// Eigene Trainingspläne (geräteübergreifend, nicht an ein Profil gebunden).
/// Die festen Pläne stehen im Code.
@DataClassName('TrainingPlanRow')
@TableIndex(name: 'training_plans_uid', columns: {#uid}, unique: true)
class TrainingPlans extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uid => text().clientDefault(newUid)();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get description => text().withDefault(const Constant(''))();

  /// Schritte als JSON-Liste `[{gameId, config, note}]`, siehe `PlanStep`.
  TextColumn get stepsJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// Durchläufe von Trainingsplänen, damit ein angefangener Plan später
/// fortgesetzt werden kann. Bleiben auf dem Gerät (kein Abgleich).
@DataClassName('PlanRunRow')
@TableIndex(name: 'plan_runs_uid', columns: {#uid}, unique: true)
class PlanRuns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uid => text().clientDefault(newUid)();

  /// `builtin-…` oder `uid` eines eigenen Plans.
  TextColumn get planId => text()();
  TextColumn get planName => text()();

  /// Schritte beim Start (eingefroren).
  TextColumn get stepsJson => text()();
  IntColumn get playerId => integer().references(Players, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  IntColumn get currentStep => integer().withDefault(const Constant(0))();

  /// Ergebnisse je Schritt mit Session-`uid`, siehe `StepResult`.
  TextColumn get resultsJson => text().withDefault(const Constant('[]'))();
}

/// Freigeschaltete Erfolge, eine Zeile je Stufe (Bronze = 1, Silber = 2,
/// Gold = 3; Erfolge ohne Stufen haben nur Stufe 1). Die Freischaltung wird
/// aus den Daten berechnet; die Tabelle merkt sich, wann es so weit war.
@DataClassName('AchievementRow')
@TableIndex(name: 'achievements_key', columns: {#playerId, #achievementId, #tier}, unique: true)
class Achievements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playerId => integer().references(Players, #id, onDelete: KeyAction.cascade)();

  /// Kennung aus `AchievementCatalog`.
  TextColumn get achievementId => text()();
  IntColumn get tier => integer()();
  DateTimeColumn get unlockedAt => dateTime()();
}

/// Bestes Ergebnis je Challenge und Profil.
@DataClassName('ChallengeResultRow')
@TableIndex(name: 'challenge_results_key', columns: {#playerId, #challengeId}, unique: true)
class ChallengeResults extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playerId => integer().references(Players, #id, onDelete: KeyAction.cascade)();

  /// Kennung aus `ChallengeCatalog`, z. B. `c1-01`.
  TextColumn get challengeId => text()();

  /// Beste Sternezahl (0–3).
  IntColumn get stars => integer().withDefault(const Constant(0))();

  /// Bester Wert der Wertungs-Kennzahl, `null` ohne gültigen Wert.
  RealColumn get best => real().nullable()();

  /// Regulär beendete Versuche.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Wann das beste Ergebnis erreicht wurde.
  DateTimeColumn get achievedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DriftDatabase(tables: [Players, Sessions, Throws, Goals, TrainingPlans, PlanRuns, Achievements, ChallengeResults])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Datenbank im App-Support-Ordner des Geräts.
  factory AppDatabase.local() => AppDatabase(driftDatabase(name: 'dartlab'));

  /// Bei Schemaänderungen erhöhen und in [migration] einen Schritt ergänzen.
  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await insertDefaultPlayer();
        },
        onUpgrade: (m, from, to) async {
          // Version 2: Ziele.
          if (from < 2) await m.createTable(goals);
          // Version 3: eindeutige IDs und Löschmarkierungen für den Abgleich.
          if (from < 3) {
            for (final table in ['players', 'sessions', 'goals']) {
              // Eine in diesem Lauf neu angelegte Tabelle (z. B. goals ab
              // Version 1) hat die Spalten schon.
              if (!await _hasColumn(table, 'uid')) {
                await customStatement("ALTER TABLE $table ADD COLUMN uid TEXT NOT NULL DEFAULT ''");
              }
              await customStatement("UPDATE $table SET uid = lower(hex(randomblob(16))) WHERE uid = ''");
            }
            await customStatement(
              'UPDATE players SET uid = ? WHERE id = (SELECT id FROM players ORDER BY is_default DESC, id LIMIT 1) '
              'AND NOT EXISTS (SELECT 1 FROM players WHERE uid = ?)',
              [defaultPlayerUid, defaultPlayerUid],
            );
            for (final column in [players.updatedAt, players.deletedAt]) {
              if (!await _hasColumn('players', column.name)) await m.addColumn(players, column);
            }
            for (final column in [goals.updatedAt, goals.deletedAt]) {
              if (!await _hasColumn('goals', column.name)) await m.addColumn(goals, column);
            }
            for (final table in ['players', 'sessions', 'goals']) {
              await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS ${table}_uid ON $table (uid)');
            }
          }
          // Version 4: Trainingspläne und ihre Durchläufe. createTable legt
          // nur an, was fehlt (IF NOT EXISTS), der Schritt ist wiederholbar.
          if (from < 4) {
            await m.createTable(trainingPlans);
            await m.createTable(planRuns);
            for (final table in ['training_plans', 'plan_runs']) {
              await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS ${table}_uid ON $table (uid)');
            }
          }
          // Version 5: Erfolge und Challenge-Ergebnisse (wiederholbar wie oben).
          if (from < 5) {
            await m.createTable(achievements);
            await m.createTable(challengeResults);
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS achievements_key ON achievements (player_id, achievement_id, tier)',
            );
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS challenge_results_key ON challenge_results (player_id, challenge_id)',
            );
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<bool> _hasColumn(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((r) => r.read<String>('name') == column);
  }

  /// Legt das Standardprofil „Ich“ an. Die feste [defaultPlayerUid] bekommt
  /// es nur, solange sie noch frei ist.
  Future<int> insertDefaultPlayer() async {
    final taken = await (select(players)..where((p) => p.uid.equals(defaultPlayerUid))).getSingleOrNull();
    return into(players).insert(PlayersCompanion.insert(
      name: 'Ich',
      isDefault: const Value(true),
      createdAt: DateTime.now(),
      uid: taken == null ? const Value(defaultPlayerUid) : const Value.absent(),
    ));
  }
}

/// In Tests mit `AppDatabase(NativeDatabase.memory())` überschreiben.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.local();
  ref.onDispose(db.close);
  return db;
});
