import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/stats/domain/game_metrics.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:dartlab/features/stats/domain/target_replay.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-10-11 ist ein Sonntag.
final now = DateTime(2026, 10, 11, 18);
var _id = 0;

SessionRow session(String gameId, DateTime start,
        {Map<String, Object?> metrics = const {},
        Map<String, Object?> details = const {},
        Map<String, Object?> config = const {},
        Duration length = const Duration(minutes: 20),
        int darts = 3}) =>
    SessionRow(
      id: ++_id,
      uid: 's$_id',
      playerId: 1,
      gameId: gameId,
      configJson: jsonEncode(config),
      seed: 7,
      startedAt: start,
      endedAt: start.add(length),
      finished: true,
      resultJson: jsonEncode({'metrics': metrics, 'details': details}),
      dartCount: darts,
    );

/// Würfe einer Session; jede innere Liste ist eine Aufnahme.
List<ThrowRow> visits(SessionRow s, List<List<String>> names, {List<bool>? counted}) {
  final out = <ThrowRow>[];
  var seq = 0;
  for (final (v, visit) in names.indexed) {
    for (final name in visit) {
      final seg = Segment.tryParse(name)!;
      out.add(ThrowRow(
        id: ++_id,
        sessionId: s.id,
        playerId: 1,
        gameId: s.gameId,
        seq: seq,
        visitIndex: v,
        counted: counted?[seq] ?? true,
        segment: seg.name,
        number: seg.number,
        multiplier: seg.multiplier,
        bed: seg.bed.name,
        score: seg.score,
        x: null,
        y: null,
        source: 'manual',
        timestamp: s.startedAt.add(Duration(seconds: seq * 10)),
        rawJson: null,
      ));
      seq++;
    }
  }
  return out;
}

