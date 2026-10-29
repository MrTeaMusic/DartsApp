import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/stats/domain/goals.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 11, 18);
var _id = 0;

SessionRow session(String gameId, DateTime start, Map<String, Object?> metrics,
    {Map<String, Object?> details = const {}, int darts = 3, bool ended = true}) =>
    SessionRow(
      id: ++_id,
      uid: 's$_id',
      playerId: 1,
      gameId: gameId,
      configJson: '{}',
      seed: 1,
      startedAt: start,
      endedAt: ended ? start.add(const Duration(minutes: 5)) : null,
      finished: true,
      resultJson: jsonEncode({'metrics': metrics, 'details': details}),
      dartCount: darts,
    );

ThrowRow dart(SessionRow s, String name, {int seq = 0, bool counted = true, double? x, double? y}) {
  final seg = Segment.tryParse(name)!;
  return ThrowRow(
    id: ++_id,
    sessionId: s.id,
    playerId: 1,
    gameId: s.gameId,
    seq: seq,
    visitIndex: 0,
    counted: counted,
    segment: seg.name,
    number: seg.number,
    multiplier: seg.multiplier,
    bed: seg.bed.name,
    score: seg.score,
    x: x,
    y: y,
    source: 'manual',
    timestamp: s.startedAt,
    rawJson: null,
  );
}

GoalRow goal(GoalKind kind, double target) =>
    GoalRow(id: ++_id, uid: 'g$_id', playerId: 1, kind: kind.name, target: target, createdAt: now);

