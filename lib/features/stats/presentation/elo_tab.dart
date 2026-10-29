import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../domain/stats_calculator.dart';
import 'stats_charts.dart';
import 'stats_screen.dart';
import 'stats_widgets.dart';

/// Gewählte Art Gegner in der Tabelle (`null` = alle).
final eloOpponentFilterProvider = NotifierProvider<_EloFilterNotifier, EloOpponentKind?>(_EloFilterNotifier.new);

class _EloFilterNotifier extends Notifier<EloOpponentKind?> {
  @override
  EloOpponentKind? build() => null;
  void set(EloOpponentKind? kind) => state = kind;
}

/// Elo ganzzahlig, wie angezeigt.
String formatElo(double v) => v.round().toString();

/// Veränderung mit Vorzeichen („+12“, „−7“, „±0“).
String formatEloChange(double d) {
  final n = d.round();
  return n > 0 ? '+$n' : (n < 0 ? '−${-n}' : '±0');
}

Color eloChangeColor(BuildContext context, double d) {
  final colors = context.dartColors;
  final n = d.round();
  return n > 0 ? colors.success : (n < 0 ? colors.danger : colors.textMuted);
}

const _gap = SectionGap(factor: 0.8);

/// Reiter „Elo“: Haus-Elo aus den Matches (siehe `docs/haus-elo.md`).
/// Der Reiter liest nur; alles kommt fertig aus
/// [StatsCalculator.houseElo]. Kennzahlen gelten für alle Matches, Verlauf,
/// Gegner und Highlights für den gewählten Zeitraum.
class EloTab extends ConsumerWidget {
  const EloTab({super.key, required this.view, required this.wide, required this.pad});
  final StatsView view;
  final bool wide;
  final double pad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = view.calc.houseElo;
    final from = view.calc.periodStart(view.period);
    final trendFrom = view.calc.periodStart(StatsPeriod.month)!;
    return ListView(
      key: const Key('stats-list-elo'),
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.m, pad, AppSpacing.xxl),
      children: [
        _Summary(report: report, wide: wide, trendFrom: trendFrom),
        _gap,
        if (!report.hasHistory) ...[
          _EmptyCard(matches: report.matches),
        ] else ...[
          _ChartSection(report: report, from: from),
          _gap,
          _OpponentsCard(report: report, from: from),
          _gap,
          TwoColumns(
            wide: wide,
            left: _HighlightCard(
              key: const Key('elo-best'),
              keyPrefix: 'elo-best',
              title: context.l10n.eloBestTitle,
              empty: context.l10n.eloBestEmpty,
              icon: Icons.emoji_events_rounded,
              steps: report.bestWins(from: from),
            ),
            right: _HighlightCard(
              key: const Key('elo-worst'),
              keyPrefix: 'elo-worst',
              title: context.l10n.eloWorstTitle,
              empty: context.l10n.eloWorstEmpty,
              icon: Icons.heart_broken_rounded,
              steps: report.worstLosses(from: from),
            ),
          ),
        ],
        _gap,
        const _ExplainCard(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Kennzahlen
// ---------------------------------------------------------------------------

class _Summary extends StatelessWidget {
  const _Summary({required this.report, required this.wide, required this.trendFrom});
  final HouseEloReport report;
  final bool wide;
  final DateTime trendFrom;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gap = context.look.gridGap;
    final n = report.matches;
    final matches = StatTile(
      key: const Key('elo-matches'),
      label: l10n.eloKpiMatches,
      value: '$n',
      caption: n == 0
          ? null
          : l10n.eloKpiMatchesCaption(
              report.count(EloOpponentKind.bot),
              report.count(EloOpponentKind.online),
              report.count(EloOpponentKind.local),
            ),
      icon: Icons.sports_score_rounded,
    );
    final record = StatTile(
      key: const Key('elo-record'),
      label: l10n.eloKpiRecord,
      value: n == 0 ? '–' : '${report.wins}–${report.losses}',
      caption: n == 0 ? null : l10n.eloKpiRecordCaption((report.wins * 100 / n).round()),
      icon: Icons.balance_rounded,
    );
    final hero = _Hero(report: report, trendFrom: trendFrom, sideBySide: wide);
    if (wide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 2, child: hero),
            SizedBox(width: gap),
            Expanded(child: matches),
            SizedBox(width: gap),
            Expanded(child: record),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hero,
        SizedBox(height: gap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: matches),
              SizedBox(width: gap),
              Expanded(child: record),
            ],
          ),
        ),
      ],
    );
  }
}

/// Aktuelles Elo groß, daneben der Rekord.
class _Hero extends StatelessWidget {
  const _Hero({required this.report, required this.trendFrom, required this.sideBySide});
  final HouseEloReport report;
  final DateTime trendFrom;

