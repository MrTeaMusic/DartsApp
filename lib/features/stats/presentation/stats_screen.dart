import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/lite.dart';
import '../../../core/router/app_router.dart';
import '../../games/domain/game_catalog.dart';
import '../../games/presentation/game_texts.dart';
import '../../profiles/presentation/active_player.dart';
import '../../progress/presentation/achievements_tab.dart';
import '../../update/presentation/update_banner.dart';
import '../data/stats_repository.dart';
import '../domain/game_metrics.dart';
import '../domain/stats_calculator.dart';
import 'elo_tab.dart';
import 'online_tab.dart';
import 'period_picker.dart';
import 'scatter_tab.dart';
import 'tempo_tab.dart';
import 'stats_tabs.dart';
import 'stats_widgets.dart';

/// Gewählter Zeitraum und Spielfilter der Statistik.
final statsPeriodProvider = NotifierProvider<_PeriodNotifier, StatsPeriod>(_PeriodNotifier.new);
final statsGameProvider = NotifierProvider<StringChoice, String?>(StringChoice.new);

/// Vergleich mit einem zweiten Zeitraum B (`null` = kein Vergleich, dann
/// zeigen die Pfeile den gleich langen Zeitraum davor).
final statsCompareProvider = NotifierProvider<_CompareNotifier, StatsCompare?>(_CompareNotifier.new);

class _CompareNotifier extends Notifier<StatsCompare?> {
  @override
  StatsCompare? build() => null;
  void set(StatsCompare? c) => state = c;
}

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
  const StatsView({
    required this.calc,
    required this.report,
    required this.previous,
    required this.doubles,
    required this.period,
    this.gameId,
    this.comparePeriod,
    this.compareReport,
    this.compareDoubles,
  });
  final StatsCalculator calc;
  final StatsReport report;

  /// Doppel-Auswertung (Streubild, Daneben-Richtung, Verlauf …).
  final DoubleStats doubles;

  /// Vergleichswerte für die Pfeile: Zeitraum B, wenn verglichen wird, sonst
  /// der gleich lange Zeitraum davor; `null` bei "Alles" oder ohne Daten.
  final StatsReport? previous;
  final StatsPeriod period;
  final String? gameId;

  /// Zeitraum B und seine Auswertungen, solange verglichen wird.
  final StatsPeriod? comparePeriod;
  final StatsReport? compareReport;
  final DoubleStats? compareDoubles;

  bool get comparing => comparePeriod != null;
}

