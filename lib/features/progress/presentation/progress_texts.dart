import 'package:flutter/material.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/l10n.dart';
import '../domain/achievements.dart';
import '../domain/daily_goal.dart';

/// Texte und Symbole für Tagesziel und Erfolge.
extension ProgressTexts on AppLocalizations {
  String goalUnit(DailyGoalUnit u) => switch (u) {
        DailyGoalUnit.darts => dgUnitDarts,
        DailyGoalUnit.minutes => dgUnitMinutes,
        DailyGoalUnit.sessions => dgUnitSessions,
      };

  String achievementGroup(AchievementGroup g) => switch (g) {
        AchievementGroup.scoring => achGroupScoring,
        AchievementGroup.finish => achGroupFinish,
        AchievementGroup.doubles => achGroupDoubles,
        AchievementGroup.endurance => achGroupEndurance,
        AchievementGroup.games => achGroupGames,
      };

  /// Name einer Stufe; Erfolge ohne Stufen haben keinen.
  String? tierName(AchievementDef d, int tier) {
    if (!d.tiered || tier <= 0) return null;
    return switch (tier) {
      1 => achTierBronze,
      2 => achTierSilver,
      _ => achTierGold,
    };
  }

  String achievementTitle(String id) => switch (id) {
        'first_100' => achFirst100,
        'first_140' => achFirst140,
        'first_180' => achFirst180,
        'many_180' => achMany180,
        'tons' => achTons,
        'average' => achAverage,
        'finish_100' => achFinish100,
        'finish_170' => achFinish170,
        'finish_bull' => achFinishBull,
        'checkouts' => achCheckouts,
        'fast_leg' => achFastLeg,
        'bobs_200' => achBobs200,
        'bobs_survive' => achBobsSurvive,
        'double_run' => achDoubleRun,
        'double_hits' => achDoubleHits,
        'darts' => achDarts,
        'goal_streak' => achGoalStreak,
        'goal_days' => achGoalDays,
        'hours' => achHours,
        'all_games' => achAllGames,
        'cpu_wins' => achCpuWins,
        'tournament' => achTournament,
        'nine_darter' => achNineDarter,
        'shanghai' => achShanghai,
        'stars' => achStars,
        _ => id,
      };

  String achievementDescription(String id) => switch (id) {
        'first_100' => achFirst100Desc,
        'first_140' => achFirst140Desc,
        'first_180' => achFirst180Desc,
        'many_180' => achMany180Desc,
        'tons' => achTonsDesc,
        'average' => achAverageDesc,
        'finish_100' => achFinish100Desc,
        'finish_170' => achFinish170Desc,
        'finish_bull' => achFinishBullDesc,
        'checkouts' => achCheckoutsDesc,
        'fast_leg' => achFastLegDesc,
        'bobs_200' => achBobs200Desc,
        'bobs_survive' => achBobsSurviveDesc,
        'double_run' => achDoubleRunDesc,
        'double_hits' => achDoubleHitsDesc,
        'darts' => achDartsDesc,
        'goal_streak' => achGoalStreakDesc,
        'goal_days' => achGoalDaysDesc,
        'hours' => achHoursDesc,
        'all_games' => achAllGamesDesc,
        'cpu_wins' => achCpuWinsDesc,
        'tournament' => achTournamentDesc,
        'nine_darter' => achNineDarterDesc,
        'shanghai' => achShanghaiDesc,
        'stars' => achStarsDesc,
        _ => '',
      };
}

/// Symbol eines Erfolgs.
IconData achievementIcon(String id) => switch (id) {
      'first_100' => Icons.looks_one_rounded,
      'first_140' => Icons.trending_up_rounded,
      'first_180' => Icons.whatshot_rounded,
      'many_180' => Icons.local_fire_department_rounded,
      'tons' => Icons.bolt_rounded,
      'average' => Icons.show_chart_rounded,
      'finish_100' => Icons.flag_rounded,
      'finish_170' => Icons.emoji_events_rounded,
      'finish_bull' => Icons.adjust_rounded,
      'checkouts' => Icons.done_all_rounded,
      'fast_leg' => Icons.speed_rounded,
      'bobs_200' => Icons.filter_2_rounded,
      'bobs_survive' => Icons.shield_rounded,
      'double_run' => Icons.link_rounded,
      'double_hits' => Icons.radio_button_checked_rounded,
      'darts' => Icons.fitness_center_rounded,
      'goal_streak' => Icons.local_fire_department_outlined,
      'goal_days' => Icons.event_available_rounded,
      'hours' => Icons.schedule_rounded,
      'all_games' => Icons.apps_rounded,
      'cpu_wins' => Icons.smart_toy_rounded,
      'tournament' => Icons.military_tech_rounded,
      'nine_darter' => Icons.auto_awesome_rounded,
      'shanghai' => Icons.stacked_bar_chart_rounded,
      'stars' => Icons.star_rounded,
      _ => Icons.workspace_premium_rounded,
    };

/// Farbe einer Stufe: Bronze, Silber, Gold; Erfolge ohne Stufen in Gold.
Color tierColor(DartColors colors, AchievementDef d, int tier) {
  if (!d.tiered) return colors.medalGold;
  return switch (tier) {
    1 => colors.medalBronze,
    2 => colors.medalSilver,
    _ => colors.medalGold,
  };
}

/// Zahl mit Tausenderpunkt, z. B. 10.000.
String groupedNumber(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Datum kurz, z. B. 03.10.2026.
String shortDate(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year}';
}
