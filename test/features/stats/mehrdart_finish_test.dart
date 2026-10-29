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

/// Finishes mit mehr als 3 Darts je Versuch (Checkout-Training mit 6 oder 9
/// Darts, Catch 40 mit 6 Darts) und 121 sind keine normalen Finishes. Die
/// Tests spielen echte Sessions durch, damit Kennzahlen, Details und Würfe
/// zusammenpassen.
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

/// Checkout-Training auf genau einen Wert, mit [darts] Darts je Versuch.
(SessionRow, List<ThrowRow>) checkoutOf(int target, List<String> names, {int? darts, DateTime? start}) => played(
      'checkout',
      {
        'mode': 'descending',
        'min': target,
        'max': target,
        'attempts': 1,
        'dartsPerAttempt': ?darts,
        'doubleOut': true,
      },
      names,
      start: start ?? day(9),
    );

/// 170 mit T20, T20, Bull im Checkout-Training.
(SessionRow, List<ThrowRow>) big170({int? darts, DateTime? start}) =>
    checkoutOf(170, ['T20', 'T20', 'BULL'], darts: darts, start: start);

/// Verpasste Versuche als fertige Session mit eigener Konfiguration.
SessionRow failedAttempts(String gameId, Map<String, Object?> config, {int target = 70, int n = 10}) => SessionRow(
      id: ++_id,
      uid: 's$_id',
      playerId: 1,
      gameId: gameId,
      configJson: jsonEncode(config),
      seed: 1,
      startedAt: day(10),
      endedAt: day(10, 19),
      finished: true,
      resultJson: jsonEncode({
        'metrics': {'highestCheckout': 0},
        'details': {
          'attempts': [
            for (var i = 0; i < n; i++) {'target': target, 'success': false, 'darts': 6},
          ],
        },
      }),
      dartCount: n * 6,
    );

