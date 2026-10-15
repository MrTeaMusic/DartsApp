import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/stats/data/stats_repository.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/history_seed.dart';
import '../../helpers/online_seed.dart';

final now = DateTime(2026, 10, 15, 21);
var _id = 0;

SessionRow session(
  String gameId,
  DateTime start, {
  Map<String, Object?> metrics = const {},
  Map<String, Object?> details = const {},
  Map<String, Object?> config = const {},
  Duration length = const Duration(minutes: 30),
}) =>
    SessionRow(
      id: ++_id,
      uid: 's$_id',
      playerId: 1,
      gameId: gameId,
      configJson: jsonEncode(config),
      seed: 1,
      startedAt: start,
      endedAt: start.add(length),
      finished: true,
      resultJson: jsonEncode({'metrics': metrics, 'details': details}),
      dartCount: 0,
    );

/// Würfe in Aufnahmen; [counted] gilt für alle.
List<ThrowRow> visits(SessionRow s, List<List<String>> names, {bool counted = true}) {
  final out = <ThrowRow>[];
  var seq = 0;
  for (final (v, list) in names.indexed) {
    for (final n in list) {
      final seg = Segment.tryParse(n)!;
      out.add(ThrowRow(
        id: ++_id,
        sessionId: s.id,
        playerId: 1,
        gameId: s.gameId,
        seq: seq++,
        visitIndex: v,
        counted: counted,
        segment: seg.name,
        number: seg.number,
        multiplier: seg.multiplier,
        bed: seg.bed.name,
        score: seg.score,
        x: null,
        y: null,
        source: 'autodartsLocal',
        timestamp: s.startedAt,
        rawJson: null,
      ));
    }
  }
  return out;
}

/// Live-Session mit X01, Legs wie in `LiveX01.result`.
SessionRow liveX01(DateTime start, {double average = 50, int darts = 90, double? first9, int won = 1, int lost = 1,
    int checkoutDarts = 4, int highest = 40, List<Map<String, Object?>> legs = const [], Map<String, Object?> config = const {}}) =>
    session('x01_live', start,
        metrics: {
          'darts': darts,
          'average': average,
          'first9': ?first9,
          'legsWon': won,
          'legsLost': lost,
          'checkoutDarts': checkoutDarts,
          'highestFinish': highest,
          'count100': 3,
          'count140': 1,
          'count180': 0,
        },
        details: {'legs': legs},
        config: config);

Map<String, Object?> leg(int darts, int points, double first9, {int checkout = 0, bool won = false}) =>
    {'darts': darts, 'points': points, 'first9': first9, 'checkout': checkout, 'won': won};

