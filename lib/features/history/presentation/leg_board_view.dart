import 'package:flutter/material.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/domain/engine/game_display.dart';
import '../../matches/domain/match_format.dart';
import '../../stats/presentation/stats_charts.dart';
import '../../stats/presentation/stats_widgets.dart';
import '../domain/leg_board.dart';
import '../domain/session_history.dart';

/// Farbe eines Spielers im Aufnahmenverlauf: man selbst in der Hauptfarbe der
/// Diagramme, der Gegner in der zweiten.
Color legSideColor(BuildContext context, int index) {
  final colors = context.dartColors;
  return index == 0 ? colors.chartPrimary : colors.chartSecondary;
}

/// Die Legs eines X01-Matches oder -Trainings: Aufnahmenverlauf (Rest über
/// die Aufnahme, eine Linie je Spieler) und darunter die Tabelle der
/// Aufnahmen mit Wurfbild, Rest und verpassten Doppeln. Bei mehreren Legs
/// wählt man „Alle Legs“ oder ein einzelnes.
class LegBoardSection extends StatefulWidget {
  const LegBoardSection({super.key, required this.detail, required this.boards});
  final SessionDetail detail;
  final LegBoards boards;

  @override
  State<LegBoardSection> createState() => _LegBoardSectionState();
}

class _LegBoardSectionState extends State<LegBoardSection> {
  /// Index in `boards.legs`, `null` = alle.
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final boards = widget.boards;
    final detail = widget.detail;
    final legs = boards.legs;
    final selected = _selected != null && _selected! < legs.length ? _selected : null;
    final shown = selected == null ? legs : [legs[selected]];
    final imported = detail.entry.isImported;
    return Column(
      key: const Key('session-visits'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          l10n.histLegs,
          trailing: Text(
            legs.length > 1 ? l10n.histLegsCount(legs.length) : l10n.histVisitsCount(legs.first.sides.first.visits.length),
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (legs.length > 1) ...[
          _LegPicker(detail: detail, boards: boards, selected: selected, onSelect: (i) => setState(() => _selected = i)),
          const SizedBox(height: AppSpacing.m),
        ],
        if (imported)
          _Note(l10n.impVisitsNote, key: const Key('session-visits-note'))
        else if (detail.entry.isMatch && !boards.hasOpponent)
          _Note(l10n.histLegNoOpponent, key: const Key('session-legs-note')),
        for (final (i, board) in shown.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xl),
          LegBlock(detail: detail, boards: boards, board: board),
        ],
        const SizedBox(height: AppSpacing.m),
        _Legend(boards: boards, colors: colors),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.m),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.dartColors.textMuted)),
      );
}

/// „Alle Legs“ und ein Chip je Leg (mit Satz, wenn mit Sätzen gespielt wird).
class _LegPicker extends StatelessWidget {
  const _LegPicker({required this.detail, required this.boards, required this.selected, required this.onSelect});
  final SessionDetail detail;
  final LegBoards boards;
  final int? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sets = detail.entry.hasOpponent && MatchFormat.fromJson(detail.entry.details['format'] ?? detail.entry.config).usesSets;
    return Wrap(
      key: const Key('leg-picker'),
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.xs,
      children: [
        ChoiceChip(
          key: const Key('leg-pick-all'),
          label: Text(l10n.histLegAll),
          selected: selected == null,
          onSelected: (_) => onSelect(null),
        ),
        for (final (i, b) in boards.legs.indexed)
          ChoiceChip(
            key: Key('leg-pick-${b.number}'),
            label: Text(sets ? l10n.matchLegSetNumber(b.leg.set, b.number) : l10n.matchLegNumber(b.number)),
            selected: selected == i,
            onSelected: (_) => onSelect(i),
          ),
      ],
    );
  }
}

