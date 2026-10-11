import 'dart:convert';
import 'dart:io';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/backup/data/backup_service.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/stats/data/stats_repository.dart';
import 'package:dartlab/features/stats/domain/goals.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

void main() {
  late AppDatabase db;
  late GameRepository games;
  late ProfileRepository profiles;
  late BackupService backup;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    games = GameRepository(db);
    profiles = ProfileRepository(db);
    backup = BackupService(db);
  });
  tearDown(() => db.close());

  Future<int> play(int player, {String game = 'highscore_hunt', List<String> darts = const ['T20', 'S5', 'MISS'], int seed = 1}) async {
    final sid = await games.startSession(
      playerId: player,
      gameId: game,
      config: const {'visits': 1},
      seed: seed,
      startedAt: DateTime(2026, 10, 1, 12, seed),
    );
    for (final (i, n) in darts.indexed) {
      await games.addThrow(sessionId: sid, playerId: player, gameId: game, seq: i, visitIndex: 0, counted: true, dart: d(n));
    }
    await games.endSession(sid, result: const GameResult(metrics: {'points': 65, 'average': 65.0}, summary: []), finished: true);
    return sid;
  }

  group('Profile', () {
    test('anlegen, umbenennen, Namen werden bereinigt', () async {
      final id = await profiles.create('  Ben  ');
      await profiles.rename(id, 'Benjamin');
      await profiles.rename(id, '   ');
      final all = await profiles.players();
      expect(all.map((p) => p.name), ['Ich', 'Benjamin']);
      expect(() => profiles.create(' '), throwsArgumentError);
      expect(ProfileRepository.clean('x' * 50).length, ProfileRepository.maxNameLength);
    });

    test('löschen entfernt Sessions, Würfe und Ziele, letztes Profil bleibt', () async {
      final me = await profiles.resolve(null);
      final other = await profiles.create('Gast');
      await play(me);
      await play(other);
      await StatsRepository(db).addGoal(other, GoalKind.weeklySessions, 3);

      expect(await profiles.delete(other), isTrue);
      expect((await db.select(db.sessions).get()).map((s) => s.playerId), [me]);
      expect((await db.select(db.throws).get()).every((t) => t.playerId == me), isTrue);
      expect(await db.select(db.goals).get(), isEmpty);
      expect(await profiles.delete(me), isFalse);
    });

    test('Standardprofil wird neu vergeben, wenn es gelöscht wird', () async {
      final me = await profiles.resolve(null);
      final other = await profiles.create('Gast');
      expect(await profiles.delete(me), isTrue);
      final rest = await profiles.players();
      expect(rest.single.id, other);
      expect(rest.single.isDefault, isTrue);
      expect(await profiles.resolve(me), other);
    });
  });

  group('Backup', () {
    test('JSON-Export enthält alles und lässt sich in eine leere Datenbank importieren', () async {
      final me = await profiles.resolve(null);
      final guest = await profiles.create('Gast');
      await play(me);
      await play(guest, seed: 2);
      await StatsRepository(db).addGoal(me, GoalKind.weeklyDarts, 500);
      final json = await backup.exportJson();
      final data = jsonDecode(json) as Map<String, Object?>;
      expect(data['format'], 'dartlab-backup');
      expect((data['throws']! as List).length, 6);

      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      final r = await BackupService(target).importJson(json);
      expect(r.players, 1, reason: '"Ich" gibt es schon, "Gast" ist neu');
      expect(r.sessions, 2);
      expect(r.throws, 6);
      expect(r.goals, 1);
      final ts = await target.select(target.throws).get();
      expect(ts.map((t) => t.segment).toSet(), {'T20', 'S5', 'MISS'});
      final guestId = (await target.select(target.players).get()).firstWhere((p) => p.name == 'Gast').id;
      expect((await target.select(target.sessions).get()).where((s) => s.playerId == guestId).length, 1);
    });

    test('zweiter Import überspringt vorhandene Sessions', () async {
      final me = await profiles.resolve(null);
      await play(me);
      final json = await backup.exportJson();
      final r = await backup.importJson(json);
      expect(r.sessions, 0);
      expect(r.skipped, 1);
      expect(r.throws, 0);
      expect((await db.select(db.sessions).get()).length, 1);
    });

    test('Export eines einzelnen Profils', () async {
      final me = await profiles.resolve(null);
      final guest = await profiles.create('Gast');
      await play(me);
      await play(guest, seed: 2);
      final data = await backup.exportData(playerId: guest);
      expect((data['players']! as List).length, 1);
      expect((data['sessions']! as List).length, 1);
    });

    test('ungültige Dateien werden abgelehnt', () async {
      expect(() => backup.importJson('kein json'), throwsA(isA<BackupFormatException>()));
      expect(() => backup.importJson('{"format":"anders"}'), throwsA(isA<BackupFormatException>()));
      expect(() => backup.importJson('{"format":"dartlab-backup","version":99}'), throwsA(isA<BackupFormatException>()));
    });

    test('CSV der Würfe und Sessions', () async {
      final me = await profiles.resolve(null);
      await profiles.rename(me, 'Ben, "B"');
      await play(me);
      final csv = await backup.exportThrowsCsv();
      final lines = csv.split('\r\n');
      expect(lines.first, '﻿timestamp,player,game,session,visit,dart,segment,number,multiplier,score,counted,x,y,source');
      expect(lines.length, 5, reason: 'Kopf, 3 Würfe, leere letzte Zeile');
      expect(lines[1], contains('"Ben, ""B""",highscore_hunt'));
      expect(lines[1], contains(',T20,20,3,60,1,,,manual'));

      final sessions = (await backup.exportSessionsCsv()).split('\r\n');
      expect(sessions.first, '﻿session,started,ended,player,game,finished,darts,config,average,points');
      expect(sessions[1], endsWith(',65.0,65'));
    });
  });

  test('Migration von Version 1 legt die Ziele-Tabelle an und behält Daten', () async {
    final dir = await Directory.systemTemp.createTemp('dartlab');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    final v1 = AppDatabase(NativeDatabase(file));
    final player = await ProfileRepository(v1).resolve(null);
    await GameRepository(v1).startSession(playerId: player, gameId: 'checkout', config: const {}, seed: 1);
    // Zustand einer App aus Phase 2/3 nachstellen.
    await v1.customStatement('DROP TABLE goals');
    await v1.customStatement('PRAGMA user_version = 1');
    await v1.close();

    final v2 = AppDatabase(NativeDatabase(file));
    addTearDown(v2.close);
    expect((await v2.select(v2.sessions).get()).length, 1);
    await StatsRepository(v2).addGoal(player, GoalKind.streakDays, 7);
    expect((await v2.select(v2.goals).get()).single.kind, 'streakDays');
  });
}
