import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:dartlab/features/stats/presentation/period_picker.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 3, 20);
var _id = 0;

SessionRow liveX01(DateTime start, {int startScore = 101, List<Map<String, Object?>> marks = const []}) => SessionRow(
      id: ++_id,
      uid: 's$_id',
      playerId: 1,
      gameId: 'x01_live',
      configJson: jsonEncode({
        'x01': {'startScore': startScore, 'outMode': 'double'},
      }),
      seed: 1,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 20)),
      finished: true,
      resultJson: jsonEncode({
        'metrics': {'darts': 9, 'average': 60, 'legsWon': 2, 'legsLost': 0, 'checkoutDarts': 3},
        'details': {'marks': marks},
      }),
      dartCount: 9,
    );

List<ThrowRow> visits(SessionRow s, List<List<String>> names) {
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
        counted: true,
        segment: seg.name,
        number: seg.number,
        multiplier: seg.multiplier,
        bed: seg.bed.name,
        score: seg.score,
        x: 0.1,
        y: -0.5,
        source: 'autodartsLocal',
        timestamp: s.startedAt.add(Duration(seconds: seq)),
        rawJson: null,
      ));
    }
  }
  return out;
}

/// Zwei Legs ab 101: T20 S1 D20 (Checkout aus 101), dann S20 S20 S20 (kein
/// Checkout aus 101) und S9 S16 D8 (Checkout aus 41, D16 verfehlt).
const twoLegs = [
  ['T20', 'S1', 'D20'],
  ['S20', 'S20', 'S20'],
  ['S9', 'S16', 'D8'],
];