void main() {
  group('Online-Matches', () {
    test('Live-Session wird zum Match-Eintrag mit Legs; ohne X01 der Rohschnitt', () {
      final x = liveX01(now.subtract(const Duration(hours: 2)),
          average: 52.4,
          first9: 61,
          legs: [leg(21, 501, 66, checkout: 40, won: true), leg(18, 380, 56)]);
      final raw = session('autodarts_live', now.subtract(const Duration(hours: 5)), metrics: {'rawAverage': 45, 'count100': 2});
      final rawThrows = visits(raw, [
        ['T20', 'S20', 'S1'],
        ['S5', 'S20', 'S20'],
      ]);
      final calc = StatsCalculator(sessions: [x, raw], throws: rawThrows, now: now);

      final m = calc.onlineMatchOf(x)!;
      expect(m.x01, isTrue);
      expect(m.average, closeTo(52.4, 1e-9));
      expect(m.first9, 61);
      expect((m.legsWon, m.legsLost), (1, 1));
      expect(m.checkout.attempts, 4);
      expect(m.checkout.hits, 1);
      expect(m.legs.map((l) => l.won), [true, false]);
      expect(m.legs.first.average, closeTo(501 / 21 * 3, 1e-9));
      expect(m.tons, 4);
      expect(m.duration, const Duration(minutes: 30));

      final r = calc.onlineMatchOf(raw)!;
      expect(r.x01, isFalse);
      expect(r.average, closeTo((60 + 20 + 1 + 5 + 20 + 20) / 6 * 3, 1e-9));
      expect(r.hasLegs, isFalse);
      expect(r.legs, isEmpty);

      expect(calc.onlineMatchOf(session('x01', now)), isNull);
    });

    test('Bericht: Zeitraum, neueste zuerst, Summen und Wochen', () {
      final old = liveX01(DateTime(2026, 8, 1, 20), average: 40, darts: 60, legs: [leg(30, 400, 40)]);
      final w1 = liveX01(DateTime(2026, 9, 29, 20), average: 50, darts: 90, legs: [leg(24, 501, 55, checkout: 32, won: true)]);
      final w2a = liveX01(DateTime(2026, 10, 6, 20), average: 60, darts: 60, won: 2, lost: 0, checkoutDarts: 5,
          highest: 81, legs: [leg(18, 501, 70, checkout: 81, won: true), leg(21, 501, 60, checkout: 20, won: true)]);
      final w2b = liveX01(DateTime(2026, 10, 9, 20), average: 45, darts: 30);
      final w3 = liveX01(DateTime(2026, 10, 14, 20), average: 55, darts: 90, legs: [leg(27, 501, 50, checkout: 16, won: true)]);
      final training = session('x01', DateTime(2026, 10, 14, 18), metrics: {'average': 70, 'darts': 45});
      final calc = StatsCalculator(sessions: [old, w1, w2a, w2b, w3, training], throws: const [], now: now);

      final month = calc.onlineReport(StatsPeriod.month);
      expect(month.matches.map((m) => m.sessionId), [w3.id, w2b.id, w2a.id, w1.id]);
      expect(month.totals.matches, 4);
      expect(month.totals.darts, 270);
      expect(month.totals.average, closeTo((50 * 90 + 60 * 60 + 45 * 30 + 55 * 90) / 270, 1e-9));
      expect(month.totals.first9, closeTo((55 + 70 + 60 + 50) / 4, 1e-9));
      expect(month.totals.highestFinish, 81);
      expect(month.totals.legsWon, 5);
      expect(month.weeks.map((w) => w.weekStart), [DateTime(2026, 9, 28), DateTime(2026, 10, 5), DateTime(2026, 10, 12)]);
      expect(month.weeks[1].totals.matches, 2);
      expect(month.byWeek, isTrue);
      final avg = month.trend(OnlineTrendMetric.average);
      expect(avg.length, 3);
      expect(avg[1].value, closeTo((60 * 60 + 45 * 30) / 90, 1e-9));
      // Checkout-Quote: nur Wochen mit Finish-Darts.
      expect(month.trend(OnlineTrendMetric.checkoutRate).length, 3);

      final week = calc.onlineReport(StatsPeriod.week);
      expect(week.matches.map((m) => m.sessionId), [w3.id, w2b.id]);
      expect(week.byWeek, isFalse);
      // Unter drei Wochen: Verlauf je Match, älteste zuerst.
      expect(week.trend(OnlineTrendMetric.average).map((p) => p.sessionId), [w2b.id, w3.id]);
      expect(week.trend(OnlineTrendMetric.first9).map((p) => p.sessionId), [w3.id]);

      expect(calc.onlineReport(StatsPeriod.all).matches.length, 5);
      // Zwischengespeichert: derselbe Bericht beim zweiten Aufruf.
      expect(identical(calc.onlineReport(StatsPeriod.month), month), isTrue);
    });

    test('Finish-Doppel online: X01 nachgespielt, mit „Leg verloren“', () {
      // Start 40 (eigene Config), Double-Out.
      final s = session('x01_live', now, config: {
        'x01': {'startScore': 40, 'outMode': 'double'},
      }, details: {
        'marks': [
          {'at': 5, 'kind': 'lost'},
        ],
      });
      final throws = visits(s, [
        // Rest 40 → D20 verfehlt (S20), Rest 20 → D10 verfehlt (S5), Rest 15: kein Doppel.
        ['S20', 'S5', 'S7'],
        // Rest 8 → D4 verfehlt, dann „Leg verloren“ nach 5 Darts.
        ['S4', 'S2'],
        // Neues Leg bei 40: D20 getroffen.
        ['D20'],
      ]);
      final calc = StatsCalculator(sessions: [s], throws: throws, now: now);
      final d = calc.liveDoublesOf(s);
      expect(d.keys.toSet(), {20, 10, 4, 2});
      expect((d[20]!.attempts, d[20]!.hits), (2, 1));
      expect((d[10]!.attempts, d[10]!.hits), (1, 0));
      expect((d[4]!.attempts, d[4]!.hits), (1, 0));
      // Ohne X01 gibt es keine Finish-Darts.
      final raw = session('autodarts_live', now);
      expect(calc.liveDoublesOf(raw), isEmpty);
    });
  });

  group('Training gegen Match', () {
    test('Zu wenig Daten: nichts vergleichbar, Mengen je Seite stimmen', () {
      final live = liveX01(now, average: 50, darts: 60, checkoutDarts: 6, legs: [leg(30, 501, 50, won: true)]);
      final x01 = session('x01', now, metrics: {'average': 60, 'darts': 45, 'checkoutDarts': 3, 'legsWon': 1});
      final calc = StatsCalculator(sessions: [live, x01], throws: const [], now: now);
      final c = calc.onlineComparison(StatsPeriod.month);
      expect(c.ready, isFalse);
      expect(c.average.online.amount, 60);
      expect(c.average.training.amount, 45);
      expect(c.average.diff, isNull);
      expect(c.first9.online.amount, 1);
      expect(c.checkout.online.amount, 6);
      expect(c.checkout.training.amount, 3);
    });

    test('Quellen je Kennzahl: Bot-Match zählt nicht, Scoring-Drill nur beim Average', () {
      final live = liveX01(now, average: 48, darts: 120, checkoutDarts: 20, won: 3, lost: 2, legs: [
        for (var i = 0; i < 5; i++) leg(24, 400, 50 + i.toDouble(), won: i < 3),
      ]);
      final solo = session('x01', now, metrics: {'average': 60, 'darts': 60, 'checkoutDarts': 10, 'legsWon': 3}, details: {
        'legs': [for (var i = 0; i < 3; i++) leg(20, 501, 66, won: true)],
      });
      final solo2 = session('x01', now, metrics: {'average': 60, 'darts': 40, 'checkoutDarts': 6, 'legsWon': 2}, details: {
        'legs': [for (var i = 0; i < 2; i++) leg(20, 501, 70, won: true)],
      });
      final drill = session('highscore_hunt', now);
      final drillThrows = visits(drill, [
        for (var i = 0; i < 10; i++) ['T20', 'S20', 'S20'],
      ]);
      // Bot-Match mit sehr gutem Average darf den Trainingswert nicht ändern.
      final bot = session('x01_match', now,
          metrics: {'average': 99, 'darts': 300, 'checkoutDarts': 50, 'legsWon': 50, 'first9': 99},
          details: {'legs': [for (var i = 0; i < 9; i++) leg(15, 501, 99, won: true)]});
      final calc = StatsCalculator(sessions: [live, solo, solo2, drill, bot], throws: drillThrows, now: now);
      final c = calc.onlineComparison(StatsPeriod.month);

      expect(c.average.training.amount, 130);
      expect(c.average.training.value, closeTo((60 * 100 + 100 * 30) / 130, 1e-9));
      expect(c.average.ready, isTrue);
      expect(c.average.diff, closeTo(48 - (60 * 100 + 100 * 30) / 130, 1e-9));

      expect(c.first9.online.value, closeTo(52, 1e-9));
      expect(c.first9.training.value, closeTo((66 * 3 + 70 * 2) / 5, 1e-9));
      expect(c.first9.ready, isTrue);
      expect(c.first9Notable, isTrue);

      expect(c.checkout.online.value, closeTo(3 / 20, 1e-9));
      expect(c.checkout.training.value, closeTo(5 / 16, 1e-9));
      expect(c.checkout.ready, isTrue);

      // Punkteverteilung: Training aus dem Drill (10 × 100).
      expect(c.trainingBands[ScoreBand.ton], 10);
      expect(c.scoring.training.value, 1.0);
      expect(c.scoring.ready, isFalse);
      expect(c.ready, isTrue);
    });

    test('Doppel je Zahl: Einbruch online, Schwelle und Reihenfolge', () {
      Map<int, HitCount> perDouble(Map<int, (int, int)> m) => {for (final e in m.entries) e.key: HitCount(e.value.$1, e.value.$2)};
      final c = OnlineComparison(
        average: const MetricComparison(CompareMetric.average, CompareSide.none, CompareSide.none),
        first9: const MetricComparison(CompareMetric.first9, CompareSide.none, CompareSide.none),
        checkout: const MetricComparison(CompareMetric.checkoutRate, CompareSide.none, CompareSide.none),
        doubles: const MetricComparison(CompareMetric.doubleRate, CompareSide(0.2, 60), CompareSide(0.34, 200)),
        scoring: const MetricComparison(CompareMetric.scoring, CompareSide.none, CompareSide.none),
        perDouble: {
          for (final n in [16, 8, 20, 10, 5])
            n: DoubleComparison(
              n,
              perDouble({16: (20, 3), 8: (10, 2), 20: (12, 5), 10: (5, 0), 5: (9, 4)})[n]!,
              perDouble({16: (50, 20), 8: (40, 16), 20: (30, 12), 10: (30, 15), 5: (6, 3)})[n]!,
            ),
        },
        onlineBands: const {},
        trainingBands: const {},
      );
      // D10 und D5 haben auf einer Seite zu wenig Darts.
      expect(c.ranked.map((d) => d.number), [16, 8, 20]);
      expect(c.perDouble[16]!.drop, closeTo(0.4 - 0.15, 1e-9));
      expect(c.notableDrops.map((d) => d.number), [16, 8]);
      expect(c.perDouble[20]!.notable, isFalse);
      expect(c.doublesNotable, isTrue);
      expect(c.ready, isTrue);
    });

    test('Zwischengespeichert und an den nächsten Rechner weitergegeben', () {
      final s = session('x01_live', now, config: {
        'x01': {'startScore': 40, 'outMode': 'double'},
      });
      final throws = visits(s, [
        ['D20'],
      ]);
      final calc = StatsCalculator(sessions: [s], throws: throws, now: now);
      final c = calc.onlineComparison(StatsPeriod.month);
      expect(identical(calc.onlineComparison(StatsPeriod.month), c), isTrue);
      final d = calc.liveDoublesOf(s);
      final m = calc.onlineMatchOf(s);
      final next = StatsCalculator(sessions: [s], throws: throws, now: now, previous: calc, unchanged: {s.id});
      expect(identical(next.liveDoublesOf(s), d), isTrue);
      expect(identical(next.onlineMatchOf(s), m), isTrue);
    });
  });

  group('Gespielte Daten (Datenbank)', () {
    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

    test('Nervöse Doppel online fallen im Vergleich auf', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = GameRepository(db);
      final player = await ProfileRepository(db).resolve(null);
      final day = DateTime.now();
      DateTime at(int daysAgo, int hour) => DateTime(day.year, day.month, day.day - daysAgo, hour);
      for (var i = 0; i < 6; i++) {
        await seedTraining(repo, player, 'x01', const {'startScore': 501, 'legs': 2}, at(i * 2, 17), seed: 10 + i, average: 60);
        await seedTraining(repo, player, 'checkout', const {'mode': 'random', 'min': 2, 'max': 40, 'attempts': 15},
            at(i * 2 + 1, 17), seed: 20 + i, average: 60);
      }
      for (var i = 0; i < 6; i++) {
        await seedOnlineMatch(repo, player, at(i * 2, 20),
            seed: 30 + i, average: 55, legs: 5, opponentMin: 9, opponentMax: 15, nervous: const {16: 0.7, 8: 0.7});
      }
      await seedOnlineMatch(repo, player, at(1, 21), seed: 50, x01: false, legs: 2);

      final calc = (await StatsRepository(db).watchCalculator(player).first);
      final report = calc.onlineReport(StatsPeriod.month);
      expect(report.matches.length, 7);
      expect(report.matches.where((m) => !m.x01).length, 1);
      expect(report.totals.legs, greaterThanOrEqualTo(20));
      expect(report.matches.first.legs, isNotEmpty);

      final c = calc.onlineComparison(StatsPeriod.month);
      expect(c.average.ready, isTrue);
      expect(c.first9.ready, isTrue);
      expect(c.doubles.ready, isTrue);
      // Online werden D16 und D8 absichtlich verfehlt.
      final d16 = c.perDouble[16];
      expect(d16, isNotNull);
      expect(d16!.online.rate!, lessThan(d16.training.rate ?? 1));
      expect(c.notableDrops.map((d) => d.number), contains(8));
      expect(c.doubles.diff!, lessThan(0));
    });
  });
}
