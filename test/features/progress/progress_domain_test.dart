import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/progress/domain/achievement_tracker.dart';
import 'package:dartlab/features/progress/domain/achievements.dart';
import 'package:dartlab/features/progress/domain/daily_goal.dart';
import 'package:dartlab/features/progress/domain/session_facts.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

var _id = 0;

/// Spielt [gameId] mit den Darts [names] (Aufnahmen zu je drei Darts, `|`
/// beendet eine Aufnahme vorzeitig) und liefert Session und Würfe.
(SessionRow, List<ThrowRow>) played(String gameId, Map<String, Object?> config, List<String> names,
    {required DateTime start, Duration length = const Duration(minutes: 10)}) {
  final def = GameCatalog.byId(gameId)!;
  final game = def.start(config, 1)..prepare();
  final sid = ++_id;
  final throws = <ThrowRow>[];
  var seq = 0;
  for (final n in names) {
    if (n == '|') {
      game.endVisit();
      continue;
    }
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
    endedAt: start.add(length),
    finished: game.finished,
    resultJson: jsonEncode(game.result.toJson()),
    dartCount: throws.length,
  );
  return (session, throws);
}

StatsCalculator calcOf(List<(SessionRow, List<ThrowRow>)> games, DateTime now) =>
    StatsCalculator(sessions: [for (final g in games) g.$1], throws: [for (final g in games) ...g.$2], now: now);

DateTime day(int d, [int h = 18]) => DateTime(2026, 10, d, h);