void main() {
  group('Online-Matches in Doppel & Finish', () {
    test('Darts aufs Finish-Doppel zählen in Doppel im Detail und in der Doppelquote', () {
      final s = liveX01(now.subtract(const Duration(days: 1)));
      final calc = StatsCalculator(sessions: [s], throws: visits(s, twoLegs), now: now);

      final d = calc.doubleStats(StatsPeriod.month);
      expect(d.perDouble.keys.toSet(), {20, 16, 8});
      expect(d[20]!.count.hits, 1);
      expect(d[16]!.count.hits, 0);
      expect(d[16]!.mainMiss, DoubleMiss.inside);
      expect(d[8]!.count.hits, 1);
      // Mit Position fürs Streubild.
      expect(d[20]!.scatter, hasLength(1));
      // Die Checkout-Darts kommen weiter aus den Kennzahlen (nicht doppelt).
      expect(d.checkout.attempts, 3);
      expect(d.training.attempts, 0);
      // Verlauf: alle drei in den letzten 30 Tagen.
      expect(d.trends[20]!.recent.attempts, 1);

      final r = calc.report(StatsPeriod.month);
      expect(r.doubles[20]!.attempts, 1);
      expect(r.doubles[16]!.attempts, 1);
      expect(r.doubleRate, closeTo(2 / 3, 1e-9));
    });

    test('Checkout-Quote nach Rest: jede Aufnahme mit checkbarem Rest ist ein Versuch', () {
      final s = liveX01(now.subtract(const Duration(days: 1)));
      final calc = StatsCalculator(sessions: [s], throws: visits(s, twoLegs), now: now);
      final r = calc.report(StatsPeriod.month);

      expect(r.checkoutAttempts, 3);
      expect(r.checkoutRate, closeTo(2 / 3, 1e-9));
      final big = r.checkoutByRange[CheckoutRange.big]!;
      expect((big.hits, big.attempts), (1, 2));
      final mid = r.checkoutByRange[CheckoutRange.mid]!;
      expect((mid.hits, mid.attempts), (1, 1));
    });

    test('Über 170 und Bogey-Reste sind keine Checkout-Chance', () {
      final s = liveX01(now.subtract(const Duration(days: 1)), startScore: 301);
      // 301 → 169 → 166 → 163: drei Bogey-Reste in Folge.
      final calc = StatsCalculator(sessions: [s], throws: visits(s, [
        ['T20', 'T20', 'S12'],
        ['S1', 'S1', 'S1'],
        ['S1', 'S1', 'S1'],
      ]), now: now);
      expect(calc.report(StatsPeriod.month).checkoutAttempts, 0);
    });

    test('Ein neu gestartetes Leg (Rest stimmte nicht) zählt nicht', () {
      final s = liveX01(now.subtract(const Duration(days: 1)), marks: [
        {'at': 6, 'kind': 'restart'},
      ]);
      final calc = StatsCalculator(sessions: [s], throws: visits(s, [
        ['T20', 'S1', 'D20'],
        ['S20', 'S20', 'S20'],
        ['T20', 'S1', 'D20'],
      ]), now: now);
      final r = calc.report(StatsPeriod.month);
      // Leg 1 (Checkout) und das neue Leg (Checkout); die Aufnahme davor fällt weg.
      expect(r.checkoutAttempts, 2);
      expect(r.checkoutRate, 1);
    });
  });

  group('Eigener Zeitraum', () {
    test('Tage, Reihenfolge, Gleichheit', () {
      final p = StatsPeriod.custom(DateTime(2026, 10, 31, 18), DateTime(2026, 10, 2));
      expect(p.from, DateTime(2026, 10, 2));
      expect(p.to, DateTime(2026, 10, 31));
      expect(p.days, 30);
      expect(StatsPeriod.custom(DateTime(2026, 11, 3), DateTime(2026, 11, 3)).days, 1);
      // Über die Zeitumstellung (25.10.) hinweg.
      expect(StatsPeriod.custom(DateTime(2026, 10, 24), DateTime(2026, 10, 26)).days, 3);
      expect(p, StatsPeriod.custom(DateTime(2026, 10, 2), DateTime(2026, 10, 31)));
      expect(p == StatsPeriod.month, isFalse);
      expect(StatsPeriod.values, hasLength(4));
    });

    test('Sessions nur zwischen Von und Bis (beide Tage eingeschlossen)', () {
      final a = liveX01(DateTime(2026, 10, 1, 23, 30));
      final b = liveX01(DateTime(2026, 10, 2, 0, 5));
      final c = liveX01(DateTime(2026, 10, 3, 23, 59));
      final d = liveX01(DateTime(2026, 10, 4, 0, 1));
      final calc = StatsCalculator(sessions: [a, b, c, d], throws: const [], now: now);
      final p = StatsPeriod.custom(DateTime(2026, 10, 2), DateTime(2026, 10, 3));
      expect(calc.sessionsIn(p).map((s) => s.id), [b.id, c.id]);
      expect(calc.report(p).sessions, 2);
      expect(calc.report(StatsPeriod.custom(DateTime(2026, 10, 4), DateTime(2026, 10, 4))).sessions, 1);
      // Tagesverlauf genau über den Zeitraum.
      expect(calc.report(p).dailyDarts.map((e) => e.day), [DateTime(2026, 10, 2), DateTime(2026, 10, 3)]);
    });

    test('Zeitraum davor und ein Jahr davor', () {
      final p = StatsPeriod.custom(DateTime(2026, 10, 10), DateTime(2026, 10, 16));
      expect(p.before(now), StatsPeriod.custom(DateTime(2026, 10, 3), DateTime(2026, 10, 9)));
      expect(StatsPeriod.week.before(now), StatsPeriod.custom(DateTime(2026, 10, 21), DateTime(2026, 10, 27)));
      expect(StatsPeriod.all.before(now), isNull);
      expect(const StatsCompare.yearAgo().resolve(p, now), StatsPeriod.custom(DateTime(2025, 10, 10), DateTime(2025, 10, 16)));
      expect(const StatsCompare.before().resolve(StatsPeriod.all, now), isNull);
      final b = StatsPeriod.custom(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      expect(StatsCompare.custom(b).resolve(StatsPeriod.all, now), b);
    });

    test('Beschriftung', () {
      expect(formatPeriodRange(StatsPeriod.custom(DateTime(2026, 10, 4), DateTime(2026, 11, 2)), now), '4.10.–2.11.');
      expect(formatPeriodRange(StatsPeriod.custom(DateTime(2026, 11, 2), DateTime(2026, 11, 2)), now), '2.11.');
      expect(formatPeriodRange(StatsPeriod.custom(DateTime(2025, 12, 1), DateTime(2026, 1, 3)), now), '1.12.2025–3.1.2026');
      expect(formatPeriodRange(StatsPeriod.week, now), '28.10.–3.11.');
    });
  });
}
