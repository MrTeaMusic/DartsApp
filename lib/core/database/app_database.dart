import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'app_database.g.dart';

/// Spielerprofile. Standard ist ein Profil "Ich".
class Players extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

/// Eine gespielte Trainingseinheit (ein Spiel).
@DataClassName('SessionRow')
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
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
class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playerId => integer().references(Players, #id, onDelete: KeyAction.cascade)();

  /// Art des Ziels, siehe `GoalKind`.
  TextColumn get kind => text()();
  RealColumn get target => real()();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(tables: [Players, Sessions, Throws, Goals])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Datenbank im App-Support-Ordner des Geräts.
  factory AppDatabase.local() => AppDatabase(driftDatabase(name: 'dartlab'));

  /// Bei Schemaänderungen erhöhen und in [migration] einen Schritt ergänzen.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await into(players).insert(PlayersCompanion.insert(
            name: 'Ich',
            isDefault: const Value(true),
            createdAt: DateTime.now(),
          ));
        },
        onUpgrade: (m, from, to) async {
          // Version 2: Ziele.
          if (from < 2) await m.createTable(goals);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

/// In Tests mit `AppDatabase(NativeDatabase.memory())` überschreiben.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.local();
  ref.onDispose(db.close);
  return db;
});