  /// Rekord neben der Zahl (breit) oder darunter (schmal). Kein
  /// `LayoutBuilder`: Die Karte steht in einer `IntrinsicHeight`-Zeile.
  final bool sideBySide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final look = context.look;
    final colors = context.dartColors;
    final ready = report.hasHistory;
    final big = look.statValue.copyWith(fontSize: (look.statValue.fontSize ?? 44) * 1.55, color: theme.colorScheme.onSurface);
    final peak = report.peakStep;
    final delta = ready ? report.changeSince(trendFrom) : null;
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Kicker(l10n.eloKpiElo),
        SizedBox(height: look.id == DartLookId.lab ? AppSpacing.s : AppSpacing.m),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(ready ? formatElo(report.current) : '–', key: const Key('elo-value'), style: big),
        ),
        if (delta != null) ...[
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              ChangePill(key: const Key('elo-trend'), change: delta),
              const SizedBox(width: AppSpacing.s),
              Expanded(child: Text(l10n.eloKpiEloCaption, style: theme.textTheme.bodySmall, maxLines: 2)),
            ],
          ),
        ],
      ],
    );
    final peakValue = Text(
      ready && peak != null ? formatElo(peak.after) : '–',
      key: const Key('elo-peak'),
      style: look.chipNumber.copyWith(fontSize: (look.chipNumber.fontSize ?? 24) * 1.25, color: theme.colorScheme.onSurface),
    );
    final peakDate = ready && peak != null
        ? Text(
            l10n.eloKpiPeakCaption(formatDate(peak.at)),
            key: const Key('elo-peak-date'),
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
            maxLines: 2,
          )
        : null;
    return AppCard(
      key: const Key('elo-hero'),
      child: Builder(builder: (context) {
        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              const SizedBox(width: AppSpacing.l),
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Kicker(l10n.eloKpiPeak),
                    SizedBox(height: look.id == DartLookId.lab ? AppSpacing.s : AppSpacing.m),
                    peakValue,
                    if (peakDate != null) ...[const SizedBox(height: AppSpacing.xs), peakDate],
                  ],
                ),
              ),
            ],
          );
        }
        // Schmal: der Rekord steht in einer Zeile darunter.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            main,
            const Divider(height: AppSpacing.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Kicker(l10n.eloKpiPeak),
                      if (peakDate != null) ...[const SizedBox(height: AppSpacing.xs), peakDate],
                    ],
                  ),
                ),
                peakValue,
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// Veränderung als kleine Pille: grün plus, rot minus, grau null.
class ChangePill extends StatelessWidget {
  const ChangePill({super.key, required this.change});
  final double change;