/// Ein Leg: Überschrift, Aufnahmenverlauf und Tabelle.
class LegBlock extends StatelessWidget {
  const LegBlock({super.key, required this.detail, required this.boards, required this.board});
  final SessionDetail detail;
  final LegBoards boards;
  final LegBoard board;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final named = board.sides.any((s) => s.name.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (board.number > 0) LegHeader(detail: detail, leg: board.leg),
        ChartCard(
          key: Key('session-leg-${board.number}-chart'),
          title: l10n.histLegCourse,
          hint: l10n.histLegCourseHint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (named) ...[
                Wrap(
                  spacing: AppSpacing.l,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final (i, s) in board.sides.indexed)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 14,
                            height: 4,
                            decoration: BoxDecoration(color: legSideColor(context, i), borderRadius: BorderRadius.circular(2)),
                          ),
                          const SizedBox(width: AppSpacing.xs + 2),
                          Text(s.name, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),
              ],
              SizedBox(
                height: 200,
                child: LegProgressChart(
                  startScore: board.startScore,
                  visits: board.rows,
                  lines: [
                    for (final (i, s) in board.sides.indexed)
                      LegLine(name: named ? s.name : '', color: legSideColor(context, i), rests: s.rests),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        LegTable(key: Key('session-leg-${board.number}'), board: board),
      ],
    );
  }
}

/// „Leg 2“ mit Sieger und Checkout.
class LegHeader extends StatelessWidget {
  const LegHeader({super.key, required this.detail, required this.leg});
  final SessionDetail detail;
  final HistoryLeg leg;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final format = detail.entry.hasOpponent ? MatchFormat.fromJson(detail.entry.details['format'] ?? detail.entry.config) : null;
    final title = format != null && format.usesSets ? l10n.matchLegSetNumber(leg.set, leg.number) : l10n.matchLegNumber(leg.number);
    final w = leg.winner;
    final mine = w == null ? null : w == detail.me || !detail.entry.hasOpponent;
    final name = w == null || detail.players.length <= w ? null : detail.players[w].name;
    final String info;
    if (w == null) {
      info = l10n.histLegOpen;
    } else if (name != null && leg.checkout != null && leg.winnerDarts != null) {
      info = l10n.histLegWon(name, leg.checkout!, leg.winnerDarts!);
    } else {
      info = name ?? '';
    }
    final color = mine == null ? colors.textMuted : (mine ? colors.success : colors.danger);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Row(
        children: [
          Container(width: 4, height: 18, color: color),
          const SizedBox(width: AppSpacing.s),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text(
              info,
              key: Key('session-leg-info-${leg.number}'),
              style: theme.textTheme.bodySmall?.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Zwei (oder eine) Spalten mit den Aufnahmen eines Legs: links die
/// Aufnahme-Nummer, je Spieler die Punkte fett, darunter das Wurfbild, rechts
/// der Rest danach. 100 und mehr sind getönt, der Checkout grün, ein Bust
/// rot; verpasste Doppel tragen eine kleine Marke.
class LegTable extends StatelessWidget {
  const LegTable({super.key, required this.board});
  final LegBoard board;

  static const double _numberWidth = 26;

  /// Höhe einer Zeile: Punkte und Wurfbild übereinander.
  static double rowHeight(DartLook look) => look.id == DartLookId.tv ? 58 : 54;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final colors = context.dartColors;
    final sides = board.sides;
    final h = rowHeight(look);
    final inset = look.cardPadding * 0.5;
    final footer = sides.any((s) => !s.doubles.isEmpty);
    return AppCard(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.s, horizontal: inset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: _numberWidth),
              for (final (i, s) in sides.indexed) Expanded(child: _SideHeader(side: s, index: i, board: board)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var r = 0; r < board.rows; r++)
            SizedBox(
              height: h,
              child: Row(
                children: [
                  SizedBox(
                    width: _numberWidth,
                    child: Text(
                      '${r + 1}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted, fontFeatures: DartLooks.tabular),
                    ),
                  ),
                  for (final s in sides)
                    Expanded(
                      child: r < s.visits.length
                          ? _VisitCell(
                              key: Key('leg-${board.number}-p${s.player}-v${r + 1}'),
                              visit: s.visits[r],
                              rest: s.rests[r + 1],
                              lastOfWinner: board.leg.winner == s.player && r == s.visits.length - 1 && s.finished,
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          if (footer) ...[
            const Divider(height: AppSpacing.l),
            Row(
              key: Key('leg-${board.number}-doubles'),
              children: [
                const SizedBox(width: _numberWidth),
                for (final s in sides)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: s.doubles.isEmpty
                          ? const SizedBox.shrink()
                          : Text(
                              context.l10n.histLegDoublesShort(s.doubles.hits, s.doubles.attempts),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                            ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Kopf einer Spalte: Farbpunkt, Name und Startwert.
class _SideHeader extends StatelessWidget {
  const _SideHeader({required this.side, required this.index, required this.board});
  final LegBoardSide side;
  final int index;
  final LegBoard board;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = context.look;
    final colors = context.dartColors;
    final color = legSideColor(context, index);
    final won = board.leg.winner == side.player;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: AppSpacing.xs + 2),
          Expanded(
            child: Text(
              side.name.isEmpty ? context.l10n.histLegStart : side.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(color: won ? colors.success : null),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _RestChip(text: '${side.startScore}', look: look, muted: true),
        ],
      ),
    );
  }
}

/// Kleines Schild mit dem Rest.
class _RestChip extends StatelessWidget {
  const _RestChip({required this.text, required this.look, this.color, this.muted = false});
  final String text;
  final DartLook look;
  final Color? color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final theme = Theme.of(context);
    final fg = color ?? (muted ? colors.textMuted : theme.colorScheme.onSurface);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color == null ? colors.surfaceHigh.withValues(alpha: 0.9) : color!.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(look.pill ? 99 : look.radiusS),
      ),
      child: Text(text, style: look.chipNumber.copyWith(fontSize: 13.5, color: fg)),
    );
  }
}

/// Eine Aufnahme eines Spielers.
class _VisitCell extends StatelessWidget {
  const _VisitCell({super.key, required this.visit, required this.rest, required this.lastOfWinner});
  final HistoryVisit visit;
  final int rest;
  final bool lastOfWinner;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final look = context.look;
    final colors = context.dartColors;
    final v = visit;
    final points = v.score;
    final big = !v.bust && points >= 100;
    final Color? tint = v.checkout
        ? colors.success.withValues(alpha: 0.14)
        : v.bust
            ? colors.danger.withValues(alpha: 0.08)
            : big
                ? colors.record.withValues(alpha: points >= 180 ? 0.24 : (points >= 140 ? 0.17 : 0.1))
                : null;
    final pointsStyle = look.chipNumber.copyWith(
      fontSize: look.id == DartLookId.tv ? 22 : 18,
      color: v.bust ? colors.danger : (big ? colors.record : theme.colorScheme.onSurface),
    );
    final small = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(fontSize: 11.5, height: 1.1, fontFeatures: DartLooks.tabular);
    final misses = missedDoublesOf(v);
    return Semantics(
      container: true,
      label: l10n.histLegSemantics(v.number, points, rest),
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(look.pill ? 12 : look.radiusM),
          border: lastOfWinner ? Border.all(color: colors.success.withValues(alpha: 0.7)) : null,
        ),
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 190;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 54),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(v.bust ? l10n.histBust : '$points', style: pointsStyle),
                    ),
                  ),
                  // Verpasste Doppel: kleine Marke zwischen Punkten und Rest.
                  Expanded(
                    child: misses.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: _MissedDoubles(misses: misses, wide: wide),
                            ),
                          ),
                  ),
                  v.checkout
                      ? _RestChip(text: '0', look: look, color: colors.success)
                      : _RestChip(text: '$rest', look: look, muted: v.bust),
                ],
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(TextSpan(children: _dartSpans(context, v, small))),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// „T20 S20 S20“: verpasste Doppel rot, das Finish grün, nicht gezählte
  /// Darts durchgestrichen.
  List<InlineSpan> _dartSpans(BuildContext context, HistoryVisit v, TextStyle base) {
    final colors = context.dartColors;
    return [
      for (final (i, d) in v.darts.take(4).indexed) ...[
        if (i > 0) TextSpan(text: ' ', style: base),
        TextSpan(
          text: d.segment.name,
          style: !d.counted
              ? base.copyWith(color: colors.textMuted.withValues(alpha: 0.6), decoration: TextDecoration.lineThrough)
              : d.finishAttempt
                  ? base.copyWith(color: d.hit ? colors.success : colors.danger, fontWeight: FontWeight.w700)
                  : base.copyWith(color: colors.textMuted),
        ),
      ],
    ];
  }
}

/// Marke „D16 verpasst“ (schmal: „D16“, bei mehreren Versuchen „D16 ×2“).
class _MissedDoubles extends StatelessWidget {
  const _MissedDoubles({required this.misses, required this.wide});
  final List<DoubleTry> misses;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final look = context.look;
    final colors = context.dartColors;
    // Je Doppel einmal, mit Anzahl.
    final counts = <String, int>{};
    for (final m in misses) {
      counts[m.label] = (counts[m.label] ?? 0) + 1;
    }
    final entries = counts.entries.take(2).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, e) in entries.indexed) ...[
          if (i > 0) const SizedBox(width: 3),
          Tooltip(
            message: e.value == 1 ? l10n.histDoubleMissed(e.key) : l10n.histDoubleMissedTimes(e.key, e.value),
            child: Container(
              key: Key('missed-double-${e.key}'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(look.pill ? 99 : look.radiusS),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close_rounded, size: 11, color: colors.danger),
                  const SizedBox(width: 2),
                  Text(
                    [e.key, if (e.value > 1) '×${e.value}', if (wide && entries.length == 1) l10n.histDoubleMissedShort].join(' '),
                    maxLines: 1,
                    style: look.chipNumber.copyWith(fontSize: 12, color: colors.danger, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Erklärung der Farben unter den Legs.
class _Legend extends StatelessWidget {
  const _Legend({required this.boards, required this.colors});
  final LegBoards boards;
  final DartColors colors;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    Widget swatch(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                border: Border.all(color: color, width: 1.5),
                borderRadius: BorderRadius.circular(context.look.radiusS.clamp(2, 4).toDouble()),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        );
    return Wrap(
      key: const Key('leg-legend'),
      spacing: AppSpacing.l,
      runSpacing: AppSpacing.xs,
      children: [
        swatch(colors.record, l10n.histLegendHundred),
        swatch(colors.success, l10n.histLegendFinishHit),
        if (boards.anyDoubles) swatch(colors.danger, l10n.histLegendDoubleMissed),
      ],
    );
  }
}

/// „Doppel“: Doppelquote je Spieler und die Doppel, auf die geworfen wurde.
class DoublesSummary extends StatelessWidget {
  const DoublesSummary({super.key, required this.boards});
  final LegBoards boards;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    return AppCard(
      key: const Key('session-doubles'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Kicker(l10n.histDoubles),
          for (final (i, p) in boards.players.indexed) ...[
            SizedBox(height: i == 0 ? AppSpacing.s : AppSpacing.m),
            _PlayerDoubles(
              key: Key('session-doubles-p${p.player}'),
              name: p.name,
              color: legSideColor(context, i),
              tally: boards.doublesOf(p.player),
              rateKey: i == 0 ? const Key('session-finish-attempts') : null,
            ),
          ],
          const SizedBox(height: AppSpacing.m),
          Text(l10n.histDoubleHint, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }
}

class _PlayerDoubles extends StatelessWidget {
  const _PlayerDoubles({super.key, required this.name, required this.color, required this.tally, this.rateKey});
  final String name;
  final Color color;
  final DoubleTally tally;
  final Key? rateKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final rate = tally.total.rate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Training ohne Namen: keine Kopfzeile, es gibt nur einen Spieler.
        if (name.isNotEmpty) ...[
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: AppSpacing.s),
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (tally.isEmpty)
          Text(l10n.histDoubleNone, style: theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted))
        else ...[
          Text(
            '${l10n.histDoubleRate(tally.hits, tally.attempts)}${rate == null ? '' : ' · ${formatPercent(rate)}'}',
            key: rateKey,
            style: theme.textTheme.bodyMedium,
          ),
          if (tally.perDouble.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s),
            Wrap(
              spacing: AppSpacing.xs + 2,
              runSpacing: AppSpacing.xs + 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.histDoubleThrownAt, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
                for (final e in tally.ranked)
                  Container(
                    key: Key('double-chip-${e.key}'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (e.value.hits > 0 ? colors.success : colors.danger).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(look.pill ? 99 : look.radiusS),
                    ),
                    child: Text(
                      l10n.histDoubleChip(doubleName(e.key), e.value.hits, e.value.attempts),
                      style: look.chipNumber.copyWith(
                        fontSize: 13,
                        color: e.value.hits > 0 ? colors.success : colors.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
