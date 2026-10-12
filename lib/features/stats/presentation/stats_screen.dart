import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/domain/game_catalog.dart';
import '../../games/presentation/game_texts.dart';
import '../../profiles/presentation/active_player.dart';
import '../../progress/presentation/achievements_tab.dart';
import '../data/stats_repository.dart';
import '../domain/game_metrics.dart';
import '../domain/stats_calculator.dart';
import 'stats_tabs.dart';
import 'stats_widgets.dart';

/// Gewählter Zeitraum und Spielfilter der Statistik.
final statsPeriodProvider = NotifierProvider<_PeriodNotifier, StatsPeriod>(_PeriodNotifier.new);
final statsGameProvider = NotifierProvider<StringChoice, String?>(StringChoice.new);

/// Spiel und Kennzahl im Verlauf des Reiters "Spiele".
final statsTrendGameProvider = NotifierProvider<StringChoice, String?>(StringChoice.new);
final statsTrendMetricProvider = NotifierProvider<StringChoice, String?>(StringChoice.new);

class _PeriodNotifier extends Notifier<StatsPeriod> {
  @override
  StatsPeriod build() => StatsPeriod.month;
  void set(StatsPeriod p) => state = p;
}

/// Auswahl eines optionalen Schlüssels (Spiel-ID, Kennzahl).
class StringChoice extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

/// Alles, was die Reiter für den gewählten Zeitraum brauchen. Einmal
/// berechnet und von allen Reitern geteilt.
class StatsView {
  const StatsView({required this.calc, required this.report, required this.previous, required this.period, this.gameId});
  final StatsCalculator calc;
  final StatsReport report;

  /// Gleich langer Zeitraum davor; `null` bei "Alles" oder ohne Daten.
  final StatsReport? previous;
  final StatsPeriod period;
  final String? gameId;
}

final statsViewProvider = Provider<StatsView?>((ref) {
  final calc = ref.watch(statsCalculatorProvider).value;
  if (calc == null) return null;
  final period = ref.watch(statsPeriodProvider);
  final gameId = ref.watch(statsGameProvider);
  final previous = calc.previousReport(period, gameId: gameId);
  return StatsView(
    calc: calc,
    report: calc.report(period, gameId: gameId),
    // Ohne Training im Zeitraum davor gibt es nichts zu vergleichen.
    previous: previous == null || previous.isEmpty ? null : previous,
    period: period,
    gameId: gameId,
  );
});

/// Formatiert die Hauptkennzahl eines Spiels.
String formatMetric(String gameId, double? v) {
  if (v == null) return '–';
  return formatMetricKey(gameId, PrimaryMetric.forGame(gameId).key, v);
}

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final view = ref.watch(statsViewProvider);
    final player = ref.watch(activePlayerProvider);

    return LayoutBuilder(builder: (context, outer) {
      // Reiter bündig mit dem Seitenrand (Label-Abstand 16 abziehen).
      final inset = AppPageBar.contentInset(context, outer.maxWidth, double.infinity);
      return DefaultTabController(
        length: 6,
        child: Scaffold(
          appBar: AppPageBar(
            title: Text(l10n.statsTitle),
            actions: [
              if (player != null)
                Chip(avatar: const Icon(Icons.person_rounded, size: 18), label: Text(player.name)),
            ],
            bottom: TabBar(
              key: const Key('stats-tabs'),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.symmetric(horizontal: (inset - AppSpacing.l).clamp(0, double.infinity)),
              tabs: [
                Tab(key: const Key('stats-tab-overview'), text: l10n.statsTabOverview),
                Tab(key: const Key('stats-tab-scoring'), text: l10n.statsTabScoring),
                Tab(key: const Key('stats-tab-doubles'), text: l10n.statsTabDoubles),
                Tab(key: const Key('stats-tab-games'), text: l10n.statsTabGames),
                Tab(key: const Key('stats-tab-records'), text: l10n.statsTabRecords),
                Tab(key: const Key('stats-tab-achievements'), text: l10n.statsTabAchievements),
              ],
            ),
          ),
          body: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final pad = inset;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Zeitraum und Spiel gelten nicht für die Erfolge.
                _HideOnTab(
                  index: _achievementsTab,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, AppSpacing.m, pad, AppSpacing.s),
                    child: _Filters(view: view),
                  ),
                ),
                Expanded(
                  child: view == null
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          children: [
                            OverviewTab(view: view, wide: wide, pad: pad),
                            ScoringTab(view: view, wide: wide, pad: pad),
                            DoublesTab(view: view, wide: wide, pad: pad),
                            GamesTab(view: view, wide: wide, pad: pad),
                            RecordsTab(view: view, wide: wide, pad: pad),
                            AchievementsTab(wide: wide, pad: pad),
                          ],
                        ),
                ),
              ],
            );
          }),
        ),
      );
    });
  }
}

