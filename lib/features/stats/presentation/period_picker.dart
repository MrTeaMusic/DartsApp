/// Eigener Zeitraum und Vergleich zweier Zeiträume in der Statistik.
library;

import 'package:flutter/material.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../domain/stats_calculator.dart';
import 'stats_widgets.dart';

/// Womit Zeitraum A verglichen wird.
class StatsCompare {
  /// Der gleich lange Zeitraum direkt vor A.
  const StatsCompare.before() : kind = StatsCompareKind.before, period = null;

  /// Derselbe Zeitraum ein Jahr früher.
  const StatsCompare.yearAgo() : kind = StatsCompareKind.yearAgo, period = null;

  /// Ein frei gewählter Zeitraum.
  const StatsCompare.custom(StatsPeriod this.period) : kind = StatsCompareKind.custom;

  final StatsCompareKind kind;
  final StatsPeriod? period;

  /// Zeitraum B zu [a]; `null`, wenn es keinen gibt (A = „Alles“ und B nicht
  /// selbst gewählt).
  StatsPeriod? resolve(StatsPeriod a, DateTime today) => switch (kind) {
    StatsCompareKind.before => a.before(today),
    StatsCompareKind.yearAgo => _yearAgo(a, today),
    StatsCompareKind.custom => period,
  };

  static StatsPeriod? _yearAgo(StatsPeriod a, DateTime today) {
    final r = StatsPeriod.resolved(a, today);
    if (!r.isCustom) return null;
    DateTime back(DateTime d) => DateTime(d.year - 1, d.month, d.day);
    return StatsPeriod.custom(back(r.from!), back(r.to!));
  }

  @override
  bool operator ==(Object other) => other is StatsCompare && other.kind == kind && other.period == period;

  @override
  int get hashCode => Object.hash(kind, period);
}

enum StatsCompareKind { before, yearAgo, custom }

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// „4.10.–2.11.“, mit Jahr, wenn der Zeitraum nicht im laufenden Jahr liegt;
/// ein einzelner Tag als „2.11.“. Feste Zeiträume werden bis [today] gerechnet.
String formatPeriodRange(StatsPeriod p, DateTime today) {
  final r = StatsPeriod.resolved(p, today);
  if (!r.isCustom) return '';
  final withYear = r.from!.year != today.year || r.to!.year != today.year;
  String f(DateTime d) => withYear ? formatDate(d) : formatDayMonth(d);
  return r.from == r.to ? f(r.from!) : '${f(r.from!)}–${f(r.to!)}';
}

/// Fragt einen eigenen Zeitraum ab (mindestens ein Tag, höchstens bis heute).
Future<StatsPeriod?> showPeriodSheet(
  BuildContext context, {
  required StatsPeriod initial,
  required DateTime today,
  String? title,
}) {
  return showModalBottomSheet<StatsPeriod>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => _PeriodSheet(initial: initial, today: _day(today), title: title),
  );
}