void main() {
  group('Serie', () {
    // 12.10.2026 ist ein Montag.
    test('aufeinanderfolgende Tage, heute offen bricht nichts ab', () {
      final s = goalStreak([day(9), day(10), day(11)], day(12));
      expect(s.current, 3);
      expect(s.best, 3);
      expect(s.freeDayUsedThisWeek, isFalse);
    });

    test('ein freier Tag pro Woche hält die Serie, wächst aber nicht', () {
      // Mo 5., Di 6., Mi 7. verpasst, Do 8., Fr 9.
      final s = goalStreak([day(5), day(6), day(8), day(9)], day(9, 22));
      expect(s.current, 4);
      expect(s.freeDayUsedThisWeek, isTrue);
    });

    test('der zweite verpasste Tag derselben Woche beendet die Serie', () {
      final s = goalStreak([day(5), day(7), day(9)], day(9, 22));
      expect(s.current, 1);
      expect(s.best, 2);
    });

    test('neue Woche, neuer freier Tag', () {
      // So 4. verpasst (Woche ab 28.9.), Di 6. verpasst (Woche ab 5.10.).
      final s = goalStreak([day(2), day(3), day(5), day(7)], day(7, 22));
      expect(s.current, 4);
      expect(s.timeline.map((p) => p.run), [1, 2, 3, 4]);
    });

    test('Tagesziel aus Darts, Minuten oder Sessions', () {
      final a = played('bull_drill', const {'visits': 1}, ['BULL', 'SB', 'MISS'], start: day(11, 10));
      final b = played('bull_drill', const {'visits': 1}, ['BULL', 'BULL', 'BULL'], start: day(11, 20), length: const Duration(minutes: 25));
      final activity = dailyActivity(calcOf([a, b], day(12)));
      final d11 = activity[DateTime(2026, 10, 11)]!;
      expect(d11.darts, 6);
      expect(d11.sessions, 2);
      expect(d11.minutes, 35);
      final status = dailyGoalStatus(activity, const DailyGoal(DailyGoalUnit.sessions, 2), day(12, 9));
      expect(status.today, 0);
      expect(status.streak.current, 1);
      final live = dailyGoalStatus(activity, const DailyGoal(DailyGoalUnit.darts, 3), day(11, 21),
          extraToday: const DayActivity(darts: 3));
      expect(live.today, 9);
      expect(live.reached, isTrue);
    });

    test('Menge rastet auf das Raster der Einheit ein', () {
      expect(DailyGoalUnit.darts.clamp(5), 30);
      expect(DailyGoalUnit.darts.clamp(204), 200);
      expect(DailyGoalUnit.minutes.clamp(1000), 240);
      expect(DailyGoalUnit.byName('minutes'), DailyGoalUnit.minutes);
      expect(DailyGoalUnit.byName('quatsch'), DailyGoalUnit.darts);
    });
  });

  group('Erfolge', () {
    test('Scoring: 180, Tonnen und Average aus der Highscore-Jagd', () {
      final g = played('highscore_hunt', const {'visits': 7},
          ['T20', 'T20', 'T20', 'T20', 'T20', 'S20', 'T20', 'S20', 'S20', ...List.filled(12, 'S20')],
          start: day(10));
      final calc = calcOf([g], day(12));
      final f = sessionFacts(calc, g.$1);
      expect(f.max180, 1);
      expect(f.visits140, 2);
      expect(f.tons, 3);
      expect(f.average, closeTo((180 + 140 + 100 + 4 * 60) / 21 * 3, 0.01));

      final t = AchievementTracker.fromCalculator(calc);
      expect(t.tierOf(AchievementCatalog.byId('first_180')!), 1);
      expect(t.tierOf(AchievementCatalog.byId('first_100')!), 1);
      expect(t.tierOf(AchievementCatalog.byId('average')!), 3); // 94,3 ab 90
      expect(t.reachedAt('first_180', 1), g.$1.endedAt);
    });

    test('Finish: Checkout-Wert und Bull-Finish im Checkout-Training', () {
      final g = played('checkout', const {'mode': 'descending', 'min': 170, 'max': 170, 'attempts': 1, 'dartsPerAttempt': 3},
          ['T20', 'T20', 'BULL'],
          start: day(10));
      final calc = calcOf([g], day(12));
      final facts = sessionFacts(calc, g.$1);
      expect(facts.checkouts, 1);
      expect(facts.highestCheckout, 170);
      expect(facts.bullFinishes, 1);
      final t = AchievementTracker.fromCalculator(calc);
      expect(t.tierOf(AchievementCatalog.byId('finish_170')!), 1);
      expect(t.tierOf(AchievementCatalog.byId('finish_bull')!), 1);
    });

    test('Schnellstes 501-Leg und Neun-Darter', () {
      final g = played('x01', const {'startScore': 501, 'outMode': 'double', 'inMode': 'straight', 'legs': 1},
          ['T20', 'T20', 'T20', 'T20', 'T20', 'T20', 'T20', 'T19', 'D12'],
          start: day(10));
      final calc = calcOf([g], day(12));
      final f = sessionFacts(calc, g.$1);
      expect(f.fastest501, 9);
      final t = AchievementTracker.fromCalculator(calc);
      expect(t.tierOf(AchievementCatalog.byId('fast_leg')!), 3);
      expect(t.tierOf(AchievementCatalog.byId('nine_darter')!), 1);
      expect(t.tierOf(AchievementCatalog.byId('finish_100')!), 1); // 141 Finish
    });

    test('Bob\'s 27 zählt nur überstanden; Doppel-Serie aus den Zielen', () {
      final hits = [for (var n = 1; n <= 20; n++) ...['D$n', 'MISS', 'MISS'], 'BULL', 'MISS', 'MISS'];
      final g = played('bobs_27', const {'startScore': 27, 'includeBull': true}, hits, start: day(10));
      final f = sessionFacts(calcOf([g], day(12)), g.$1);
      expect(f.bobsSurvived, isTrue);
      expect(f.bobsScore, greaterThan(200));
      expect(f.doubleHits, 21);
      expect(f.doubleRun, 1);

      final lost = played('bobs_27', const {'startScore': 27, 'includeBull': true}, List.filled(9, 'MISS'), start: day(11));
      final f2 = sessionFacts(calcOf([lost], day(12)), lost.$1);
      expect(f2.bobsSurvived, isFalse);
      expect(f2.bobsScore, isNull);
    });

    test('Ausdauer und Sterne: Datum der Stufe aus Serie und Challenge-Ergebnis', () {
      final t = AchievementTracker()
        ..applyGoals(goalStreak([for (var d = 1; d <= 8; d++) day(d)], day(9)))
        ..applyStars([(stars: 20, at: day(3)), (stars: 15, at: day(5))]);
      expect(t.tierOf(AchievementCatalog.byId('goal_streak')!), 1);
      expect(t.reachedAt('goal_streak', 1), DateTime(2026, 10, 7, 23, 59));
      expect(t.tierOf(AchievementCatalog.byId('stars')!), 1);
      expect(t.reachedAt('stars', 1), day(5));
      final tiers = reachedTiers(t);
      expect(tiers.keys, containsAll(['goal_streak#1', 'stars#1']));
    });

    test('gespeicherte Stufen bleiben, auch wenn die Daten sie nicht mehr hergeben', () {
      final statuses = achievementStatuses(AchievementTracker(), {'many_180#2': day(1)});
      final many = statuses.firstWhere((s) => s.def.id == 'many_180');
      expect(many.tier, 2);
      expect(many.unlockedAt, day(1));
      expect(many.next, 100);
      final locked = statuses.firstWhere((s) => s.def.id == 'tons');
      expect(locked.unlocked, isFalse);
      expect(locked.ratio, 0);
    });

    test('Katalog: eindeutige IDs, Stufen werden schwerer', () {
      expect({for (final d in AchievementCatalog.all) d.id}, hasLength(AchievementCatalog.all.length));
      expect(AchievementCatalog.all.length, greaterThanOrEqualTo(24));
      for (final d in AchievementCatalog.all) {
        for (var i = 1; i < d.thresholds.length; i++) {
          expect(d.lowerIsBetter ? d.thresholds[i] < d.thresholds[i - 1] : d.thresholds[i] > d.thresholds[i - 1], isTrue,
              reason: d.id);
        }
      }
    });
  });
}