void main() {
  test('Average nur aus Scoring-Spielen, ignorierte Darts zählen nicht', () {
    final hs = session('highscore_hunt', now, {'average': 81});
    final atc = session('around_the_clock', now, {'darts': 30, 'completed': 1});
    final calc = StatsCalculator(sessions: [hs, atc], throws: [
      dart(hs, 'T20'),
      dart(hs, 'S1', seq: 1),
      dart(hs, 'D10', seq: 2),
      dart(hs, 'T20', seq: 3, counted: false),
      dart(atc, 'S1'),
    ], now: now);
    final r = calc.report(StatsPeriod.all);
    expect(r.scoringAverage, 81);
    expect(r.darts, 4);
    expect(r.sessions, 2);
    expect(r.numberHits, {20: 1, 1: 2, 10: 1});
  });

  test('Checkout-Quote nur aus Checkout-Training, 121 zählt nicht', () {
    final co = session('checkout', now, {}, details: {
      'attempts': [
        {'target': 40, 'success': true, 'darts': 1},
        {'target': 81, 'success': false, 'darts': 3},
      ],
    });
    final ott = session('one_twenty_one', now, {}, details: {
      'rounds': [
        {'target': 121, 'success': true, 'darts': 9},
        {'target': 122, 'success': true, 'darts': 6},
      ],
    });
    final r = StatsCalculator(sessions: [co, ott], throws: const [], now: now).report(StatsPeriod.all);
    expect(r.checkoutAttempts, 2);
    expect(r.checkoutRate, 0.5);
  });

  test('Double- und Triple-Quote aus Bob\'s 27 und T20-Training', () {
    final r = StatsCalculator(sessions: [
      session('bobs_27', now, {'hits': 6, 'darts': 60}),
      session('bobs_27', now, {'hits': 14, 'darts': 40}),
      session('target_practice', now, {'trebles': 3, 'darts': 30}),
    ], throws: const [], now: now)
        .report(StatsPeriod.all);
    expect(r.doubleRate, 0.2);
    expect(r.trebleRate, 0.1);
  });

  test('Zeitraum filtert, Verlauf und Rekord je Spiel', () {
    final old = session('target_practice', now.subtract(const Duration(days: 40)), {'average': 70});
    final a = session('target_practice', now.subtract(const Duration(days: 3)), {'average': 45});
    final b = session('target_practice', now, {'average': 55});
    final calc = StatsCalculator(sessions: [b, old, a], throws: const [], now: now);
    expect(calc.report(StatsPeriod.month).sessions, 2);
    expect(calc.trend('target_practice', StatsPeriod.all).map((p) => p.value), [70, 45, 55]);
    final g = calc.report(StatsPeriod.month).games.single;
    expect(g.best, 55);
    expect(g.last, 55);
    expect(calc.report(StatsPeriod.all).games.single.best, 70);
  });

  test('Bei "weniger ist besser" zählen nur vollständige Spiele', () {
    final calc = StatsCalculator(sessions: [
      session('around_the_clock', now, {'darts': 40, 'completed': 1}),
      session('around_the_clock', now, {'darts': 12, 'completed': 0}),
      session('around_the_clock', now, {'darts': 33, 'completed': 1}),
    ], throws: const [], now: now);
    expect(calc.report(StatsPeriod.all).games.single.best, 33);
  });

  test('Heatmap nutzt Koordinaten, sonst die Feldmitte, Fehlwürfe ohne Position fehlen', () {
    final s = session('highscore_hunt', now, {});
    final r = StatsCalculator(sessions: [s], throws: [
      dart(s, 'T20', x: 0.01, y: 0.6),
      dart(s, 'S5', seq: 1),
      dart(s, 'MISS', seq: 2),
    ], now: now)
        .report(StatsPeriod.all);
    expect(r.heat.length, 2);
    expect(r.heat.first.x, 0.01);
  });

  test('Darts pro Tag inklusive Tage ohne Training', () {
    final s1 = session('highscore_hunt', now.subtract(const Duration(days: 2)), {});
    final s2 = session('highscore_hunt', now, {});
    final r = StatsCalculator(sessions: [s1, s2], throws: [dart(s1, 'S1'), dart(s2, 'S1'), dart(s2, 'S2', seq: 1)], now: now)
        .report(StatsPeriod.week);
    expect(r.dailyDarts.length, 7);
    expect(r.dailyDarts.map((d) => d.darts).toList().sublist(4), [1, 0, 2]);
  });

  group('Streak', () {
    StatsCalculator calcFor(List<int> daysAgo) => StatsCalculator(sessions: [
          for (final d in daysAgo) session('bull_drill', now.subtract(Duration(days: d)), {}),
        ], throws: const [], now: now);

    test('heute und die Tage davor', () {
      final s = calcFor([0, 1, 2, 5, 6]).streak();
      expect(s.current, 3);
      expect(s.longest, 3);
      expect(s.trainedToday, isTrue);
    });

    test('gestern zuletzt: Serie läuft noch', () {
      final s = calcFor([1, 2, 10, 11, 12, 13]).streak();
      expect(s.current, 2);
      expect(s.longest, 4);
      expect(s.trainedToday, isFalse);
    });

    test('vorgestern zuletzt: Serie gerissen', () {
      expect(calcFor([2, 3]).streak().current, 0);
      expect(calcFor([]).streak().longest, 0);
    });
  });

  test('Ziele: Woche, Streak, Quoten', () {
    // 2026-10-11 ist ein Sonntag, die Woche beginnt am 5.10.
    final inWeek = session('bobs_27', DateTime(2026, 10, 5, 9), {'hits': 5, 'darts': 25}, darts: 25);
    final lastWeek = session('bobs_27', DateTime(2026, 10, 4, 9), {'hits': 0, 'darts': 25}, darts: 25);
    final today = session('highscore_hunt', now, {}, darts: 30);
    final calc = StatsCalculator(sessions: [inWeek, lastWeek, today], throws: [
      for (var i = 0; i < 3; i++) dart(today, 'T20', seq: i),
    ], now: now);
    expect(calc.weekStart, DateTime(2026, 10, 5));
    final p = goalProgress([
      goal(GoalKind.weeklySessions, 2),
      goal(GoalKind.weeklyDarts, 100),
      goal(GoalKind.streakDays, 3),
      goal(GoalKind.doubleRate, 15),
      goal(GoalKind.checkoutRate, 30),
      goal(GoalKind.scoringAverage, 60),
    ], calc);
    expect(p[0].current, 2);
    expect(p[0].reached, isTrue);
    expect(p[1].current, 55);
    expect(p[1].ratio, closeTo(0.55, 1e-9));
    expect(p[2].current, 1);
    expect(p[3].current, 10);
    expect(p[3].reached, isFalse);
    expect(p[4].current, isNull);
    expect(p[4].ratio, 0);
    expect(p[5].current, 180);
    expect(p[5].ratio, 1);
  });
}
