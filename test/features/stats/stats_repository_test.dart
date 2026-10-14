import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/progress/domain/achievement_tracker.dart';
import 'package:dartlab/features/progress/domain/daily_goal.dart';
import 'package:dartlab/features/stats/data/stats_repository.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';
import '../progress/progress_domain_test.dart' show played;

/// Alles, was Statistik, Tagesziel und Erfolge aus einem Rechner lesen, als
/// Text, damit sich zwei Rechner vergleichen lassen.
String fingerprint(StatsCalculator calc) {
  String hits(Map<int, HitCount> m) => [for (final e in m.entries) '${e.key}:${e.value.attempts}/${e.value.hits}'].join(',');
  final out = StringBuffer();
  for (final s in calc.sessions) {
    out.writeln('${s.id} ${[for (final t in calc.throwsOf(s)) t.id]} ${calc.countedOf(s).length} '
        '${calc.aimedOf(s).length} ${calc.metricsOfSession(s)}');
  }
  for (final period in StatsPeriod.values) {
    final r = calc.report(period);
    out.writeln('${r.sessions} ${r.darts} ${r.scoringAverage} ${r.first9Average} ${r.checkoutRate} ${r.doubleRate} '
        '${r.trebleRate} ${r.accuracy.attempts}/${r.accuracy.hits} ${hits(r.doubles)} ${hits(r.trebles)} ${r.numberHits} '
        '${[for (final d in r.dailyDarts) '${d.day}:${d.darts}']} ${r.scoring?.visits} ${r.scoring?.mean} '
        '${r.streak.current}/${r.streak.longest}');
  }
  for (final r in calc.records()) {
    out.writeln('${r.kind} ${r.value} ${r.date} ${r.gameId}');
  }
  for (final e in dailyActivity(calc).entries) {
    out.writeln('${e.key} ${e.value.darts} ${e.value.minutes} ${e.value.sessions}');
  }
  out.writeln(reachedTiers(AchievementTracker.fromCalculator(calc)));
  return out.toString();
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late AppDatabase db;
  late int me;
  late GameRepository games;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    me = await ProfileRepository(db).resolve(null);
    games = GameRepository(db);
    // Abgeschlossene Sessions verschiedener Spiele mit echten Würfen.
    final names = ['T20', 'S20', 'S1', 'D16', 'S5', 'T19', 'MISS', 'D8', 'BULL', 'S20', 'T20', 'D20'];
    var i = 0;
    for (final id in ['x01', 'highscore_hunt', 'around_the_clock', 'bobs_27', 'checkout', 'x01', 'bull_drill']) {
      final (s, t) = played(id, const {}, [for (var k = 0; k < 30; k++) names[(k * 7 + i) % names.length]],
          start: DateTime.now().subtract(Duration(days: 9 - i, hours: 2)));
      await db.into(db.sessions).insert(s.copyWith(playerId: me).toCompanion(false));
      await db.batch((b) => b.insertAll(db.throws, [for (final r in t) r.copyWith(playerId: me).toCompanion(false)]));
      i++;
    }
  });
  tearDown(() => db.close());

  Future<StatsCalculator> full() async => StatsCalculator(
        sessions: await (db.select(db.sessions)..where((s) => s.playerId.equals(me) & s.endedAt.isNotNull())).get(),
        throws: await (db.select(db.throws)..where((t) => t.playerId.equals(me))).get(),
      );

  Future<void> waitFor(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue);
  }

  test('Spielstart rechnet nichts neu, Spielende lädt nur die neue Session; Ergebnis wie komplett neu', () async {
    final calcs = <StatsCalculator>[];
    final sub = StatsRepository(db).watchCalculator(me).listen(calcs.add);
    addTearDown(sub.cancel);
    await waitFor(() => calcs.isNotEmpty);
    final first = calcs.single;
    expect(first.sessions, hasLength(7));
    expect(fingerprint(first), fingerprint(await full()));

    // Spielstart: die Session ist noch offen, es kommt kein neuer Rechner.
    final sid = await games.startSession(playerId: me, gameId: 'highscore_hunt', config: const {'visits': 2}, seed: 1);
    for (final (i, n) in ['T20', 'T20', 'S5', 'D1', 'MISS', 'S20'].indexed) {
      await games.addThrow(sessionId: sid, playerId: me, gameId: 'highscore_hunt', seq: i, visitIndex: i ~/ 3, counted: true, dart: d(n));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calcs, hasLength(1));

    // Spielende: neuer Rechner, die Würfe der alten Sessions sind übernommen.
    await games.endSession(sid, result: const GameResult(metrics: {'points': 247}, summary: []), finished: true);
    await waitFor(() => calcs.length == 2);
    final next = calcs.last;
    expect(next.sessions, hasLength(8));
    for (final s in first.sessions) {
      expect(identical(next.throwsOf(s), first.throwsOf(s)), isTrue);
    }
    expect(next.throwsOf(next.sessions.firstWhere((s) => s.id == sid)), hasLength(6));
    expect(fingerprint(next), fingerprint(await full()));
  });

  test('Würfe, die nach ihrer Session gespeichert werden (Abgleich), kommen beim nächsten Mal mit', () async {
    final calcs = <StatsCalculator>[];
    final sub = StatsRepository(db).watchCalculator(me).listen(calcs.add);
    addTearDown(sub.cancel);
    await waitFor(() => calcs.isNotEmpty);

    // Erst die abgeschlossene Session ohne Würfe …
    final (s, t) = played('highscore_hunt', const {'visits': 1}, ['T20', 'T20', 'T20'],
        start: DateTime.now().subtract(const Duration(hours: 1)));
    await db.into(db.sessions).insert(s.copyWith(playerId: me).toCompanion(false));
    await waitFor(() => calcs.length == 2);
    expect(calcs.last.throwsOf(calcs.last.sessions.firstWhere((x) => x.id == s.id)), isEmpty);

    // … dann die Würfe; die nächste Änderung an den Sessions bringt sie mit.
    await db.batch((b) => b.insertAll(db.throws, [for (final r in t) r.copyWith(playerId: me).toCompanion(false)]));
    await games.startSession(playerId: me, gameId: 'x01', config: const {}, seed: 2);
    await waitFor(() => calcs.length == 3);
    expect(calcs.last.throwsOf(calcs.last.sessions.firstWhere((x) => x.id == s.id)), hasLength(3));
    expect(fingerprint(calcs.last), fingerprint(await full()));

    // Gelöschte Sessions verschwinden.
    await (db.delete(db.sessions)..where((x) => x.id.equals(s.id))).go();
    await waitFor(() => calcs.length == 4);
    expect(calcs.last.sessions.map((x) => x.id), isNot(contains(s.id)));
    expect(fingerprint(calcs.last), fingerprint(await full()));
  });
}