/// Index des Reiters „Erfolge“.
const int _achievementsTab = 5;

/// Blendet [child] aus, solange der Reiter [index] gewählt ist.
class _HideOnTab extends StatelessWidget {
  const _HideOnTab({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: controller.index == index ? const SizedBox(width: double.infinity) : child,
      ),
      child: child,
    );
  }
}

/// Menüwert für "Alle Spiele" (ein Menü meldet `null` als Abbruch).
const String _allGames = '*';

class _Filters extends ConsumerWidget {
  const _Filters({required this.view});
  final StatsView? view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final period = ref.watch(statsPeriodProvider);
    final gameId = ref.watch(statsGameProvider);
    String label(StatsPeriod p) => switch (p) {
          StatsPeriod.week => l10n.statsPeriodWeek,
          StatsPeriod.month => l10n.statsPeriodMonth,
          StatsPeriod.quarter => l10n.statsPeriodQuarter,
          StatsPeriod.all => l10n.statsPeriodAll,
        };
    // Katalog plus Spiele, die nur in den Daten vorkommen (z. B. neuere).
    final ids = [
      for (final d in GameCatalog.all) d.id,
      for (final id in view?.calc.playedGames ?? const <String>[])
        if (GameCatalog.byId(id) == null) id,
    ];
    final selected = ids.contains(gameId) ? gameId : null;
    // Eine Zeile, auf schmalen Bildschirmen seitlich scrollbar, damit die
    // Reiter möglichst viel Platz behalten.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in StatsPeriod.values) ...[
            ChoiceChip(
              key: Key('period-${p.name}'),
              label: Text(label(p)),
              selected: p == period,
              onSelected: (_) => ref.read(statsPeriodProvider.notifier).set(p),
            ),
            const SizedBox(width: AppSpacing.s),
          ],
          const SizedBox(width: AppSpacing.s),
          PopupMenuButton<String>(
            key: const Key('stats-game'),
            tooltip: l10n.statsAllGames,
            initialValue: selected ?? _allGames,
            onSelected: (v) => ref.read(statsGameProvider.notifier).set(v == _allGames ? null : v),
            itemBuilder: (_) => [
              PopupMenuItem(value: _allGames, child: Text(l10n.statsAllGames)),
              for (final id in ids)
                PopupMenuItem(
                  value: id,
                  child: Row(
                    children: [
                      Icon(gameIcon(id), size: 18),
                      const SizedBox(width: AppSpacing.s),
                      Flexible(child: Text(l10n.gameTitle(id), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
            ],
            child: IgnorePointer(
              child: FilterChip(
                selected: selected != null,
                showCheckmark: false,
                avatar: Icon(selected == null ? Icons.filter_list_rounded : gameIcon(selected), size: 18),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(selected == null ? l10n.statsAllGames : l10n.gameTitle(selected)),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(Icons.arrow_drop_down_rounded, size: 20),
                  ],
                ),
                onSelected: (_) {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}
