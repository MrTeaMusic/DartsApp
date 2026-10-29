import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/plans/domain/auto_plan.dart';
import 'package:dartlab/features/progress/domain/achievement_tracker.dart';
import 'package:dartlab/features/progress/domain/achievements.dart';
import 'package:dartlab/features/progress/domain/session_facts.dart';
import 'package:dartlab/features/stats/domain/goals.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// 121 zählt nicht zu normalen Finishes: Ein Ziel hat dort mehrere
/// Aufnahmen, das Finish ist kein 3-Dart-Finish. Die Tests spielen echte
/// Sessions durch, damit Kennzahlen, Details und Würfe zusammenpassen.
final now = DateTime(2026, 10, 11, 18);
DateTime day(int d, [int h = 18]) => DateTime(2026, 10, d, h);
var _id = 0;

(SessionRow, List<ThrowRow>) played(String gameId, Map<String, Object?> config, List<String> names, {required DateTime start}) {
  final game = GameCatalog.byId(gameId)!.start(config, 1)..prepare();
  final sid = ++_id;
  final throws = <ThrowRow>[];
  var seq = 0;
  for (final n in names) {
    if (game.visitClosed) game.endVisit();
    final seg = Segment.tryParse(n)!;
    final counted = game.acceptsDarts;
    final visit = game.visitIndex + (game.visitClosed || game.physicalDartsInVisit >= 3 ? 1 : 0);
    final at = start.add(Duration(seconds: seq * 5));
    game.throwDart(DartThrow(segment: seg, timestamp: at, source: DartSourceKind.manual));
    throws.add(ThrowRow(
      id: ++_id,
      sessionId: sid,
      playerId: 1,
      gameId: gameId,
      seq: seq++,
      visitIndex: visit,
      counted: counted,
      segment: seg.name,
      number: seg.number,
      multiplier: seg.multiplier,
      bed: seg.bed.name,
      score: seg.score,
      source: 'manual',
      timestamp: at,
    ));
  }
  final session = SessionRow(
    id: sid,
    uid: 's$sid',
    playerId: 1,
    gameId: gameId,
    configJson: jsonEncode(config),
    seed: 1,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 10)),
    finished: game.finished,
    resultJson: jsonEncode(game.result.toJson()),
    dartCount: throws.length,
  );
  return (session, throws);
}

StatsCalculator calcOf(List<(SessionRow, List<ThrowRow>)> games) =>
    StatsCalculator(sessions: [for (final g in games) g.$1], throws: [for (final g in games) ...g.$2], now: now);

/// 121 mit Start 170 und 9 Darts je Ziel: 170 (T20, T20, Bull) in der dritten
/// Aufnahme, also in 9 Darts statt 3.
(SessionRow, List<ThrowRow>) bigFinish121({int dartsPerAttempt = 9, DateTime? start}) => played(
      'one_twenty_one',
      {'start': 170, 'dartsPerAttempt': dartsPerAttempt, 'rounds': 1, 'failRule': 'back', 'doubleOut': true},
      [...List.filled(6, 'MISS'), 'T20', 'T20', 'BULL'],
      start: start ?? day(10),
    );

/// Checkout-Training: 100 mit T20 und D20.
(SessionRow, List<ThrowRow>) checkout100({DateTime? start}) => played(
      'checkout',
      {'mode': 'descending', 'min': 100, 'max': 100, 'attempts': 1, 'dartsPerAttempt': 3, 'doubleOut': true},
      ['T20', 'D20'],
      start: start ?? day(9),
    );

