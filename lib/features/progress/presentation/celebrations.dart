import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../games/presentation/active_game_controller.dart';
import '../../matches/domain/match_result.dart';
import '../../matches/presentation/match_controller.dart';
import '../../profiles/presentation/active_player.dart';
import '../../stats/domain/stats_calculator.dart';
import '../domain/achievement_tracker.dart';
import '../domain/achievements.dart';
import '../domain/daily_goal.dart';
import '../domain/session_facts.dart';
import 'progress_providers.dart';

/// Was eingeblendet wird.
sealed class Celebration {
  const Celebration();
}

/// Tagesziel erreicht.
class GoalCelebration extends Celebration {
  const GoalCelebration(this.goal);
  final DailyGoal goal;
}

/// Erfolgs-Stufe freigeschaltet.
class AchievementCelebration extends Celebration {
  const AchievementCelebration(this.def, this.tier);
  final AchievementDef def;
  final int tier;
}

/// Einblendungen, die zusammen erscheinen.
@immutable
class CelebrationBatch {
  const CelebrationBatch(this.serial, this.items);
  final int serial;
  final List<Celebration> items;
}

final celebrationsProvider = NotifierProvider<CelebrationController, CelebrationBatch?>(CelebrationController.new);

/// Beobachtet das laufende Trainingsspiel bzw. Match und meldet, sobald das
/// Tagesziel erreicht oder ein Erfolg freigeschaltet wird.
///
/// Der Stand aller abgeschlossenen Sessions kommt aus den Providern; das
/// laufende Spiel wird als vorläufige Session dazugerechnet. Jede
/// Einblendung kommt nur einmal (je Tag bzw. je Stufe).
class CelebrationController extends Notifier<CelebrationBatch?> {
  final Set<String> _done = {};
  final Map<Object, DateTime> _starts = {};
  int _serial = 0;

  @override
  CelebrationBatch? build() {
    // Der Stand vor dem Spiel muss bereitliegen, wenn der erste Dart kommt.
    ref
      ..listen(sessionTrackerProvider, (_, _) {})
      ..listen(dailyActivityProvider, (_, _) {})
      ..listen(achievementUnlocksProvider, (_, _) {})
      ..listen(challengeResultsProvider, (_, _) {});
    ref.listen(activeGameProvider, (_, next) {
      if (next != null) _checkGame(next);
    });
    ref.listen(matchControllerProvider, (_, next) {
      if (next != null) _checkMatch(next);
    });
    ref.listen(achievementRecorderProvider, (_, next) {
      if (next == null || next.silent) return;
      final inGame = ref.read(activeGameProvider) != null || ref.read(matchControllerProvider) != null;
      if (!inGame) {
        _done.addAll(next.keys);
        return;
      }
      _emit(_achievementItems(next.keys));
    });
    return null;
  }

  void _emit(List<Celebration> items) {
    if (items.isEmpty) return;
    state = CelebrationBatch(++_serial, items);
  }

  /// Neue Stufen als Einblendungen, je Erfolg nur die höchste.
  List<Celebration> _achievementItems(Iterable<String> keys) {
    final fresh = keys.where(_done.add).toList();
    final best = <String, int>{};
    for (final k in fresh) {
      final i = k.lastIndexOf('#');
      final id = k.substring(0, i);
      final tier = int.parse(k.substring(i + 1));
      if (tier > (best[id] ?? 0)) best[id] = tier;
    }
    return [
      for (final e in best.entries)
        if (AchievementCatalog.byId(e.key) case final def?) AchievementCelebration(def, e.value),
    ];
  }

  void _checkGame(ActiveGame active) {
    final records = active.session.records;
    if (records.isEmpty) return;
    final now = DateTime.now();
    final start = _starts.putIfAbsent(active.sessionId, () => records.first.dart.timestamp);
    final game = active.game;
    final session = SessionRow(
      id: -1,
      uid: '',
      playerId: active.playerId,
      gameId: active.gameId,
      configJson: jsonEncode(active.session.config),
      seed: active.session.seed,
      startedAt: start,
      endedAt: now,
      finished: game.finished,
      resultJson: jsonEncode(game.result.toJson()),
      dartCount: records.length,
    );
    final throws = [
      for (final (i, r) in records.indexed)
        _throw(i, active.playerId, active.gameId, r.visitIndex, r.counted, r.dart.segment.name, r.dart.segment.number,
            r.dart.segment.multiplier, r.dart.segment.bed.name, r.dart.segment.score, r.dart.timestamp),
    ];
    _check(session, throws, ended: active.ended);
  }