void main() {
  group('Ziel je Dart durch erneutes Abspielen', () {
    test("Bob's 27: Doubles je Zahl, auch bei vorzeitig beendeter Aufnahme", () {
      final s = session('bobs_27', now);
      final t = visits(s, [
        ['D1', 'S1', 'D1'],
        ['S2', 'MISS', 'S2'],
        ['D3'], // Takeout nach einem Dart
        ['D4', 'S4', 'S4'],
      ]);
      final r = StatsCalculator(sessions: [s], throws: t, now: now).report(StatsPeriod.all);
      expect(r.doubles[1]!.attempts, 3);
      expect(r.doubles[1]!.hits, 2);
      expect(r.doubles[2]!.hits, 0);
      expect(r.doubles[3]!.attempts, 1);
      expect(r.doubles[4]!.hits, 1);
      expect(r.doubleAttempts, 10);
      expect(r.doubleRate, closeTo(0.4, 1e-9));
      expect(r.accuracy.attempts, 10);
      expect(r.games.single.accuracy.hits, 4);
    });

    test('Checkout-Training: Dart aufs vorgeschlagene Double zählt als Double-Versuch', () {
      final s = session('checkout', now,
          config: {'mode': 'descending', 'min': 40, 'max': 40, 'attempts': 2},
          details: {
            'attempts': [
              {'target': 40, 'success': true, 'darts': 2},
              {'target': 40, 'success': true, 'darts': 1},
            ],
          });
      final t = visits(s, [
        ['S20', 'D10', 'MISS'], // 40: Ziel D20, verfehlt; Rest 20: Ziel D10, Checkout; MISS zählt nicht
        ['D20'], // nächster Versuch 40: Ziel D20, Checkout
      ]);
      final aimed = StatsCalculator(sessions: [s], throws: t, now: now).aimedOf(s);
      // Erster Dart: Vorschlag für 40 ist D20.
      expect(aimed.first.aimedDouble, 20);
      expect(aimed.first.onTarget, isFalse);
      final r = StatsCalculator(sessions: [s], throws: t, now: now).report(StatsPeriod.all);
      expect(aimed.length, 3);
      expect(r.doubles[20]!.attempts, 2);
      expect(r.doubles[20]!.hits, 1);
      expect(r.doubles[10]!.hits, 1);
      expect(r.checkoutByRange[CheckoutRange.low]!.attempts, 2);
      expect(r.checkoutByRange[CheckoutRange.low]!.hits, 2);
    });

    test('T20-Training: Triple-Quote je Zahl aus den Würfen', () {
      final s = session('target_practice', now, metrics: {'trebles': 99, 'darts': 6});
      final t = visits(s, [
        ['T20', 'S20', 'T20'],
        ['S1', 'S5', 'T20'],
      ]);
      final r = StatsCalculator(sessions: [s], throws: t, now: now).report(StatsPeriod.all);
      expect(r.trebles[20]!.attempts, 6);
      expect(r.trebles[20]!.hits, 3);
      expect(r.trebleRate, 0.5);
      expect(r.trebleAttempts, 6);
    });

    test('Unbekanntes Spiel liefert keine Ziele', () {
      final s = session('gibt_es_nicht', now);
      expect(replayTargets(s, visits(s, [['T20']]), const {}), isEmpty);
    });

    test('segmentOf unterscheidet innere und äußere Single-Fläche', () {
      final s = session('around_the_clock', now);
      final row = visits(s, [['S1']]).single.copyWith(bed: Bed.singleInner.name);
      expect(segmentOf(row), Segment.single(1, inner: true));
    });
  });

  test('Neue Spiele wie X01: Average und First 9 aus den Kennzahlen, Verlauf über "average"', () {
    final x = session('x01', now, metrics: {'average': 60.0, 'first9': 72.0, 'darts': 30, 'highestCheckout': 81});
    final hs = session('highscore_hunt', now);
    final t = [
      ...visits(x, [
        ['T20', 'S20', 'S20'],
        ['S20', 'S20', 'S20'],
      ]),
      ...visits(hs, [
        ['S20', 'S20', 'S20'],
      ]),
    ];
    final calc = StatsCalculator(sessions: [x, hs], throws: t, now: now);
    final r = calc.report(StatsPeriod.all);
    // X01: 60 × 30 / 3 = 600 Punkte aus 30 Darts, Highscore: 60 aus 3.
    expect(r.scoringDarts, 33);
    expect(r.scoringAverage, closeTo(660 / 33 * 3, 1e-9));
    expect(r.first9Average, 72);
    expect(r.scoring!.visits, 3);
    expect(calc.trend('x01', StatsPeriod.all).single.value, 60);
    expect(r.games.firstWhere((g) => g.gameId == 'x01').best, 60);
    expect(PrimaryMetric.forGame('x01').key, 'average');
    expect(calc.metricKeys('x01', StatsPeriod.all).first, 'average');
    expect(calc.metricTrend('x01', 'first9', StatsPeriod.all).single.value, 72);
    expect(calc.playedGames, containsAll(['x01', 'highscore_hunt']));
    expect(calc.records().firstWhere((r) => r.kind == RecordKind.highestCheckout).value, 81);
  });

  test('Punkteverteilung und Konstanz aus vollen Aufnahmen', () {
    final s = session('highscore_hunt', now);
    final t = visits(s, [
      ['T20', 'T20', 'T20'], // 180
      ['S20', 'S1', 'S5'], // 26
      ['T20', 'T20', 'S20'], // 140
      ['T20', 'S20', 'S20'], // 100
      ['T20', 'S20'], // nicht voll, zählt nicht
    ]);
    final sc = StatsCalculator(sessions: [s], throws: t, now: now).report(StatsPeriod.all).scoring!;
    expect(sc.visits, 4);
    expect(sc.highest, 180);
    expect(sc.maxes, 1);
    expect(sc.ton40s, 2);
    expect(sc.tons, 3);
    expect(sc.under40, 1);
    expect(sc.count(ScoreBand.ton), 1);
    expect(sc.mean, closeTo(111.5, 1e-9));
    expect(sc.stdDev, closeTo(56.89, 0.01));
    expect(sc.rate(sc.tons), 0.75);
    expect(ScoreBand.of(39), ScoreBand.under40);
    expect(ScoreBand.of(60), ScoreBand.from60);
    expect(ScoreBand.of(180), ScoreBand.maximum);
  });

  test('Vergleich mit dem Zeitraum davor', () {
    final calc = StatsCalculator(sessions: [
      session('bull_drill', now.subtract(const Duration(days: 2))),
      session('bull_drill', now.subtract(const Duration(days: 8))),
      session('bull_drill', now.subtract(const Duration(days: 13))),
      session('bull_drill', now.subtract(const Duration(days: 14))),
    ], throws: const [], now: now);
    expect(calc.report(StatsPeriod.week).sessions, 1);
    final prev = calc.previousReport(StatsPeriod.week)!;
    expect(prev.sessions, 2);
    expect(prev.dailyDarts.length, 7);
    expect(prev.dailyDarts.last.day, DateTime(2026, 10, 4));
    expect(calc.previousReport(StatsPeriod.all), isNull);
  });

  test('Gleitender Durchschnitt', () {
    expect(StatsCalculator.movingAverage([10, 20, 30, 40], 2), [10, 15, 25, 35]);
    expect(StatsCalculator.movingAverage([], 3), isEmpty);
  });

  test('Trainingsmuster: Wochentage, Tageszeiten, Wochen, Trainingszeit, Average-Verlauf', () {
    final mon = session('highscore_hunt', DateTime(2026, 10, 5, 8)); // Montag Morgen
    final sun = session('highscore_hunt', DateTime(2026, 10, 11, 19), length: const Duration(hours: 5)); // Sonntag Abend
    final prevWeek = session('bull_drill', DateTime(2026, 9, 30, 23)); // Mittwoch Nacht
    final t = [
      ...visits(mon, [
        ['S20', 'S20', 'S20'],
      ]),
      ...visits(sun, [
        ['T20', 'T20', 'T20'],
      ]),
      ...visits(prevWeek, [
        ['BULL'],
      ]),
    ];
    final r = StatsCalculator(sessions: [mon, sun, prevWeek], throws: t, now: now).report(StatsPeriod.month);
    expect(r.weekdays[0].sessions, 1);
    expect(r.weekdays[0].average, 60);
    expect(r.weekdays[6].average, 180);
    expect(r.weekdays[2].darts, 1);
    expect(r.weekdays[2].average, isNull);
    expect(r.dayParts[DayPart.morning.index].sessions, 1);
    expect(r.dayParts[DayPart.evening.index].average, 180);
    expect(r.dayParts[DayPart.night.index].sessions, 1);
    expect(r.weekly.last.weekStart, DateTime(2026, 10, 5));
    expect(r.weekly.last.bucket.darts, 6);
    expect(r.weekly[r.weekly.length - 2].bucket.sessions, 1);
    // 20 + 20 Minuten, die 5-Stunden-Session zählt höchstens 3 Stunden.
    expect(r.trainingTime, const Duration(hours: 3, minutes: 40));
    expect(r.averageTrend.map((p) => p.value), [60, 180]);
  });

  test('Persönliche Rekorde mit Datum', () {
    final a = session('highscore_hunt', DateTime(2026, 10, 1, 18));
    final b = session('highscore_hunt', DateTime(2026, 10, 2, 18));
    final c = session('highscore_hunt', DateTime(2026, 10, 3, 18));
    final co = session('checkout', DateTime(2026, 10, 3, 19), details: {
      'attempts': [
        {'target': 100, 'success': true, 'darts': 3},
        {'target': 120, 'success': false, 'darts': 3},
      ],
    });
    final t = [
      ...visits(a, [
        ['T20', 'T20', 'T20'],
        ['T20', 'T20', 'T20'],
        ['S20', 'S20', 'S20'],
      ]),
      ...visits(b, [
        ['T20', 'T20', 'S20'],
        ['T20', 'T20', 'T20'],
        ['T20', 'T20', 'T20'],
        ['T20', 'T20', 'T20'],
      ]),
      ...visits(c, [
        ['S1', 'S1', 'S1'],
      ]),
    ];
    final records = {for (final r in StatsCalculator(sessions: [a, b, c, co], throws: t, now: now).records()) r.kind: r};
    expect(records[RecordKind.bestAverage]!.value, closeTo(170, 1e-9));
    expect(records[RecordKind.bestAverage]!.date, b.startedAt);
    expect(records[RecordKind.highestVisit]!.value, 180);
    expect(records[RecordKind.highestVisit]!.date!.day, 1);
    expect(records[RecordKind.most180s]!.value, 3);
    expect(records[RecordKind.highestCheckout]!.value, 100);
    expect(records[RecordKind.mostDartsDay]!.value, 12);
    expect(records[RecordKind.mostDartsDay]!.date, DateTime(2026, 10, 2));
    expect(records[RecordKind.longestStreak]!.value, 3);
    expect(records[RecordKind.longestStreak]!.date, DateTime(2026, 10, 3));
    expect(records.containsKey(RecordKind.bestFirst9), isFalse);
  });

  test('Bestwert je Spiel mit Datum', () {
    final a = session('bobs_27', DateTime(2026, 10, 1), metrics: {'score': 80});
    final b = session('bobs_27', DateTime(2026, 10, 2), metrics: {'score': 40});
    final g = StatsCalculator(sessions: [a, b], throws: const [], now: now).report(StatsPeriod.all).games.single;
    expect(g.best, 80);
    expect(g.bestAt, a.startedAt);
    expect(g.last, 40);
  });
}
