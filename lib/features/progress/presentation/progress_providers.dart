import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings.dart';
import '../../challenges/data/challenge_repository.dart';
import '../../challenges/domain/challenge.dart';
import '../../profiles/presentation/active_player.dart';
import '../../stats/data/stats_repository.dart';
import '../../stats/domain/stats_calculator.dart';
import '../data/achievement_repository.dart';
import '../domain/achievement_tracker.dart';
import '../domain/achievements.dart';
import '../domain/daily_goal.dart';

/// Das eingestellte Tagesziel.
final dailyGoalProvider = Provider<DailyGoal>((ref) => ref.watch(settingsProvider.select((s) => s.dailyGoal)));

/// Training je Tag aus den abgeschlossenen Sessions des aktiven Profils.
final dailyActivityProvider = Provider<Map<DateTime, DayActivity>?>((ref) {
  final calc = ref.watch(statsCalculatorProvider).value;
  return calc == null ? null : dailyActivity(calc);
});

/// Heutiger Stand des Tagesziels und die Serie.
final dailyGoalStatusProvider = Provider<DailyGoalStatus?>((ref) {
  final activity = ref.watch(dailyActivityProvider);
  if (activity == null) return null;
  return dailyGoalStatus(activity, ref.watch(dailyGoalProvider), DateTime.now());
});

/// Erfolgs-Stand aus allen abgeschlossenen Sessions (ohne Tagesziel und
/// Challenges, die kommen in [achievementTrackerProvider] dazu).
final sessionTrackerProvider = Provider<AchievementTracker?>((ref) {
  final calc = ref.watch(statsCalculatorProvider).value;
  return calc == null ? null : AchievementTracker.fromCalculator(calc);
});

/// Beste Challenge-Ergebnisse des aktiven Profils.
final challengeResultsProvider = StreamProvider<List<ChallengeBest>>((ref) {
  final playerId = ref.watch(activePlayerProvider)?.id;
  if (playerId == null) return const Stream.empty();
  return ref.watch(challengeRepositoryProvider).watchResults(playerId);
});

/// Gespeicherte Freischaltungen des aktiven Profils (Schlüssel → Datum).
final achievementUnlocksProvider = StreamProvider<Map<String, DateTime>>((ref) {
  final playerId = ref.watch(activePlayerProvider)?.id;
  if (playerId == null) return const Stream.empty();
  return ref
      .watch(achievementRepositoryProvider)
      .watchUnlocks(playerId)
      .map((rows) => {for (final AchievementRow r in rows) tierKey(r.achievementId, r.tier): r.unlockedAt});
});

/// Vollständiger Erfolgs-Stand: Sessions, Tagesziel-Serie und Sterne.
final achievementTrackerProvider = Provider<AchievementTracker?>((ref) {
  final base = ref.watch(sessionTrackerProvider);
  final goal = ref.watch(dailyGoalStatusProvider);
  final results = ref.watch(challengeResultsProvider).value;
  if (base == null || goal == null || results == null) return null;
  return base.copy()
    ..applyGoals(goal.streak)
    ..applyStars([for (final r in results) (stars: r.stars, at: r.achievedAt)]);
});

/// Stand aller Erfolge für die Anzeige.
final achievementsProvider = Provider<List<AchievementStatus>?>((ref) {
  final tracker = ref.watch(achievementTrackerProvider);
  final stored = ref.watch(achievementUnlocksProvider).value;
  if (tracker == null || stored == null) return null;
  return achievementStatuses(tracker, stored);
});

/// Neu gespeicherte Erfolgs-Stufen.
class UnlockBatch {
  const UnlockBatch({required this.playerId, required this.keys, required this.silent, required this.serial});
  final int playerId;
  final Set<String> keys;

  /// Rückwirkend berechnet (erster Lauf nach dem Start), ohne Einblendung.
  final bool silent;
  final int serial;
}

/// Schreibt neu erreichte Erfolgs-Stufen mit ihrem Datum in die Datenbank.
///
/// Rechnet direkt aus den Daten des Profils, dem der Rechner gehört, damit
/// beim Wechsel des Profils nichts beim falschen landet.
class AchievementRecorder extends Notifier<UnlockBatch?> {
  Future<void> _pending = Future.value();

  /// Profile, für die schon einmal gespeichert wurde. Beim ersten Mal (z. B.
  /// nach dem Start der App) kommen rückwirkend berechnete Erfolge ohne
  /// Einblendung dazu.
  final Set<int> _initialized = {};
  int _serial = 0;

  @override
  UnlockBatch? build() {
    void again() {
      final calc = ref.read(statsCalculatorProvider).value;
      if (calc != null) _schedule(calc);
    }

    ref.listen(statsCalculatorProvider, (_, next) {
      final calc = next.value;
      if (calc != null) _schedule(calc);
    }, fireImmediately: true);
    ref.listen(challengeResultsProvider, (_, _) => again());
    ref.listen(dailyGoalProvider, (_, _) => again());
    return null;
  }

  /// Wartet auf laufende Speichervorgänge (für Tests).
  Future<void> get pending => _pending;

  void _schedule(StatsCalculator calc) {
    _pending = _pending.then((_) => _record(calc)).catchError((Object _) {});
  }

  Future<void> _record(StatsCalculator calc) async {
    final playerId = ref.read(activePlayerProvider)?.id;
    if (playerId == null) return;
    if (calc.sessions.any((s) => s.playerId != playerId)) return;
    final results = await ref.read(challengeRepositoryProvider).results(playerId);
    // Gehört der Rechner noch zum aktuellen Stand, sind Tage und Erfolge schon
    // berechnet (die Provider halten sie für Einblendungen ohnehin bereit).
    final current = identical(ref.read(statsCalculatorProvider).value, calc);
    final activity = (current ? ref.read(dailyActivityProvider) : null) ?? dailyActivity(calc);
    final status = dailyGoalStatus(activity, ref.read(dailyGoalProvider), DateTime.now());
    final cached = current ? ref.read(sessionTrackerProvider) : null;
    final tracker = (cached ?? AchievementTracker.fromCalculator(calc)).copy()
      ..applyGoals(status.streak)
      ..applyStars([for (final r in results) (stars: r.stars, at: r.achievedAt)]);
    final repo = ref.read(achievementRepositoryProvider);
    final stored = {for (final r in await repo.unlocks(playerId)) tierKey(r.achievementId, r.tier)};
    final missing = {
      for (final e in reachedTiers(tracker).entries)
        if (!stored.contains(e.key)) e.key: e.value,
    };
    final first = _initialized.add(playerId);
    if (missing.isEmpty) return;
    await repo.addUnlocks(playerId, missing);
    state = UnlockBatch(playerId: playerId, keys: missing.keys.toSet(), silent: first, serial: ++_serial);
  }
}

final achievementRecorderProvider = NotifierProvider<AchievementRecorder, UnlockBatch?>(AchievementRecorder.new);