final statsViewProvider = Provider<StatsView?>((ref) {
  final calc = ref.watch(statsCalculatorProvider).value;
  if (calc == null) return null;
  final period = ref.watch(statsPeriodProvider);
  final gameId = ref.watch(statsGameProvider);
  final b = ref.watch(statsCompareProvider)?.resolve(period, calc.now);
  final compareReport = b == null ? null : calc.report(b, gameId: gameId);
  final previous = compareReport ?? calc.previousReport(period, gameId: gameId);
  return StatsView(
    calc: calc,
    report: calc.report(period, gameId: gameId),
    // Ohne Training im Vergleichszeitraum gibt es nichts zu vergleichen.
    previous: previous == null || previous.isEmpty ? null : previous,
    doubles: calc.doubleStats(period, gameId: gameId),
    period: period,
    gameId: gameId,
    comparePeriod: b,
    compareReport: compareReport,
    compareDoubles: b == null ? null : calc.doubleStats(b, gameId: gameId),
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
        length: 10,
        child: Scaffold(
          appBar: AppPageBar(
            title: Text(l10n.statsTitle),
            actions: [
              TextButton.icon(
                key: const Key('stats-history'),
                onPressed: () => context.go(Routes.history),
                icon: const Icon(Icons.history_rounded),
                label: Text(l10n.histTitle),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (player != null)
                Chip(avatar: const Icon(Icons.person_rounded, size: 18), label: Text(player.name)),
            ],
            bottom: TabBar(
              key: const Key('stats-tabs'),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              // Arena: der Reiter ist eine Pille, die nicht am Rand abgeschnitten sein soll.
              padding: EdgeInsets.symmetric(horizontal: (inset - AppSpacing.l).clamp(context.look.isArena ? 12 : 0, double.infinity)),
              tabs: [
                Tab(key: const Key('stats-tab-overview'), text: l10n.statsTabOverview),
                Tab(key: const Key('stats-tab-online'), text: l10n.statsTabOnline),
                Tab(key: const Key('stats-tab-elo'), text: l10n.statsTabElo),
                Tab(key: const Key('stats-tab-scoring'), text: l10n.statsTabScoring),
                Tab(key: const Key('stats-tab-doubles'), text: l10n.statsTabDoubles),
                Tab(key: const Key('stats-tab-scatter'), text: l10n.statsTabScatter),
                Tab(key: const Key('stats-tab-tempo'), text: l10n.statsTabTempo),
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
                // Lite hat keine Startseite: Der Update-Hinweis steht hier.
                if (ref.watch(liteProvider))
                  Padding(
                    padding: EdgeInsets.fromLTRB(pad, AppSpacing.s, pad, 0),
                    child: const UpdateBanner(bottomGap: AppSpacing.s),
                  ),
                // Zeitraum und Spiel gelten nicht für die Erfolge.
                _HideOnTab(
                  indexes: const {_achievementsTab},
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, AppSpacing.m, pad, AppSpacing.s),
                    child: _Filters(view: view),
                  ),
                ),
                if (view?.comparePeriod case final b?)
                  _HideOnTab(
                    indexes: const {_onlineTab, _eloTab, _scatterTab, _tempoTab, _gamesTab, _recordsTab, _achievementsTab},
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, AppSpacing.s),
                      child: CompareBar(
                        a: view!.period,
                        b: b,
                        today: view.calc.now,
                        onEdit: () async {
                          final r = await showCompareSheet(context,
                              a: view.period, current: ref.read(statsCompareProvider), today: view.calc.now);
                          if (r != null) ref.read(statsCompareProvider.notifier).set(r.compare);
                        },
                        onClose: () => ref.read(statsCompareProvider.notifier).set(null),
                      ),
                    ),
                  ),
                Expanded(
                  child: view == null
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          children: [
                            OverviewTab(view: view, wide: wide, pad: pad),
                            OnlineTab(view: view, wide: wide, pad: pad),
                            EloTab(view: view, wide: wide, pad: pad),
                            ScoringTab(view: view, wide: wide, pad: pad),
                            DoublesTab(view: view, wide: wide, pad: pad),
                            ScatterTab(view: view, wide: wide, pad: pad),
                            TempoTab(view: view, wide: wide, pad: pad),
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

/// Index des Reiters „Online“ (gilt für alle Live-Sessions, ohne Spielfilter).
const int _onlineTab = 1;

/// Index des Reiters „Elo“ (gilt für alle Matches, ohne Spielfilter).
const int _eloTab = 2;

/// Reiter ohne Vergleich A gegen B.
const int _scatterTab = 5;
const int _tempoTab = 6;
const int _gamesTab = 7;
const int _recordsTab = 8;

/// Index des Reiters „Erfolge“.
const int _achievementsTab = 9;

/// Blendet [child] aus, solange der Reiter [index] gewählt ist.
class _HideOnTab extends StatelessWidget {
  const _HideOnTab({required this.indexes, required this.child, this.inline = false});
  final Set<int> indexes;
  final Widget child;

  /// In einer Zeile (ohne volle Breite, wenn ausgeblendet).
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: indexes.contains(controller.index) ? (inline ? const SizedBox.shrink() : const SizedBox(width: double.infinity)) : child,
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
    final today = view?.calc.now ?? DateTime.now();
    String label(StatsPeriod p) {
      if (p == StatsPeriod.week) return l10n.statsPeriodWeek;
      if (p == StatsPeriod.month) return l10n.statsPeriodMonth;
      if (p == StatsPeriod.quarter) return l10n.statsPeriodQuarter;
      return l10n.statsPeriodAll;
    }

    final compare = ref.watch(statsCompareProvider);
    Future<void> pickCustom() async {
      final p = await showPeriodSheet(context, initial: period, today: today);
      if (p != null) ref.read(statsPeriodProvider.notifier).set(p);
    }

    Future<void> editCompare() async {
      final r = await showCompareSheet(context, a: period, current: compare, today: today);
      if (r != null) ref.read(statsCompareProvider.notifier).set(r.compare);
    }

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
          ChoiceChip(
            key: const Key('period-custom'),
            avatar: Icon(Icons.date_range_rounded, size: 18, color: period.isCustom ? null : Theme.of(context).colorScheme.onSurfaceVariant),
            label: Text(period.isCustom ? formatPeriodRange(period, today) : l10n.statsPeriodCustom),
            selected: period.isCustom,
            onSelected: (_) => pickCustom(),
          ),
          const SizedBox(width: AppSpacing.s),
          // Elo, Online usw. haben keine Pfeile: Vergleich nur, wo er wirkt.
          _HideOnTab(
            indexes: const {_onlineTab, _eloTab, _scatterTab, _tempoTab, _gamesTab, _recordsTab},
            inline: true,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s),
              child: FilterChip(
                key: const Key('stats-compare'),
                showCheckmark: false,
                avatar: const Icon(Icons.compare_arrows_rounded, size: 18),
                label: Text(switch (view?.comparePeriod) {
                  final b? => l10n.statsCompareChip(b.days == null ? l10n.statsPeriodAll : formatPeriodRange(b, today)),
                  null => l10n.statsCompare,
                }),
                selected: view?.comparing ?? false,
                onSelected: (_) => editCompare(),
              ),
            ),
          ),
          // „Online“ zeigt immer alle Live-Sessions, „Elo“ alle Matches.
          _HideOnTab(
            indexes: const {_onlineTab, _eloTab},
            inline: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
          ),
        ],
      ),
    );
  }
}
