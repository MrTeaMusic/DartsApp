import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 11, 18);
var _id = 0;

SessionRow session(String gameId, DateTime start,
        {Map<String, Object?> metrics = const {},
        Map<String, Object?> details = const {},
        Map<String, Object?> config = const {}}) =>
    SessionRow(
      id: ++_id,
      uid: 's$_id',
      playerId: 1,
      gameId: gameId,
      configJson: jsonEncode(config),
      seed: 7,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 20)),
      finished: true,
      resultJson: jsonEncode({'metrics': metrics, 'details': details}),
      dartCount: 3,
    );

/// Würfe einer Session; jede innere Liste ist eine Aufnahme. Mit
/// [positions] bekommt jeder Dart eine Position (wie im Simulator).
List<ThrowRow> visits(SessionRow s, List<List<String>> names, {bool positions = false}) {
  final out = <ThrowRow>[];
  var seq = 0;
  for (final (v, visit) in names.indexed) {
    for (final name in visit) {
      final seg = Segment.tryParse(name)!;
      final p = seg.isMiss ? const BoardPoint(0, 1.1) : BoardGeometry.centerOf(seg);
      out.add(ThrowRow(
        id: ++_id,
        sessionId: s.id,
        playerId: 1,
        gameId: s.gameId,
        seq: seq,
        visitIndex: v,
        counted: true,
        segment: seg.name,
        number: seg.number,
        multiplier: seg.multiplier,
        bed: seg.bed.name,
        score: seg.score,
        x: positions ? p.x : null,
        y: positions ? p.y : null,
        source: positions ? 'simulator' : 'manual',
        timestamp: s.startedAt.add(Duration(seconds: seq * 10)),
        rawJson: null,
      ));
      seq++;
    }
  }
  return out;
}

DoubleAttempt attempt(int target, String landed,
        {DateTime? time, BoardPoint? position, DoubleSource source = DoubleSource.training}) =>
    DoubleAttempt(
      target: target,
      landed: Segment.tryParse(landed)!,
      time: time ?? now,
      position: position,
      source: source,
    );