  @override
  Widget build(BuildContext context) {
    final color = eloChangeColor(context, change);
    final look = context.look;
    final up = change.round() > 0;
    final down = change.round() < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s - 2, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(look.pill ? 99 : look.radiusS),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_upward_rounded : (down ? Icons.arrow_downward_rounded : Icons.trending_flat_rounded),
            size: 13,
            color: color,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            formatEloChange(change),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontFeatures: DartLooks.tabular),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leerzustand
// ---------------------------------------------------------------------------

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.matches});
  final int matches;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    return AppCard(
      key: const Key('elo-empty'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: Icons.show_chart_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.eloEmptyTitle, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(l10n.eloEmptyText, style: theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted)),
                  const SizedBox(height: AppSpacing.m),
                  Text(
                    l10n.eloEmptyProgress(matches, HouseEloRules.minMatchesForChart),
                    key: const Key('elo-empty-progress'),
                    style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Verlauf
// ---------------------------------------------------------------------------

class _ChartSection extends StatelessWidget {
  const _ChartSection({required this.report, required this.from});
  final HouseEloReport report;
  final DateTime? from;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ChartCard(
      key: const Key('elo-chart'),
      title: l10n.eloChartTitle,
      hint: l10n.eloChartHint,
      child: TrendLineChart(
        points: report.trend(from),
        format: (v) => v.round().toString(),
        emptyText: l10n.eloChartEmpty,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gegner
// ---------------------------------------------------------------------------

/// Spaltenbreiten der Tabelle.
const double _colMatches = 58;
const double _colRecord = 50;
const double _colRating = 54;
const double _colChange = 50;

/// So viele Gegner zeigt die Tabelle zuerst.
const int _opponentRows = 8;

String _kindLabel(AppLocalizations l10n, EloOpponent o) => switch (o.kind) {
      EloOpponentKind.online => l10n.eloKindOnline,
      EloOpponentKind.local => l10n.eloKindLocal,
      EloOpponentKind.bot => o.botAverage == null ? l10n.eloKindBot : l10n.eloKindBotAverage(o.botAverage!.round().toString()),
    };

class _OpponentsCard extends ConsumerStatefulWidget {
  const _OpponentsCard({required this.report, required this.from});
  final HouseEloReport report;
  final DateTime? from;

  @override
  ConsumerState<_OpponentsCard> createState() => _OpponentsCardState();
}

class _OpponentsCardState extends ConsumerState<_OpponentsCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final filter = ref.watch(eloOpponentFilterProvider);
    final all = widget.report.opponents(from: widget.from, kind: filter);
    final shown = _all ? all : all.take(_opponentRows).toList();
    Widget head(String text, double width, {TextAlign align = TextAlign.right}) => SizedBox(
          width: width,
          child: Align(
            alignment: align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
            child: FittedBox(fit: BoxFit.scaleDown, child: Kicker(text)),
          ),
        );
    final filters = <(EloOpponentKind?, String, String)>[
      (null, 'all', l10n.eloFilterAll),
      (EloOpponentKind.online, 'online', l10n.eloFilterOnline),
      (EloOpponentKind.bot, 'bots', l10n.eloFilterBots),
      (EloOpponentKind.local, 'local', l10n.eloFilterLocal),
    ];
    return AppCard(
      key: const Key('elo-opponents'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(l10n.eloOpponentsTitle),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              for (final (kind, key, label) in filters)
                ChoiceChip(
                  key: Key('elo-filter-$key'),
                  label: Text(label),
                  selected: filter == kind,
                  onSelected: (_) => ref.read(eloOpponentFilterProvider.notifier).set(kind),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          if (all.isEmpty)
            NoDataHint(key: const Key('elo-opponents-empty'), text: l10n.eloOpponentsEmpty, height: 80)
          else ...[
            Row(
              children: [
                Expanded(child: Align(alignment: Alignment.centerLeft, child: Kicker(l10n.eloOpponentsTitle))),
                head(l10n.eloColMatches, _colMatches),
                head(l10n.eloColRecord, _colRecord),
                head(l10n.eloColRating, _colRating),
                head(l10n.eloColChange, _colChange),
              ],
            ),
            for (final o in shown) ...[
              const Divider(height: AppSpacing.l),
              Row(
                key: Key('elo-opponent-${o.id}'),
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.name, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          _kindLabel(l10n, o),
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _cell('${o.matches}', _colMatches, theme),
                  _cell('${o.wins}–${o.losses}', _colRecord, theme),
                  _cell(formatElo(o.rating), _colRating, theme),
                  SizedBox(
                    width: _colChange,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        formatEloChange(o.change),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: eloChangeColor(context, o.change),
                          fontFeatures: DartLooks.tabular,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (all.length > _opponentRows)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('elo-opponents-more'),
                  onPressed: () => setState(() => _all = !_all),
                  child: Text(_all ? l10n.eloOpponentsLess : l10n.eloOpponentsMore(all.length)),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.m),
          Text(l10n.eloOpponentsHint, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }

  Widget _cell(String text, double width, ThemeData theme) => SizedBox(
        width: width,
        child: Text(
          text,
          textAlign: TextAlign.right,
          maxLines: 1,
          style: theme.textTheme.titleSmall?.copyWith(fontFeatures: DartLooks.tabular),
        ),
      );
}

// ---------------------------------------------------------------------------
// Größte Siege, bitterste Niederlagen
// ---------------------------------------------------------------------------

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    super.key,
    required this.keyPrefix,
    required this.title,
    required this.empty,
    required this.icon,
    required this.steps,
  });
  final String keyPrefix;
  final String title;
  final String empty;
  final IconData icon;
  final List<EloStep> steps;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title),
          if (steps.isEmpty)
            NoDataHint(text: empty, height: 72)
          else
            for (final (i, s) in steps.indexed) ...[
              if (i > 0) const Divider(height: AppSpacing.l),
              Row(
                key: Key('$keyPrefix-$i'),
                children: [
                  Icon(icon, size: 18, color: colors.textMuted),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.match.opponentName, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          s.match.legsWon != null && s.match.legsLost != null
                              ? l10n.eloHighlightLineLegs(s.opponentBefore.round(), '${s.match.legsWon}:${s.match.legsLost}', formatDayMonth(s.at))
                              : l10n.eloHighlightLine(s.opponentBefore.round(), formatDayMonth(s.at)),
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  ChangePill(change: s.change),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Erklärung
// ---------------------------------------------------------------------------

class _ExplainCard extends StatelessWidget {
  const _ExplainCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    return AppCard(
      key: const Key('elo-explain'),
      onTap: () => showEloExplanation(context),
      child: Row(
        children: [
          IconBadge(icon: Icons.help_outline_rounded, color: theme.colorScheme.primary, size: 40),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.eloExplainTitle, style: theme.textTheme.titleSmall),
                Text(l10n.eloExplainSubtitle, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.textMuted),
        ],
      ),
    );
  }
}

/// Kurze Erklärung als Bottom-Sheet.
Future<void> showEloExplanation(BuildContext context) {
  final l10n = context.l10n;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: SingleChildScrollView(
          key: const Key('elo-explain-sheet'),
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.eloExplainHeadline, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.m),
              for (final text in [
                l10n.eloExplain1,
                l10n.eloExplain2,
                l10n.eloExplain3,
                l10n.eloExplain4,
              ]) ...[
                Text(text, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.m),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.eloExplainClose),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