void main() {
  group('Rekorde', () {
    test('121-Finish zählt nicht als höchstes Finish, Checkout-Training schon', () {
      final big = bigFinish121();
      final co = checkout100();
      // Die Session meldet ihr Finish weiter in der eigenen Wertung.
      expect(jsonDecode(big.$1.resultJson!)['metrics']['highestCheckout'], 170);

      final both = calcOf([big, co]).records().where((r) => r.kind == RecordKind.highestCheckout).single;
      expect(both.value, 100);

      // Nur 121: kein Rekord „Höchstes Finish“.
      expect(calcOf([big]).records().where((r) => r.kind == RecordKind.highestCheckout), isEmpty);
    });

    test('Der Bestwert von 121 bleibt in der Wertung des Spiels', () {
      final report = calcOf([bigFinish121()]).report(StatsPeriod.all);
      expect(report.games.single.gameId, 'one_twenty_one');
      expect(report.games.single.best, 170);
    });

    test('Andere Spiele mit Kennzahl highestCheckout zählen weiter', () {
      final x01 = SessionRow(
        id: ++_id,
        uid: 's$_id',
        playerId: 1,
        gameId: 'x01',
        configJson: '{}',
        seed: 1,
        startedAt: day(8),
        endedAt: day(8, 19),
        finished: true,
        resultJson: jsonEncode({'metrics': {'average': 50, 'highestCheckout': 81}, 'details': {}}),
        dartCount: 3,
      );
      final calc = StatsCalculator(sessions: [x01, bigFinish121().$1], throws: const [], now: now);
      expect(calc.records().firstWhere((r) => r.kind == RecordKind.highestCheckout).value, 81);
    });
  });

  group('Checkout-Quote', () {
    test('121-Runden fließen weder in Quote noch in Quote nach Rest ein', () {
      final big = bigFinish121();
      final co = checkout100();
      final r = calcOf([big, co]).report(StatsPeriod.all);
      expect(r.checkoutAttempts, 1);
      expect(r.checkoutRate, 1);
      expect(r.checkoutByRange.keys.single, CheckoutRange.of(100));

      final only121 = calcOf([big]).report(StatsPeriod.all);
      expect(only121.checkoutAttempts, 0);
      expect(only121.checkoutRate, isNull);
      expect(only121.checkoutByRange, isEmpty);
    });

    test('Verpasste 121-Runden senken die Quote nicht', () {
      final co = checkout100();
      final failed = SessionRow(
        id: ++_id,
        uid: 's$_id',
        playerId: 1,
        gameId: 'one_twenty_one',
        configJson: '{}',
        seed: 1,
        startedAt: day(10),
        endedAt: day(10, 19),
        finished: true,
        resultJson: jsonEncode({
          'metrics': {'highestCheckout': 0},
          'details': {
            'rounds': [
              for (var i = 0; i < 10; i++) {'target': 121, 'success': false, 'darts': 9},
            ],
          },
        }),
        dartCount: 90,
      );
      final calc = StatsCalculator(sessions: [co.$1, failed], throws: co.$2, now: now);
      expect(calc.report(StatsPeriod.all).checkoutRate, 1);
    });

    test('Ziel „Checkout-Quote“ rechnet ohne 121', () {
      GoalRow goal() => GoalRow(id: ++_id, uid: 'g$_id', playerId: 1, kind: GoalKind.checkoutRate.name, target: 30, createdAt: now);
      final big = bigFinish121(start: day(5));
      expect(goalProgress([goal()], calcOf([big])).single.current, isNull);
      final withCheckout = goalProgress([goal()], calcOf([big, checkout100(start: day(6))])).single;
      expect(withCheckout.current, 100);
    });
  });

  group('Auto-Plan', () {
    test('Zehn verpasste 121-Ziele ergeben keine Checkout-Schwäche', () {
      final failed = SessionRow(
        id: ++_id,
        uid: 's$_id',
        playerId: 1,
        gameId: 'one_twenty_one',
        configJson: '{}',
        seed: 1,
        startedAt: day(10),
        endedAt: day(10, 19),
        finished: true,
        resultJson: jsonEncode({
          'metrics': {'highestCheckout': 0},
          'details': {
            'rounds': [
              for (var i = 0; i < 10; i++) {'target': 70, 'success': false, 'darts': 9},
            ],
          },
        }),
        dartCount: 90,
      );
      final report = StatsCalculator(sessions: [failed], throws: const [], now: now).report(StatsPeriod.all);
      final weaknesses = AutoPlanGenerator.weaknesses(AutoPlanInput.fromReport(report));
      expect(weaknesses.where((w) => w.kind == WeaknessKind.checkout), isEmpty);
    });
  });

  group('Erfolge', () {
    test('121-Finish (170 mit Bull) zählt für keinen Finish-Erfolg', () {
      final big = bigFinish121();
      final calc = calcOf([big]);
      final facts = sessionFacts(calc, big.$1);
      expect(facts.highestCheckout, 0);
      expect(facts.checkouts, 0);
      expect(facts.bullFinishes, 0);
      final t = AchievementTracker.fromCalculator(calc);
      for (final id in ['finish_100', 'finish_170', 'finish_bull', 'checkouts']) {
        expect(t.tierOf(AchievementCatalog.byId(id)!), 0, reason: id);
      }
      expect(t.value(AchievementMetric.highestCheckout), isNull);
      expect(t.value(AchievementMetric.checkouts), isNull);
    });

    test('Auch mit nur einer Aufnahme je Ziel zählt 121 nicht als normales Finish', () {
      final g = played(
        'one_twenty_one',
        {'start': 170, 'dartsPerAttempt': 3, 'rounds': 1, 'failRule': 'back', 'doubleOut': true},
        ['T20', 'T20', 'BULL'],
        start: day(10),
      );
      expect(jsonDecode(g.$1.resultJson!)['metrics']['checkouts'], 1);
      final facts = sessionFacts(calcOf([g]), g.$1);
      expect(facts.checkouts, 0);
      expect(facts.highestCheckout, 0);
    });

    test('Normales Finish im Checkout-Training zählt weiter, 121 daneben ändert nichts', () {
      final co = checkout100();
      final alone = AchievementTracker.fromCalculator(calcOf([co]));
      final withBig = AchievementTracker.fromCalculator(calcOf([co, bigFinish121()]));
      expect(sessionFacts(calcOf([co]), co.$1).highestCheckout, 100);
      expect(alone.tierOf(AchievementCatalog.byId('finish_100')!), 0); // 101 nötig
      expect(alone.value(AchievementMetric.highestCheckout), 100);
      expect(alone.value(AchievementMetric.checkouts), 1);
      expect(withBig.value(AchievementMetric.highestCheckout), 100);
      expect(withBig.value(AchievementMetric.checkouts), 1);
      expect(withBig.tierOf(AchievementCatalog.byId('finish_170')!), 0);
    });

    test('Ein 170er-Finish im Checkout-Training zählt weiter', () {
      final g = played(
        'checkout',
        {'mode': 'descending', 'min': 170, 'max': 170, 'attempts': 1, 'dartsPerAttempt': 3},
        ['T20', 'T20', 'BULL'],
        start: day(10),
      );
      final t = AchievementTracker.fromCalculator(calcOf([g]));
      expect(t.tierOf(AchievementCatalog.byId('finish_170')!), 1);
      expect(t.tierOf(AchievementCatalog.byId('finish_bull')!), 1);
    });
  });

  group('Doppel-Statistik', () {
    test('Darts aus 121 zählen weiter als Checkout-Darts aufs Doppel', () {
      final g = played(
        'one_twenty_one',
        {'start': 40, 'dartsPerAttempt': 9, 'rounds': 1, 'failRule': 'back', 'doubleOut': true},
        ['S20', 'D10'],
        start: day(10),
      );
      final stats = calcOf([g]).doubleStats(StatsPeriod.all);
      expect(stats.checkout.attempts, greaterThan(0));
      expect(stats.checkout.hits, 1);
      expect(stats[10]!.count.hits, 1);
    });
  });
}
