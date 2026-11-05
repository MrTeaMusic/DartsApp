import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/history/data/history_repository.dart';
import 'package:dartlab/features/history/domain/session_history.dart';
import 'package:dartlab/features/history/presentation/shared_match_screen.dart';
import 'package:dartlab/features/history/share/shared_match.dart';
import 'package:dartlab/features/history/share/shared_match_opener.dart';
import 'package:dartlab/features/history/share/windows_file_type.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/history_seed.dart';
import '../../helpers/leg_seed.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/sync_device.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Device ben;
  setUp(() => ben = Device());
  tearDown(() => ben.db.close());

  Future<(SessionDetail, SharedMatch)> share(int id, {SharedElo? elo}) async {
    final row = (await HistoryRepository(ben.db).session(id))!;
    final throws = await ben.games.throwsOf(id);
    final original = buildSessionDetail(row, throws, playerName: 'Ben');
    final match = SharedMatch.fromSession(player: 'Ben', session: row, throws: throws, elo: elo, createdAt: DateTime(2026, 11, 5, 10));
    return (original, SharedMatch.decode(match.encode()));
  }

  void expectSameDetail(SessionDetail a, SessionDetail b) {
    expect(b.entry.gameId, a.entry.gameId);
    expect(b.entry.startedAt, a.entry.startedAt);
    expect(b.entry.won, a.entry.won);
    expect(b.entry.opponents, a.entry.opponents);
    expect(b.legs.length, a.legs.length);
    expect([for (final v in b.visits) v.score], [for (final v in a.visits) v.score]);
    expect([for (final v in b.visits) v.after], [for (final v in a.visits) v.after]);
    expect([for (final s in b.summary) '${s.key}=${s.value}'], [for (final s in a.summary) '${s.key}=${s.value}']);
    expect([for (final p in b.players) p.name], [for (final p in a.players) p.name]);
    expect(b.positions.length, a.positions.length);
    expect(b.finishAttempts, a.finishAttempts);
  }

  group('Datei hin und zurück', () {
    test('Match mit Gegner, Legs und Elo', () async {
      final id = await seedHandMadeMatch(ben.games, await ben.me(), DateTime(2026, 10, 1, 19));
      final (original, back) = await share(id, elo: const SharedElo(before: 1500, after: 1512));
      expectSameDetail(original, back.toDetail());
      expect(back.player, 'Ben');
      expect(back.elo!.change, 12);
      expect(back.createdAt, DateTime(2026, 11, 5, 10));
    });

    test('Trainings: X01, Cricket, abgebrochen', () async {
      final s = await seedHistory(ben.games, await ben.me(), DateTime(2026, 10, 20, 20));
      for (final id in [s.x01, s.cricket, s.aborted, s.match]) {
        final (original, back) = await share(id);
        expectSameDetail(original, back.toDetail());
        expect(back.elo, isNull);
      }
    });

    test('ohne interne Nummern und Rohdaten', () async {
      final id = await seedHandMadeMatch(ben.games, await ben.me(), DateTime(2026, 10, 1, 19));
      final row = (await HistoryRepository(ben.db).session(id))!;
      final json = SharedMatch.fromSession(player: 'Ben', session: row, throws: await ben.games.throwsOf(id)).toJson();
      expect(json['format'], 'dartlab-match');
      expect(json['version'], sharedMatchFormatVersion);
      final session = json['session']! as Map<String, Object?>;
      expect(session['id'], 0);
      expect(session['playerId'], 0);
      for (final t in json['throws']! as List) {
        expect((t as Map)['rawJson'], isNull);
        expect(t['sessionId'], 0);
      }
    });

    test('Dateiname', () async {
      final id = await seedHandMadeMatch(ben.games, await ben.me(), DateTime(2026, 10, 1, 19));
      final (_, back) = await share(id);
      expect(back.fileName, matches(RegExp(r'^dartlab-ben-vs-[a-z0-9-]+-2026-10-01\.dartlab$')));
    });
  });

  group('fremde Dateien', () {
    SharedMatchError? errorOf(List<int> bytes) {
      try {
        SharedMatch.decode(bytes);
        return null;
      } on SharedMatchException catch (e) {
        return e.error;
      }
    }

    test('kein JSON, falsches Format, kaputte Felder', () {
      expect(errorOf([0x25, 0x50, 0x44, 0x46]), SharedMatchError.notDartLab);
      expect(errorOf(utf8.encode('{"version":1}')), SharedMatchError.notDartLab);
      expect(errorOf(utf8.encode('[1,2]')), SharedMatchError.notDartLab);
      expect(errorOf(utf8.encode('{"format":"dartlab-match","version":1,"session":{}}')), SharedMatchError.notDartLab);
    });

    test('aus einer neueren Version', () {
      expect(errorOf(utf8.encode('{"format":"dartlab-match","version":99}')), SharedMatchError.newerVersion);
    });

    test('mit BOM', () async {
      final id = await seedHandMadeMatch(ben.games, await ben.me(), DateTime(2026, 10, 1, 19));
      final row = (await HistoryRepository(ben.db).session(id))!;
      final bytes = SharedMatch.fromSession(player: 'Ben', session: row, throws: await ben.games.throwsOf(id)).encode();
      expect(errorOf([0xEF, 0xBB, 0xBF, ...bytes]), isNull);
    });
  });

  test('Windows: Dateizuordnung zeigt auf die App und gibt die Datei weiter', () {
    final cmds = windowsFileTypeCommands(r'C:\Apps\DartLab\dartlab.exe');
    expect(cmds.every((c) => c.first == 'add' && c.last == '/f'), isTrue);
    expect(cmds.first, [r'add', r'HKCU\Software\Classes\.dartlab', '/ve', '/d', 'DartLab.Match', '/f']);
    expect(cmds.last[1], r'HKCU\Software\Classes\DartLab.Match\shell\open\command');
    expect(cmds.last[cmds.last.indexOf('/d') + 1], r'"C:\Apps\DartLab\dartlab.exe" "%1"');
  });

  test('Startargumente: nur .dartlab-Dateien', () {
    expect(sharedMatchArgs(['--fullscreen', r'C:\Users\x\Downloads\Match.DARTLAB', 'a.pdf']), [r'C:\Users\x\Downloads\Match.DARTLAB']);
  });

  testWidgets('geteiltes Match öffnen: Ansicht mit Hinweis, eigene Daten unberührt', (tester) async {
    final bytes = (await tester.runAsync(() async {
      final id = await seedHandMadeMatch(ben.games, await ben.me(), DateTime(2026, 10, 1, 19));
      final row = (await HistoryRepository(ben.db).session(id))!;
      return SharedMatch.fromSession(player: 'Ben', session: row, throws: await ben.games.throwsOf(id), elo: const SharedElo(before: 1500, after: 1512))
          .encode();
    }))!;
    final c = await pumpApp(tester);
    final db = c.read(appDatabaseProvider);
    final before = await tester.runAsync(() => db.select(db.sessions).get());

    c.read(sharedMatchOpenerProvider).openBytes(bytes);
    await tester.pumpAndSettle();
    expect(find.byType(SharedMatchScreen), findsOneWidget);
    expect(find.byKey(const Key('shared-match-banner')), findsOneWidget);
    expect(find.text('Geteilt von Ben'), findsOneWidget);
    expect(find.byKey(const Key('session-match-result')), findsOneWidget);
    expect(find.byKey(const Key('session-match-elo')), findsOneWidget);
    // Nur ansehen: kein Löschen, kein Nochmal-Spielen.
    expect(find.byKey(const Key('session-delete')), findsNothing);
    expect(find.byKey(const Key('session-play-again')), findsNothing);

    final after = await tester.runAsync(() => db.select(db.sessions).get());
    expect(after!.length, before!.length);
    expect(await tester.runAsync(() => db.select(db.throws).get()), isEmpty);

    await tester.tap(find.byKey(const Key('shared-match-close')));
    await tester.pumpAndSettle();
    expect(find.byType(SharedMatchScreen), findsNothing);
    expect(c.read(routerProvider).routerDelegate.currentConfiguration.uri.path, Routes.home);
  });

  testWidgets('fremde Datei: Hinweis, kein Seitenwechsel', (tester) async {
    final c = await pumpApp(tester);
    c.read(sharedMatchOpenerProvider).openBytes(utf8.encode('hallo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shared-match-error')), findsOneWidget);
    expect(find.text('Datei lässt sich nicht öffnen'), findsOneWidget);
    expect(c.read(routerProvider).routerDelegate.currentConfiguration.uri.path, Routes.home);
  });
}