void main() {
  group('Daneben-Richtung', () {
    test('Doppel: außen, innen, seitlich', () {
      expect(classifyDoubleMiss(16, Segment.double(16)), isNull);
      expect(classifyDoubleMiss(16, Segment.miss), DoubleMiss.outside);
      expect(classifyDoubleMiss(16, Segment.single(16)), DoubleMiss.inside);
      expect(classifyDoubleMiss(16, Segment.single(16, inner: true)), DoubleMiss.inside);
      expect(classifyDoubleMiss(16, Segment.triple(16)), DoubleMiss.inside);
      expect(classifyDoubleMiss(16, Segment.outerBull), DoubleMiss.inside);
      expect(classifyDoubleMiss(16, Segment.double(8)), DoubleMiss.side);
      expect(classifyDoubleMiss(16, Segment.single(7)), DoubleMiss.side);
    });

    test('Bull: Single-Bull innen, Zahlen seitlich', () {
      expect(classifyDoubleMiss(25, Segment.bull), isNull);
      expect(classifyDoubleMiss(25, Segment.outerBull), DoubleMiss.inside);
      expect(classifyDoubleMiss(25, Segment.single(20, inner: true)), DoubleMiss.side);
      expect(classifyDoubleMiss(25, Segment.miss), DoubleMiss.outside);
    });
  });

  group('DoubleStats.build', () {
    test('Quote, Richtungen, Streubild und Checkout gegen Training', () {
      final stats = DoubleStats.build(
        attempts: [
          attempt(16, 'D16', position: const BoardPoint(0, 0.97), source: DoubleSource.checkout),
          attempt(16, 'MISS', position: const BoardPoint(0, 1.05), source: DoubleSource.checkout),
          attempt(16, 'MISS'),
          attempt(16, 'S16'),
          attempt(16, 'D8', source: DoubleSource.none),
          attempt(20, 'D20'),
        ],
        now: now,
        extraCheckout: const HitCount(4, 1),
      );
      final d16 = stats[16]!;
      expect(d16.count.attempts, 5);
      expect(d16.count.hits, 1);
      expect(d16.missesOf(DoubleMiss.outside), 2);
      expect(d16.missesOf(DoubleMiss.inside), 1);
      expect(d16.missesOf(DoubleMiss.side), 1);
      expect(d16.share(DoubleMiss.outside), closeTo(0.4, 1e-9));
      expect(d16.mainMiss, DoubleMiss.outside);
      expect(d16.scatter.length, 2);
      expect(d16.scatter.where((a) => a.hit).length, 1);
      // 2 Checkout-Darts plus 4 aus den X01-Kennzahlen; D8 (X01) zählt nicht doppelt.
      expect(stats.checkout.attempts, 6);
      expect(stats.checkout.hits, 2);
      expect(stats.training.attempts, 3);
      expect(stats.training.hits, 1);
      expect(stats.mostThrown, 16);
      expect(stats[20]!.mainMiss, isNull);
    });

    test('Meistgeworfenes Doppel: bei Gleichstand Zahl vor Bull, dann die höhere', () {
      final stats = DoubleStats.build(attempts: [attempt(25, 'BULL'), attempt(3, 'D3'), attempt(18, 'S18')], now: now);
      expect(stats.mostThrown, 18);
      expect(DoubleStats.build(attempts: const [], now: now).mostThrown, isNull);
    });

    test('Tipp erst ab zwei Doppeln mit genug Versuchen', () {
      List<DoubleAttempt> darts(int n, int hits, int total) =>
          [for (var i = 0; i < total; i++) attempt(n, i < hits ? 'D$n' : 'S$n')];
      final one = DoubleStats.build(attempts: [...darts(20, 3, 5), ...darts(16, 4, 4)], now: now);
      expect(one.bestFor(5), isNull);
      final two = DoubleStats.build(attempts: [...darts(20, 3, 5), ...darts(16, 2, 6), ...darts(8, 4, 4)], now: now);
      expect(two.bestFor(5)!.number, 20);
      expect(two.ranked(5).map((d) => d.number), [20, 16]);
    });

    test('Verlauf: letzte 30 Tage gegen die 30 davor, ab fünf Versuchen je Zeitraum', () {
      final recent = DateTime(2026, 10, 1);
      final before = DateTime(2026, 9, 1);
      final old = DateTime(2026, 7, 1);
      final stats = DoubleStats.build(
        attempts: const [],
        trendAttempts: [
          for (var i = 0; i < 5; i++) attempt(16, i < 3 ? 'D16' : 'S16', time: recent),
          for (var i = 0; i < 5; i++) attempt(16, i < 1 ? 'D16' : 'MISS', time: before),
          for (var i = 0; i < 5; i++) attempt(16, 'D16', time: old), // zu alt
          for (var i = 0; i < 5; i++) attempt(20, i < 2 ? 'D20' : 'S20', time: recent),
          for (var i = 0; i < 5; i++) attempt(20, i < 4 ? 'D20' : 'S20', time: before),
          for (var i = 0; i < 5; i++) attempt(8, 'D8', time: recent),
          for (var i = 0; i < 4; i++) attempt(8, 'S8', time: before),
          for (var i = 0; i < 5; i++) attempt(3, i < 2 ? 'D3' : 'S3', time: recent),
          for (var i = 0; i < 10; i++) attempt(3, i < 4 ? 'D3' : 'S3', time: before),
        ],
        now: now,
      );
      expect(stats.trends[16]!.recent.hits, 3);
      expect(stats.trends[16]!.before.attempts, 5);
      expect(stats.trends[16]!.direction, TrendDirection.up);
      expect(stats.trends[20]!.direction, TrendDirection.down);
      expect(stats.trends[8]!.direction, isNull);
      expect(stats.trends[3]!.direction, TrendDirection.flat);
      // Grenze: der 30. Tag zurück zählt noch zu „letzte 30 Tage“.
      final edge = DoubleStats.build(
        attempts: const [],
        trendAttempts: [attempt(1, 'D1', time: DateTime(2026, 9, 12, 0, 1)), attempt(1, 'S1', time: DateTime(2026, 9, 11, 23))],
        now: now,
      );
      expect(edge.trends[1]!.recent.attempts, 1);
      expect(edge.trends[1]!.before.attempts, 1);
    });
  });

  group('StatsCalculator.doubleStats', () {
    test("Bob's 27 mit Positionen, Checkout-Training und X01-Kennzahlen", () {
      final bobs = session('bobs_27', now.subtract(const Duration(days: 2)));
      final oldBobs = session('bobs_27', now.subtract(const Duration(days: 40)));
      final co = session('checkout', now.subtract(const Duration(days: 1)),
          config: {'mode': 'descending', 'min': 40, 'max': 40, 'attempts': 1},
          details: {
            'attempts': [
              {'target': 40, 'success': true, 'darts': 2},
            ],
          });
      final x01 = session('x01', now, metrics: {'checkoutDarts': 6, 'legsWon': 2, 'average': 50, 'darts': 3});
      final throws = [
        ...visits(bobs, [
          ['D1', 'MISS', 'S1'],
          ['S2', 'D3', 'T2'],
        ], positions: true),
        ...visits(oldBobs, [
          ['S1', 'S1', 'S1'],
        ]),
        // 40: Ziel D20, Single 20; Rest 20: Ziel D10, Checkout.
        ...visits(co, [
          ['S20', 'D10'],
        ]),
        ...visits(x01, [
          ['T20'],
        ]),
      ];
      final calc = StatsCalculator(sessions: [bobs, oldBobs, co, x01], throws: throws, now: now);
      final stats = calc.doubleStats(StatsPeriod.month);
      expect(stats[1]!.count.attempts, 3);
      expect(stats[1]!.count.hits, 1);
      expect(stats[1]!.missesOf(DoubleMiss.outside), 1);
      expect(stats[1]!.missesOf(DoubleMiss.inside), 1);
      expect(stats[1]!.scatter.length, 3);
      expect(stats[2]!.missesOf(DoubleMiss.side), 1);
      expect(stats[20]!.missesOf(DoubleMiss.inside), 1);
      expect(stats[20]!.scatter, isEmpty);
      expect(stats.training.attempts, 6);
      expect(stats.training.hits, 1);
      // Checkout-Training: 2 Darts, 1 Treffer; X01: 6 Darts, 2 Legs.
      expect(stats.checkout.attempts, 8);
      expect(stats.checkout.hits, 3);
      // Verlauf: D1 hat 3 Darts in den letzten 30 Tagen und 3 davor.
      expect(stats.trends[1]!.recent.attempts, 3);
      expect(stats.trends[1]!.before.attempts, 3);
      expect(stats.trends[1]!.direction, isNull);
      // Mit Spielfilter nur Bob's 27.
      final bobsOnly = calc.doubleStats(StatsPeriod.all, gameId: 'bobs_27');
      expect(bobsOnly.checkout.attempts, 0);
      expect(bobsOnly[1]!.count.attempts, 6);
    });
  });
}