void main() {
  group('Regel', () {
    test('countsAsNormalFinish nach Spiel und Darts je Versuch', () {
      bool counts(String id, Map<String, Object?> config) => StatsCalculator.countsAsNormalFinish(SessionRow(
            id: ++_id,
            uid: 's$_id',
            playerId: 1,
            gameId: id,
            configJson: jsonEncode(config),
            seed: 1,
            startedAt: day(1),
            finished: true,
            dartCount: 0,
          ));
      expect(counts('checkout', const {}), isTrue); // Standard: 3 Darts
      expect(counts('checkout', const {'dartsPerAttempt': 3}), isTrue);
      expect(counts('checkout', const {'dartsPerAttempt': 6}), isFalse);
      expect(counts('checkout', const {'dartsPerAttempt': 9}), isFalse);
      expect(counts('catch_40', const {}), isFalse); // Standard: 6 Darts
      expect(counts('catch_40', const {'dartsPerTarget': 6}), isFalse);
      expect(counts('catch_40', const {'dartsPerTarget': 3}), isTrue);
      expect(counts('one_twenty_one', const {'dartsPerAttempt': 3}), isFalse);
      expect(counts('one_twenty_one', const {'dartsPerAttempt': 9}), isFalse);
      expect(counts('x01', const {}), isTrue);
      expect(counts('x01_match', const {}), isTrue);
    });
  });

  group('Rekorde', () {
    test('Finish mit 6 oder 9 Darts zählt nicht als höchstes Finish, 3 Darts schon', () {
      final six = big170(darts: 6);
      final nine = big170(darts: 9, start: day(8));
      final three = checkoutOf(100, ['T20', 'D20'], darts: 3, start: day(7));
      // Die Session meldet ihr Finish weiter in der eigenen Wertung.
      expect(jsonDecode(six.$1.resultJson!)['metrics']['highestCheckout'], 170);

      expect(calcOf([six, nine, three]).records().firstWhere((r) => r.kind == RecordKind.highestCheckout).value, 100);
      expect(calcOf([six, nine]).records().where((r) => r.kind == RecordKind.highestCheckout), isEmpty);
    });

    test('Ohne dartsPerAttempt in der Konfiguration gilt der Standard von 3 Darts', () {
      final g = checkoutOf(100, ['T20', 'D20']);
      expect(calcOf([g]).records().firstWhere((r) => r.kind == RecordKind.highestCheckout).value, 100);
    });

    test('Der Bestwert des Spiels bleibt auch mit 6 Darts', () {
      final report = calcOf([big170(darts: 6)]).report(StatsPeriod.all);
      expect(report.games.single.gameId, 'checkout');
      expect(report.games.single.best, 1); // Checkout-Quote: eigene Wertung
    });
  });

  group('Checkout-Quote', () {
    test('Versuche mit 6 Darts fließen weder in Quote noch in Quote nach Rest ein', () {
      final six = big170(darts: 6);
      final three = checkoutOf(100, ['T20', 'D20'], darts: 3, start: day(7));
      final r = calcOf([six, three]).report(StatsPeriod.all);
      expect(r.checkoutAttempts, 1);
      expect(r.checkoutRate, 1);
      expect(r.checkoutByRange.keys.single, CheckoutRange.of(100));

      final only6 = calcOf([six]).report(StatsPeriod.all);
      expect(only6.checkoutAttempts, 0);
      expect(only6.checkoutRate, isNull);
      expect(only6.checkoutByRange, isEmpty);
    });

    test('Verpasste Versuche mit 9 Darts senken die Quote nicht', () {
      final three = checkoutOf(100, ['T20', 'D20'], darts: 3);
      final failed = failedAttempts('checkout', {'dartsPerAttempt': 9});
      final calc = StatsCalculator(sessions: [three.$1, failed], throws: three.$2, now: now);
      expect(calc.report(StatsPeriod.all).checkoutRate, 1);
    });

    test('Ziel „Checkout-Quote“ rechnet nur mit 3-Dart-Versuchen', () {
      GoalRow goal() => GoalRow(id: ++_id, uid: 'g$_id', playerId: 1, kind: GoalKind.checkoutRate.name, target: 30, createdAt: now);
      final six = big170(darts: 6, start: day(5));
      expect(goalProgress([goal()], calcOf([six])).single.current, isNull);
      final withThree = goalProgress([goal()], calcOf([six, checkoutOf(100, ['T20', 'D20'], darts: 3, start: day(6))])).single;
      expect(withThree.current, 100);
    });
  });

  group('Auto-Plan', () {
    List<Weakness> weaknessesOf(SessionRow s) {
      final report = StatsCalculator(sessions: [s], throws: const [], now: now).report(StatsPeriod.all);
      return AutoPlanGenerator.weaknesses(AutoPlanInput.fromReport(report));
    }

    test('Zehn verpasste 6-Dart-Versuche ergeben keine Checkout-Schwäche', () {
      expect(weaknessesOf(failedAttempts('checkout', {'dartsPerAttempt': 6})).where((w) => w.kind == WeaknessKind.checkout), isEmpty);
    });

    test('Zehn verpasste 3-Dart-Versuche ergeben weiter eine Checkout-Schwäche', () {
      expect(weaknessesOf(failedAttempts('checkout', {'dartsPerAttempt': 3})).where((w) => w.kind == WeaknessKind.checkout), isNotEmpty);
    });
  });

  group('Erfolge', () {
    test('Checkout-Training mit 6 Darts: 170 mit Bull zählt für keinen Finish-Erfolg', () {
      final g = big170(darts: 6);
      final calc = calcOf([g]);
      final facts = sessionFacts(calc, g.$1);
      expect(facts.highestCheckout, 0);
      expect(facts.checkouts, 0);
      expect(facts.bullFinishes, 0);
      final t = AchievementTracker.fromCalculator(calc);
      for (final id in ['finish_100', 'finish_170', 'finish_bull', 'checkouts']) {
        expect(t.tierOf(AchievementCatalog.byId(id)!), 0, reason: id);
      }
      expect(t.value(AchievementMetric.highestCheckout), isNull);
    });

    test('Checkout-Training mit 3 Darts zählt weiter', () {
      final g = big170(darts: 3);
      final t = AchievementTracker.fromCalculator(calcOf([g]));
      expect(t.tierOf(AchievementCatalog.byId('finish_170')!), 1);
      expect(t.tierOf(AchievementCatalog.byId('finish_bull')!), 1);
      expect(t.value(AchievementMetric.checkouts), 1);
    });

    test('Catch 40 mit 6 Darts je Ziel zählt nicht, mit 3 Darts schon', () {
      List<(SessionRow, List<ThrowRow>)> catch40(int darts) =>
          [played('catch_40', {'min': 50, 'max': 50, 'dartsPerTarget': darts, 'doubleOut': true}, ['BULL'], start: day(10))];
      final six = catch40(6).single;
      expect(jsonDecode(six.$1.resultJson!)['metrics']['checkouts'], 1);
      final f6 = sessionFacts(calcOf([six]), six.$1);
      expect(f6.checkouts, 0);
      expect(f6.highestCheckout, 0);
      expect(f6.bullFinishes, 0);

      final three = catch40(3).single;
      final f3 = sessionFacts(calcOf([three]), three.$1);
      expect(f3.checkouts, 1);
      expect(f3.highestCheckout, 50);
      expect(f3.bullFinishes, 1);
    });

    test('121 zählt weiterhin nicht', () {
      final g = played(
        'one_twenty_one',
        {'start': 170, 'dartsPerAttempt': 3, 'rounds': 1, 'failRule': 'back', 'doubleOut': true},
        ['T20', 'T20', 'BULL'],
        start: day(10),
      );
      final facts = sessionFacts(calcOf([g]), g.$1);
      expect(facts.checkouts, 0);
      expect(facts.highestCheckout, 0);
    });
  });

  group('Doppel-Statistik', () {
    test('Darts aus 6-Dart-Versuchen zählen weiter als Checkout-Darts aufs Doppel', () {
      final g = checkoutOf(40, ['S20', 'D10'], darts: 6, start: day(10));
      final stats = calcOf([g]).doubleStats(StatsPeriod.all);
      expect(stats.checkout.attempts, greaterThan(0));
      expect(stats.checkout.hits, 1);
    });
  });
}