  void _checkMatch(MatchState state) {
    final setup = state.setup;
    final playerId = ref.read(activePlayerProvider)?.id;
    var human = -1;
    for (var i = 0; i < setup.players.length; i++) {
      final p = setup.players[i];
      if (p.isBot || p.profileId == null) continue;
      if (human < 0 || p.profileId == playerId) human = i;
    }
    if (human < 0) return;
    final profile = setup.players[human].profileId!;
    if (playerId != null && profile != playerId) return;
    final own = [for (final r in state.session.records) if (r.player == human) r];
    if (own.isEmpty) return;
    final now = DateTime.now();
    final start = _starts.putIfAbsent(state.session, () => own.first.dart.timestamp);
    final session = SessionRow(
      id: -1,
      uid: '',
      playerId: profile,
      gameId: matchGameId,
      configJson: jsonEncode({
        ...setup.format.toJson(),
        'vsBot': setup.hasBot,
        if (setup.tournamentMatch != null) 'tournament': true,
      }),
      seed: 0,
      startedAt: start,
      endedAt: now,
      finished: state.finished,
      resultJson: jsonEncode(matchResultFor(state.match, human, setup).toJson()),
      dartCount: own.length,
    );
    final throws = [
      for (final (i, r) in own.indexed)
        _throw(i, profile, matchGameId, r.visitSerial, r.counted, r.dart.segment.name, r.dart.segment.number,
            r.dart.segment.multiplier, r.dart.segment.bed.name, r.dart.segment.score, r.dart.timestamp),
    ];
    _check(session, throws, ended: state.ended);
  }

  static ThrowRow _throw(int seq, int playerId, String gameId, int visit, bool counted, String segment, int number,
          int multiplier, String bed, int score, DateTime time) =>
      ThrowRow(
        id: seq,
        sessionId: -1,
        playerId: playerId,
        gameId: gameId,
        seq: seq,
        visitIndex: visit,
        counted: counted,
        segment: segment,
        number: number,
        multiplier: multiplier,
        bed: bed,
        score: score,
        source: 'live',
        timestamp: time,
      );

  AchievementTracker? _baseFor;
  DailyGoal? _baseGoal;
  AchievementTracker? _baseFull;

  /// Serie des Tagesziels samt laufendem Spiel. Sie hängt nur von den Tagen
  /// ab (dieselben Tageswerte, dasselbe Ziel, derselbe Tag) und davon, ob das
  /// Ziel heute erreicht ist; pro Dart ändert sich das selten, deshalb wird
  /// nicht nach jedem Dart die ganze Geschichte Tag für Tag durchgegangen.
  (Map<DateTime, DayActivity>, DailyGoal, DateTime, bool)? _streakKey;
  GoalStreak? _streak;

  void _check(SessionRow session, List<ThrowRow> throws, {required bool ended}) {
    final base = ref.read(sessionTrackerProvider);
    final activity = ref.read(dailyActivityProvider);
    final stored = ref.read(achievementUnlocksProvider).value;
    final results = ref.read(challengeResultsProvider).value ?? const [];
    if (base == null || activity == null || stored == null) return;
    final goal = ref.read(dailyGoalProvider);
    final now = DateTime.now();
    final items = <Celebration>[];

    // Tagesziel: abgeschlossene Sessions plus das laufende Spiel.
    final calc = StatsCalculator(sessions: [session], throws: throws, now: now);
    final extra = dailyActivity(calc)[StatsCalculator.dayOf(now)] ?? DayActivity.zero;
    final today = activity[StatsCalculator.dayOf(now)] ?? DayActivity.zero;
    // Eine laufende Session zählt als Session erst, wenn sie beendet ist.
    final liveToday = DayActivity(darts: extra.darts, minutes: extra.minutes, sessions: ended ? 1 : 0);
    final before = today.valueOf(goal.unit);
    final after = (today + liveToday).valueOf(goal.unit);
    final dayKey = 'goal:${StatsCalculator.dayOf(now).toIso8601String()}';
    if (before < goal.amount && after >= goal.amount && _done.add(dayKey)) items.add(GoalCelebration(goal));

    // Erfolge.
    final stars = [for (final r in results) (stars: r.stars, at: r.achievedAt)];
    if (!identical(base, _baseFor) || goal != _baseGoal) {
      _baseFor = base;
      _baseGoal = goal;
      _baseFull = base.copy()
        ..applyGoals(dailyGoalStatus(activity, goal, now).streak)
        ..applyStars(stars);
    }
    final tracker = base.copy()
      ..add(sessionFacts(calc, session))
      ..applyGoals(_liveStreak(activity, goal, now, liveToday, reached: after >= goal.amount))
      ..applyStars(stars);
    final known = _baseFull!.reached;
    final fresh = tracker.reached.where((k) => !known.contains(k) && !stored.containsKey(k));
    items.addAll(_achievementItems(fresh));
    _emit(items);
  }

  GoalStreak _liveStreak(Map<DateTime, DayActivity> activity, DailyGoal goal, DateTime now, DayActivity liveToday,
      {required bool reached}) {
    final key = (activity, goal, StatsCalculator.dayOf(now), reached);
    if (key == _streakKey) return _streak!;
    _streakKey = key;
    return _streak = dailyGoalStatus(activity, goal, now, extraToday: liveToday).streak;
  }
}
