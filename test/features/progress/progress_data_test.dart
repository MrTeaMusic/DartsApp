import 'dart:convert';
import 'dart:io';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/backup/data/backup_service.dart';
import 'package:dartlab/features/challenges/data/challenge_repository.dart';
import 'package:dartlab/features/challenges/domain/challenge_catalog.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/progress/data/achievement_repository.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../helpers/sync_device.dart';

extension on Device {
  AchievementRepository get achievements => AchievementRepository(db);
  ChallengeRepository get challenges => ChallengeRepository(db);
}

Future<void> sync(Device a, Device b) async {
  await b.store.merge(await a.store.bundle());
  await a.store.merge(await b.store.bundle());
}

DateTime at(int day, [int hour = 12]) => DateTime(2026, 10, day, hour);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Device a;
  late Device b;
  setUp(() {
    a = Device();
    b = Device();
  });
  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  final atc = ChallengeCatalog.byId('c1-1')!; // weniger Darts sind besser
  final points = ChallengeCatalog.byId('c1-3')!;

  test('Freischaltungen: nur fehlende Stufen kommen dazu, Datum bleibt', () async {
    final me = await a.me();
    expect(await a.achievements.addUnlocks(me, {'first_180#1': at(1), 'tons#1': at(2)}), 2);
    expect(await a.achievements.addUnlocks(me, {'first_180#1': at(5), 'tons#2': at(6)}), 1);
    final rows = await a.achievements.unlocks(me);
    expect(rows, hasLength(3));
    expect(rows.firstWhere((r) => r.achievementId == 'first_180').unlockedAt, at(1));
  });

  test('Challenge-Ergebnis: Sterne und Bestwert werden nur besser, Versuche zählen', () async {
    final me = await a.me();
    expect(await a.challenges.record(me, atc, stars: 1, score: 55, at: at(1)), isNull);
    final first = await a.challenges.record(me, atc, stars: 0, score: 70, at: at(2));
    expect(first!.stars, 1);
    await a.challenges.record(me, atc, stars: 2, score: 44, at: at(3));
    final best = (await a.challenges.result(me, atc.id))!;
    expect(best.stars, 2);
    expect(best.best, 44);
    expect(best.attempts, 3);
    expect(best.achievedAt, at(3));
    // Ein schlechterer Versuch ändert das Datum nicht.
    await a.challenges.record(me, atc, stars: 1, score: 50, at: at(4));
    expect((await a.challenges.result(me, atc.id))!.achievedAt, at(3));
  });

  test('Abgleich: Erfolge und Challenges landen auf dem anderen Gerät, das Bessere gewinnt', () async {
    final meA = await a.me();
    await a.achievements.addUnlocks(meA, {'first_180#1': at(3)});
    await a.challenges.record(meA, atc, stars: 2, score: 44, at: at(3));
    await a.challenges.record(meA, points, stars: 1, score: 320, at: at(3));
    await sync(a, b);

    final meB = await b.me();
    expect((await b.achievements.unlocks(meB)).single.unlockedAt, at(3));
    expect((await b.challenges.result(meB, atc.id))!.best, 44);

    // Auf B: früher freigeschaltet, mehr Punkte; auf A: weniger Darts.
    await b.achievements.addUnlocks(meB, {'tons#1': at(1)});
    await b.challenges.record(meB, points, stars: 3, score: 510, at: at(5));
    await a.challenges.record(meA, atc, stars: 3, score: 33, at: at(6));
    await sync(a, b);

    for (final (d, me) in [(a, meA), (b, meB)]) {
      final c1 = (await d.challenges.result(me, atc.id))!;
      expect(c1.stars, 3);
      expect(c1.best, 33);
      final c3 = (await d.challenges.result(me, points.id))!;
      expect(c3.stars, 3);
      expect(c3.best, 510);
      expect(c3.achievedAt, at(5));
      expect((await d.achievements.unlocks(me)).map((r) => r.achievementId), containsAll(['first_180', 'tons']));
    }
    expect((await b.store.merge(await a.store.bundle())).changedAnything, isFalse);
    // Neue Erfolge und Ergebnisse ändern die Signatur (Abgleich nötig).
    final before = await a.store.signature();
    await a.achievements.addUnlocks(meA, {'darts#1': at(7)});
    final afterUnlock = await a.store.signature();
    expect(afterUnlock, isNot(before));
    await a.challenges.record(meA, atc, stars: 1, score: 50, at: at(8));
    expect(await a.store.signature(), isNot(afterUnlock));
  });

  test('Sicherung enthält Erfolge und Challenges und stellt sie wieder her', () async {
    final me = await a.me();
    await a.achievements.addUnlocks(me, {'many_180#2': at(2)});
    await a.challenges.record(me, points, stars: 2, score: 410, at: at(2));
    final json = await BackupService(a.db).exportJson();
    final data = jsonDecode(json) as Map<String, Object?>;
    expect(data['version'], BackupService.version);
    expect(data['achievements'], hasLength(1));
    expect(data['challenges'], hasLength(1));

    final r = await BackupService(b.db).importJson(json);
    expect(r.achievements, 1);
    expect(r.challenges, 1);
    final meB = await b.me();
    expect((await b.challenges.result(meB, points.id))!.best, 410);
    expect((await BackupService(b.db).importJson(json)).changedAnything, isFalse);
  });

  test('Profil löschen entfernt Erfolge und Challenges', () async {
    final other = await a.profiles.create('Gast');
    await a.achievements.addUnlocks(other, {'tons#1': at(1)});
    await a.challenges.record(other, atc, stars: 1, score: 60, at: at(1));
    await a.profiles.delete(other);
    expect(await a.db.select(a.db.achievements).get(), isEmpty);
    expect(await a.db.select(a.db.challengeResults).get(), isEmpty);
  });

  test('Migration von Version 4 legt die neuen Tabellen an, wiederholbar', () async {
    final dir = await Directory.systemTemp.createTemp('dartlab');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    final v4 = AppDatabase(NativeDatabase(file));
    final me = await ProfileRepository(v4).resolve(null);
    await v4.customStatement('DROP TABLE achievements');
    await v4.customStatement('DROP TABLE challenge_results');
    await v4.customStatement('PRAGMA user_version = 4');
    await v4.close();

    final v5 = AppDatabase(NativeDatabase(file));
    await AchievementRepository(v5).addUnlocks(me, {'tons#1': at(1)});
    await ChallengeRepository(v5).record(me, atc, stars: 1, score: 58, at: at(1));
    await v5.close();

    // Abgebrochener Lauf: Tabellen da, Version noch 4.
    final raw = sqlite3.open(file.path);
    raw.execute('PRAGMA user_version = 4');
    raw.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect(await again.select(again.achievements).get(), hasLength(1));
    expect((await ChallengeRepository(again).result(me, atc.id))!.best, 58);
    final indexes = await again.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get();
    expect(indexes.map((r) => r.read<String>('name')), containsAll(['achievements_key', 'challenge_results_key']));
    final version = await again.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 7);
  });
}