class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({required this.initial, required this.today, this.title});
  final StatsPeriod initial;
  final DateTime today;
  final String? title;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late DateTime from;
  late DateTime to;

  /// Frühester wählbarer Tag.
  static final DateTime first = DateTime(2020);

  @override
  void initState() {
    super.initState();
    final r = StatsPeriod.resolved(widget.initial, widget.today);
    from = r.from ?? DateTime(widget.today.year, widget.today.month, widget.today.day - 29);
    to = r.to ?? widget.today;
  }

  List<(String, DateTime, DateTime)> _quick(BuildContext context) {
    final l10n = context.l10n;
    final t = widget.today;
    final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
    return [
      (l10n.statsPeriodToday, t, t),
      (l10n.statsPeriodYesterday, DateTime(t.year, t.month, t.day - 1), DateTime(t.year, t.month, t.day - 1)),
      (l10n.statsPeriodThisWeek, monday, t),
      (
        l10n.statsPeriodLastWeek,
        DateTime(monday.year, monday.month, monday.day - 7),
        DateTime(monday.year, monday.month, monday.day - 1),
      ),
      (l10n.statsPeriodThisMonth, DateTime(t.year, t.month), t),
      (l10n.statsPeriodLastMonth, DateTime(t.year, t.month - 1), DateTime(t.year, t.month, 0)),
    ];
  }

  Future<void> _pick({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? from : to,
      firstDate: first,
      lastDate: widget.today,
      helpText: start ? context.l10n.statsPeriodFrom : context.l10n.statsPeriodTo,
    );
    if (picked == null || !mounted) return;
    setState(() {
      final d = _day(picked);
      if (start) {
        from = d;
        if (to.isBefore(from)) to = from;
      } else {
        to = d;
        if (from.isAfter(to)) from = to;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final period = StatsPeriod.custom(from, to);
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('period-sheet'),
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title ?? l10n.statsPeriodPickTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.m),
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                for (final (label, a, b) in _quick(context))
                  ChoiceChip(
                    label: Text(label),
                    selected: a == from && b == to,
                    onSelected: (_) => setState(() {
                      from = a;
                      to = b;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    key: const Key('period-from'),
                    label: l10n.statsPeriodFrom,
                    value: formatDate(from),
                    onTap: () => _pick(start: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: _DateField(
                    key: const Key('period-to'),
                    label: l10n.statsPeriodTo,
                    value: formatDate(to),
                    onTap: () => _pick(start: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              '${l10n.statsPeriodDays(period.days!)} · ${l10n.statsPeriodPickHint}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.l),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.statsPeriodCancel),
                ),
                const SizedBox(width: AppSpacing.s),
                FilledButton(
                  key: const Key('period-apply'),
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => Navigator.pop(context, period),
                  child: Text(l10n.statsPeriodApply),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({super.key, required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final colors = context.dartColors;
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(look.pill ? 16 : look.radiusS);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s + 2),
          child: Row(
            children: [
              Icon(Icons.event_rounded, size: 20, color: colors.textMuted),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.labelSmall?.copyWith(color: colors.textMuted)),
                    Text(value, style: theme.textTheme.titleMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fragt ab, womit Zeitraum [a] verglichen wird. Ergebnis `null` = Abbruch;
/// `(compare: null)` = Vergleich beenden.
Future<({StatsCompare? compare})?> showCompareSheet(
  BuildContext context, {
  required StatsPeriod a,
  required StatsCompare? current,
  required DateTime today,
}) {
  return showModalBottomSheet<({StatsCompare? compare})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => _CompareSheet(a: a, current: current, today: _day(today)),
  );
}

class _CompareSheet extends StatefulWidget {
  const _CompareSheet({required this.a, required this.current, required this.today});
  final StatsPeriod a;
  final StatsCompare? current;
  final DateTime today;

  @override
  State<_CompareSheet> createState() => _CompareSheetState();
}

class _CompareSheetState extends State<_CompareSheet> {
  late StatsCompare? choice = widget.current ?? (widget.a.days == null ? null : const StatsCompare.before());

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final a = widget.a;
    final aRange = a.days == null ? l10n.statsPeriodAll : formatPeriodRange(a, widget.today);
    String rangeOf(StatsCompare c) => switch (c.resolve(a, widget.today)) {
      final p? => '${formatPeriodRange(p, widget.today)} · ${l10n.statsPeriodDays(p.days!)}',
      null => '–',
    };
    final options = <(StatsCompare, String)>[
      if (a.days != null) ...[
        (const StatsCompare.before(), l10n.statsCompareBefore),
        (const StatsCompare.yearAgo(), l10n.statsCompareYearAgo),
      ],
    ];
    final custom = choice?.kind == StatsCompareKind.custom ? choice : null;
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('compare-sheet'),
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.statsCompareTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                const PeriodBadge(b: false),
                const SizedBox(width: AppSpacing.s),
                Expanded(child: Text(l10n.statsCompareAText(aRange), style: theme.textTheme.bodyMedium)),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            Row(
              children: [
                const PeriodBadge(b: true),
                const SizedBox(width: AppSpacing.s),
                Text(l10n.statsPeriodPickBTitle, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            if (a.days == null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s),
                child: Text(l10n.statsCompareAllHint, style: theme.textTheme.bodySmall),
              ),
            for (final (c, label) in options)
              _OptionTile(
                key: Key('compare-${c.kind.name}'),
                selected: choice == c,
                title: label,
                subtitle: rangeOf(c),
                onTap: () => setState(() => choice = c),
              ),
            _OptionTile(
              key: const Key('compare-custom'),
              selected: custom != null,
              title: l10n.statsCompareCustom,
              subtitle: custom == null ? null : rangeOf(custom),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: () async {
                final p = await showPeriodSheet(
                  context,
                  initial:
                      custom?.period ?? (const StatsCompare.before().resolve(a, widget.today) ?? StatsPeriod.month),
                  today: widget.today,
                  title: l10n.statsPeriodPickBTitle,
                );
                if (p != null && mounted) setState(() => choice = StatsCompare.custom(p));
              },
            ),
            const SizedBox(height: AppSpacing.l),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.current != null)
                  TextButton(
                    key: const Key('compare-stop'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => Navigator.pop(context, (compare: null)),
                    child: Text(l10n.statsCompareStop),
                  )
                else
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.statsPeriodCancel),
                  ),
                const SizedBox(width: AppSpacing.s),
                FilledButton.icon(
                  key: const Key('compare-apply'),
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: choice?.resolve(a, widget.today) == null
                      ? null
                      : () => Navigator.pop(context, (compare: choice)),
                  icon: const Icon(Icons.compare_arrows_rounded),
                  label: Text(l10n.statsCompareStart),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.selected,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });
  final bool selected;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final look = context.look;
    final radius = BorderRadius.circular(look.pill ? 16 : look.radiusS);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: radius,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: radius),
          leading: Icon(
            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
            color: selected ? scheme.primary : null,
          ),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: trailing,
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Kleines „A“ oder „B“ in der Farbe des Zeitraums.
class PeriodBadge extends StatelessWidget {
  const PeriodBadge({super.key, required this.b});
  final bool b;

  static Color colorOf(BuildContext context, {required bool b}) =>
      b ? context.dartColors.chartSecondary : context.dartColors.chartPrimary;

  @override
  Widget build(BuildContext context) {
    final color = colorOf(context, b: b);
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        b ? context.l10n.statsCompareB : context.l10n.statsCompareA,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Zeile unter dem Filter, solange verglichen wird: „A 4.10.–2.11. gegen B …“.
class CompareBar extends StatelessWidget {
  const CompareBar({
    super.key,
    required this.a,
    required this.b,
    required this.today,
    required this.onEdit,
    required this.onClose,
  });
  final StatsPeriod a;
  final StatsPeriod b;
  final DateTime today;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final look = context.look;
    String label(StatsPeriod p) =>
        p.days == null ? l10n.statsPeriodAll : '${formatPeriodRange(p, today)} · ${l10n.statsPeriodDays(p.days!)}';
    Widget side(StatsPeriod p, {required bool isB}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PeriodBadge(b: isB),
        const SizedBox(width: AppSpacing.xs + 2),
        Flexible(
          child: Text(label(p), style: theme.textTheme.labelLarge, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    return Material(
      key: const Key('compare-bar'),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(look.pill ? 99 : look.radiusM),
      child: InkWell(
        borderRadius: BorderRadius.circular(look.pill ? 99 : look.radiusM),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.m,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    side(a, isB: false),
                    Text(l10n.statsCompareVs, style: theme.textTheme.bodySmall),
                    side(b, isB: true),
                  ],
                ),
              ),
              IconButton(
                key: const Key('compare-close'),
                tooltip: l10n.statsCompareStop,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eine Zeile im Vergleich A gegen B.
class CompareRow {
  const CompareRow({
    required this.label,
    required this.a,
    required this.b,
    required this.kind,
    this.aDetail,
    this.bDetail,
    this.higherIsBetter = true,
    this.hasValues,
  });

  /// Quote aus Versuchen; ohne genug Versuche in einem Zeitraum `–`.
  factory CompareRow.rate(String label, HitCount a, HitCount b, {int minAttempts = 1}) => CompareRow(
    label: label,
    a: a.attempts >= minAttempts ? a.rate : null,
    b: b.attempts >= minAttempts ? b.rate : null,
    kind: ValueKind.percent,
    aDetail: '${a.hits}/${a.attempts}',
    bDetail: '${b.hits}/${b.attempts}',
    hasValues: a.attempts + b.attempts > 0,
  );

  final String label;
  final double? a;
  final double? b;
  final ValueKind kind;
  final String? aDetail;
  final String? bDetail;
  final bool higherIsBetter;

  /// Ob es in einem der Zeiträume Werte gibt; ohne Angabe: A oder B bekannt.
  final bool? hasValues;

  /// Zeilen ohne Werte in beiden Zeiträumen fallen weg.
  bool get hasData => hasValues ?? (a != null || b != null);
}

/// Tabelle A | B | Unterschied, in Abschnitte gegliedert.
class PeriodCompareCard extends StatelessWidget {
  const PeriodCompareCard({super.key, required this.sections, this.hint, this.title});
  final List<(String, List<CompareRow>)> sections;
  final String? hint;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final visible = [
      for (final (name, rows) in sections)
        if (rows.where((r) => r.hasData).toList() case final kept when kept.isNotEmpty) (name, kept),
    ];
    return ChartCard(
      key: const Key('stats-compare-card'),
      title: title ?? l10n.statsCompareCardTitle,
      hint: hint,
      child: visible.isEmpty
          ? NoDataHint(text: l10n.statsCompareNoData, height: 80)
          : LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 520 || (c.maxWidth >= 900 && c.maxWidth < 1040);
                final valueW = narrow ? 64.0 : 96.0;
                final diffW = narrow ? 66.0 : 90.0;
                Widget sectionName(String name) => Text(
                  name.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.textMuted, letterSpacing: 0.8),
                );
                Widget head(String name) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: sectionName(name)),
                      SizedBox(
                        width: valueW,
                        child: const Align(alignment: Alignment.centerRight, child: PeriodBadge(b: false)),
                      ),
                      SizedBox(
                        width: valueW,
                        child: const Align(alignment: Alignment.centerRight, child: PeriodBadge(b: true)),
                      ),
                      SizedBox(
                        width: diffW,
                        child: Text(
                          narrow ? 'Δ' : l10n.statsCompareDiff,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: colors.textMuted),
                        ),
                      ),
                    ],
                  ),
                );
                Widget value(double? v, String? detail, ValueKind kind) => SizedBox(
                  width: valueW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatValue(kind, v), style: theme.textTheme.titleSmall),
                      if (detail != null)
                        Text(
                          detail,
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                );
                Widget row(CompareRow r) {
                  final d = MetricDelta.of(r.a, r.b, r.kind, higherIsBetter: r.higherIsBetter);
                  final color = d == null || d.flat ? colors.textMuted : (d.improved ? colors.success : colors.danger);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: ConstrainedBox(
                      // Gleiche Zeilenhöhe mit und ohne Treffer/Versuche darunter.
                      constraints: const BoxConstraints(minHeight: 36),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.label,
                              style: theme.textTheme.labelLarge,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          value(r.a, r.aDetail, r.kind),
                          value(r.b, r.bDetail, r.kind),
                          SizedBox(
                            width: diffW,
                            child: Text(
                              d == null ? '–' : d.text,
                              textAlign: TextAlign.right,
                              style: theme.textTheme.titleSmall?.copyWith(color: color),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                Widget column(List<(String, List<CompareRow>)> list) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, (name, rows)) in list.indexed) ...[
                      if (i > 0) Divider(height: AppSpacing.l, color: colors.textMuted.withValues(alpha: 0.2)),
                      if (i == 0)
                        head(name)
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: sectionName(name),
                        ),
                      for (final r in rows) row(r),
                    ],
                  ],
                );

                // Breit: Abschnitte auf zwei Spalten verteilt (der letzte rechts).
                if (c.maxWidth >= 900 && visible.length >= 2) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: column(visible.sublist(0, visible.length - 1))),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(child: column([visible.last])),
                    ],
                  );
                }
                return column(visible);
              },
            ),
    );
  }
}
