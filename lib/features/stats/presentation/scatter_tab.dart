import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../board/presentation/dartboard_view.dart';
import '../domain/stats_calculator.dart';
import 'double_insights.dart';
import 'stats_screen.dart';
import 'stats_widgets.dart';

/// Auswahl Training/Match der Streuungs-Analyse.
final scatterScopeProvider = NotifierProvider<_ScopeNotifier, ScatterScope>(_ScopeNotifier.new);

class _ScopeNotifier extends Notifier<ScatterScope> {
  @override
  ScatterScope build() => ScatterScope.all;
  void set(ScatterScope s) => state = s;
}

/// Gewähltes Feld (Kurzname wie „T20“); `null` = das mit den meisten Darts.
final scatterFieldProvider = NotifierProvider<StringChoice, String?>(StringChoice.new);

const _gap = SectionGap(factor: 0.8);

/// Höchstens so viele Punkte im Ausschnitt (die neuesten).
const int _maxFocusPoints = 300;

/// Farbe der Zeichnungen auf der Scheibe: gut sichtbar auf Rot, Grün,
/// Schwarz und Creme, unabhängig vom Theme.
const Color _boardInk = Color(0xFFFFFFFF);
const Color _boardAccent = Color(0xFFFFD23F);

/// Millimeter ohne Nachkommastelle.
String _mm(double v) => v.abs().round().toString();

/// Reiter „Streuung“: Wohin verzieht man je Zielfeld, wie stark streut es,
/// mit Tipp je Feld. Die Zahlen kommen fertig aus dem [StatsCalculator]
/// (je Zeitraum, Spiel und Auswahl zwischengespeichert).
class ScatterTab extends ConsumerWidget {
  const ScatterTab({super.key, required this.view, required this.wide, required this.pad});
  final StatsView view;
  final bool wide;
  final double pad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scope = ref.watch(scatterScopeProvider);
    final report = view.calc.scatterReport(view.period, gameId: view.gameId, scope: scope);
    final picked = ref.watch(scatterFieldProvider);
    FieldScatter? selected;
    for (final f in report.fields) {
      if (f.field.name == picked) selected = f;
    }
    selected ??= report.fields.firstOrNull;
    void select(FieldScatter f) => ref.read(scatterFieldProvider.notifier).set(f.field.name);

    return ListView(
      key: const Key('stats-list-scatter'),
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.m, pad, AppSpacing.xxl),
      children: [
        _ScopeChips(scope: scope),
        const SizedBox(height: AppSpacing.m),
        if (report.isEmpty || selected == null)
          _Empty(report: report)
        else ...[
          _Overview(report: report),
          _gap,
          TwoColumns(
            wide: wide,
            left: _BoardCard(report: report, selected: selected),
            right: _FocusCard(report: report, field: selected, onSelect: select),
          ),
          _gap,
          SectionHeader(l10n.scatterListTitle),
          AppCard(
            key: const Key('scatter-list'),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (final (i, f) in report.fields.indexed) ...[
                  if (i > 0) Divider(height: 1, indent: context.look.cardPadding, endIndent: context.look.cardPadding),
                  _FieldRow(field: f, selected: f == selected, onTap: () => select(f)),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(l10n.scatterFrameHint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.scatterBadgeHint, style: Theme.of(context).textTheme.bodySmall),
          if (report.pending.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(_pendingText(l10n, report), key: const Key('scatter-pending'), style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ],
    );
  }
}

String _pendingText(AppLocalizations l10n, ScatterReport report) => l10n.scatterPending([
      for (final p in report.pending.take(6)) '${scatterFieldName(p.field)} (${p.darts}/${ScatterRules.minDarts})',
    ].join(', '));

String directionLabel(AppLocalizations l10n, ScatterDirection d) => switch (d) {
      ScatterDirection.center => l10n.scatterDirCenter,
      ScatterDirection.up => l10n.scatterDirUp,
      ScatterDirection.upRight => l10n.scatterDirUpRight,
      ScatterDirection.right => l10n.scatterDirRight,
      ScatterDirection.downRight => l10n.scatterDirDownRight,
      ScatterDirection.down => l10n.scatterDirDown,
      ScatterDirection.downLeft => l10n.scatterDirDownLeft,
      ScatterDirection.left => l10n.scatterDirLeft,
      ScatterDirection.upLeft => l10n.scatterDirUpLeft,
    };

/// „eher links unten“ bzw. „mittig“.
String tendencyLabel(AppLocalizations l10n, ScatterDirection d) =>
    d == ScatterDirection.center ? l10n.scatterDirCenter : l10n.scatterTendency(directionLabel(l10n, d));

String tipText(AppLocalizations l10n, ScatterTip tip) => switch (tip.kind) {
      ScatterTipKind.steady => l10n.scatterTipSteady,
      ScatterTipKind.shiftAim => l10n.scatterTipShiftAim,
      ScatterTipKind.tighten => l10n.scatterTipTighten,
      ScatterTipKind.tooFlat => l10n.scatterTipTooFlat,
      ScatterTipKind.tooSteep => l10n.scatterTipTooSteep,
      ScatterTipKind.inside => l10n.scatterTipInside,
      ScatterTipKind.outside => l10n.scatterTipOutside,
      ScatterTipKind.drift => tip.toward != null
          ? l10n.scatterTipDrift(tip.toward!)
          : l10n.scatterTipDriftSide(tip.right ? l10n.scatterDirRight : l10n.scatterDirLeft),
      ScatterTipKind.wideSideways => l10n.scatterTipWideSideways,
      ScatterTipKind.wideHeight => l10n.scatterTipWideHeight,
      ScatterTipKind.wideOverall => l10n.scatterTipWideOverall,
    };

/// „3 mm links (Richtung 12) · 6 mm unten“: die beiden Anteile der
/// Abweichung, kleine Anteile (unter 1 mm) entfallen.
String offsetDetail(AppLocalizations l10n, FieldScatter f) {
  final o = f.offset;
  final parts = <String>[];
  if (o.t.abs() >= 0.5) {
    final right = o.t > 0;
    final side = right ? l10n.scatterDirRight : l10n.scatterDirLeft;
    final n = neighbourOf(f.field, right: right);
    parts.add(n == null ? l10n.scatterSidePlain(_mm(o.t), side) : l10n.scatterSideToward(_mm(o.t), side, n));
  }
  if (o.r.abs() >= 0.5) parts.add(l10n.scatterHeight(_mm(o.r), o.r > 0 ? l10n.scatterDirUp : l10n.scatterDirDown));
  return parts.isEmpty ? l10n.scatterDirCenter : parts.join(' · ');
}

class _ScopeChips extends ConsumerWidget {
  const _ScopeChips({required this.scope});
  final ScatterScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    String label(ScatterScope s) => switch (s) {
          ScatterScope.all => l10n.scatterScopeAll,
          ScatterScope.training => l10n.scatterScopeTraining,
          ScatterScope.match => l10n.scatterScopeMatch,
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            for (final s in ScatterScope.values)
              ChoiceChip(
                key: Key('scatter-scope-${s.name}'),
                label: Text(label(s)),
                selected: s == scope,
                onSelected: (_) => ref.read(scatterScopeProvider.notifier).set(s),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.scatterScopeHint, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.report});
  final ScatterReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = [
      l10n.scatterEmptyText(ScatterRules.minDarts),
      l10n.scatterEmptyCount(report.positioned),
      if (report.pending.isNotEmpty) _pendingText(l10n, report),
    ].join('\n\n');
    return ComingSoon(
      key: const Key('scatter-empty'),
      icon: Icons.track_changes_rounded,
      title: l10n.scatterEmptyTitle,
      text: text,
    );
  }
}

/// Kennzahlen oben: Tendenz, mittlere Streuung, Felder, Darts.
class _Overview extends StatelessWidget {
  const _Overview({required this.report});
  final ScatterReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final o = report.overall!;
    final dir = o.direction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TileGrid(children: [
          StatTile(
            key: const Key('scatter-overall'),
            label: l10n.scatterOverall,
            value: dir == ScatterDirection.center ? l10n.scatterDirCenter : directionLabel(l10n, dir),
            caption: l10n.scatterOverallCaption(_mm(o.offset)),
            icon: Icons.explore_outlined,
          ),
          StatTile(
            label: l10n.scatterSpread,
            value: l10n.scatterSpreadValue(_mm(o.sigma)),
            caption: l10n.scatterSpreadCaption,
            icon: Icons.blur_circular_rounded,
          ),
          StatTile(
            label: l10n.scatterFields,
            value: '${report.fields.length}',
            caption: l10n.scatterFieldsCaption(ScatterRules.minDarts),
            icon: Icons.grid_view_rounded,
          ),
          StatTile(
            label: l10n.scatterPositioned,
            value: '${report.positioned}',
            caption: l10n.scatterPositionedCaption(report.assigned),
            icon: Icons.my_location_rounded,
          ),
        ]),
        const SizedBox(height: AppSpacing.s),
        Text(
          dir == ScatterDirection.center
              ? l10n.scatterOverallCentered
              : l10n.scatterOverallText(directionLabel(l10n, dir), _mm(o.offset)),
          key: const Key('scatter-overall-text'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// Ganze Scheibe mit Ellipse und mittlerer Abweichung je Feld.
class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.report, required this.selected});
  final ScatterReport report;
  final FieldScatter selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ChartCard(
      key: const Key('scatter-board'),
      title: l10n.scatterBoardTitle,
      hint: l10n.scatterBoardHint,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: AspectRatio(
            aspectRatio: 1,
            child: DartboardView(
              key: const Key('scatter-board-view'),
              semanticsLabel: l10n.scatterBoardTitle,
              decoration: ScatterDecoration(report.fields, selected: selected.field),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ausschnitt um das gewählte Feld mit den Darts, dazu Zahlen und Tipps.
class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.report, required this.field, required this.onSelect});
  final ScatterReport report;
  final FieldScatter field;
  final void Function(FieldScatter) onSelect;

  static final Expando<List<ScatterMarker>> _markers = Expando();

  static List<ScatterMarker> markersOf(FieldScatter f) => _markers[f] ??= [
        for (final d in f.points.skip(math.max(0, f.points.length - _maxFocusPoints))) ScatterMarker(d.position, hit: d.hit),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final f = field;
    final focus = f.field.isBull ? Segment.bull : f.field;
    return ChartCard(
      key: const Key('scatter-focus'),
      title: l10n.scatterFocusTitle,
      hint: f.field.isBull ? l10n.scatterFocusHintBull(_maxFocusPoints) : l10n.scatterFocusHint(_maxFocusPoints),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, x) in report.fields.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs + 2),
                  ChoiceChip(
                    key: Key('scatter-chip-${x.field.name}'),
                    label: Text(scatterFieldName(x.field)),
                    selected: x == f,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) => onSelect(x),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: look.gridGap),
          ClipRRect(
            borderRadius: BorderRadius.circular(look.radiusM),
            child: ColoredBox(
              color: colors.boardSurround,
              child: DartboardView(
                key: const Key('scatter-focus-view'),
                semanticsLabel: l10n.scatterFocusTitle,
                focus: focus,
                focusWidth: f.field.isDouble ? 1.05 : (f.field.isBull ? 0.75 : 0.95),
                aspectRatio: 1.45,
                scatter: markersOf(f),
                decoration: ScatterDecoration([f], selected: f.field, focus: true),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.m,
            runSpacing: AppSpacing.xs,
            children: [
              LegendItem(color: colors.success, label: l10n.scatterLegendHit),
              LegendItem(color: const Color(0xFFB4B9C0), label: l10n.scatterLegendMiss),
            ],
          ),
          SizedBox(height: look.gridGap),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${scatterFieldName(f.field)}: ${tendencyLabel(l10n, f.direction)}',
                  key: const Key('scatter-focus-summary'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              _AimBadge(exact: f.exact),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(offsetDetail(l10n, f), style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(_facts(l10n, f), style: theme.textTheme.bodySmall),
          SizedBox(height: look.gridGap),
          Kicker(l10n.scatterTipsTitle),
          const SizedBox(height: AppSpacing.xs),
          for (final t in f.tips) ...[
            _TipLine(text: tipText(l10n, t)),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

String _facts(AppLocalizations l10n, FieldScatter f) => [
      l10n.scatterSpreadDetail(_mm(f.sdT), _mm(f.sdR)),
      f.field.isBull ? l10n.scatterBullRate(wholePercent(f.hits.rate)) : l10n.scatterHitRate(wholePercent(f.hits.rate)),
      l10n.scatterDarts(f.darts),
    ].join(' · ');

class _TipLine extends StatelessWidget {
  const _TipLine({required this.text, this.compact = false});
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.lightbulb_outline_rounded, size: compact ? 16 : 18, color: colors.highlight),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(child: Text(text, style: compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)),
      ],
    );
  }
}

/// Kleines Schild „exakt“ / „geschätzt“.
class _AimBadge extends StatelessWidget {
  const _AimBadge({required this.exact});
  final bool exact;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final colors = context.dartColors;
    final color = exact ? colors.success : colors.warning;
    final label = exact ? context.l10n.scatterExact : context.l10n.scatterEstimated;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(look.id == DartLookId.clean ? AppRadii.pill : look.radiusS),
        border: look.id == DartLookId.lab ? Border.all(color: color.withValues(alpha: 0.45)) : null,
      ),
      child: Text(
        look.caps(label),
        style: (look.id == DartLookId.tv ? look.kicker : Theme.of(context).textTheme.labelSmall)?.copyWith(color: color),
      ),
    );
  }
}

/// Eine Zeile der Feldliste.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field, required this.selected, required this.onTap});
  final FieldScatter field;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final look = context.look;
    final f = field;
    final accent = segmentColor(context, f.field);
    final tips = f.tips;
    return InkWell(
      key: Key('scatter-row-${f.field.name}'),
      onTap: onTap,
      child: Container(
        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.07) : null,
        padding: EdgeInsets.symmetric(horizontal: look.cardPadding, vertical: AppSpacing.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(look.radiusS),
                border: selected ? Border.all(color: accent, width: 1.5) : null,
              ),
              child: Text(scatterFieldName(f.field), style: look.chipNumber.copyWith(color: accent, fontSize: 18)),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.scatterRowTitle(tendencyLabel(l10n, f.direction), _mm(f.shape.offset)),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      _AimBadge(exact: f.exact),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(offsetDetail(l10n, f), style: theme.textTheme.bodySmall),
                  Text(_facts(l10n, f), style: theme.textTheme.bodySmall),
                  if (tips.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _TipLine(text: tipText(l10n, tips.first), compact: true),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ellipse (1 Sigma), Feldmittelpunkt und mittlere Abweichung je Feld, in
/// Board-Koordinaten über der Scheibe. Ruhend: wird nur neu gezeichnet, wenn
/// sich Felder oder Auswahl ändern.
class ScatterDecoration extends BoardDecoration {
  const ScatterDecoration(this.fields, {required this.selected, this.focus = false});
  final List<FieldScatter> fields;
  final Segment? selected;

  /// Ausschnitt eines Felds: kräftiger, ohne die anderen Felder.
  final bool focus;

  @override
  void paint(Canvas canvas, Offset Function(BoardPoint p) toCanvas, double ringRadius, double markerScale) {
    final ordered = [
      for (final f in fields)
        if (f.field != selected) f,
      for (final f in fields)
        if (f.field == selected) f,
    ];
    final s = focus ? 1.0 : 0.8;
    for (final f in ordered) {
      final active = f.field == selected;
      final color = active ? _boardAccent : _boardInk;
      final e = f.ellipse;
      final c = toCanvas(f.mean);
      final rect = Rect.fromCenter(center: Offset.zero, width: 2 * e.major * ringRadius, height: 2 * e.minor * ringRadius);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-e.angle);
      final oval = Path()..addOval(rect);
      canvas.drawPath(oval, Paint()..color = color.withValues(alpha: active ? (focus ? 0.12 : 0.24) : 0.14));
      final outline = f.exact ? oval : _dashed(oval, 7 * s, 5 * s);
      canvas.drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (active ? 4.2 : 3.2) * s
          ..color = Colors.black.withValues(alpha: 0.45),
      );
      canvas.drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (active ? 2.4 : 1.6) * s
          ..color = color,
      );
      canvas.restore();

      // Feldmittelpunkt (Kreuz), Linie zur mittleren Position, Punkt.
      final aim = toCanvas(f.center);
      final arm = 5.0 * s * (focus ? 1.4 : 1);
      for (final (w, col) in [(3.4 * s, Colors.black.withValues(alpha: 0.55)), (1.6 * s, _boardInk)]) {
        final p = Paint()
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = col;
        canvas.drawLine(aim - Offset(arm, arm), aim + Offset(arm, arm), p);
        canvas.drawLine(aim - Offset(arm, -arm), aim + Offset(arm, -arm), p);
      }
      if ((c - aim).distance > 1.5) {
        canvas.drawLine(
          aim,
          c,
          Paint()
            ..strokeWidth = 3.6 * s
            ..strokeCap = StrokeCap.round
            ..color = Colors.black.withValues(alpha: 0.5),
        );
        canvas.drawLine(
          aim,
          c,
          Paint()
            ..strokeWidth = 2 * s
            ..strokeCap = StrokeCap.round
            ..color = color,
        );
      }
      final dot = (focus ? 5.5 : 3.6) * s;
      canvas.drawCircle(c, dot + 1.2, Paint()..color = Colors.black.withValues(alpha: 0.6));
      canvas.drawCircle(c, dot, Paint()..color = color);
    }
  }

  static Path _dashed(Path source, double dash, double gap) {
    final out = Path();
    for (final ui.PathMetric m in source.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash + gap) {
        out.addPath(m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is ScatterDecoration &&
      other.selected == selected &&
      other.focus == focus &&
      other.fields.length == fields.length &&
      _sameFields(other.fields);

  bool _sameFields(List<FieldScatter> other) {
    for (var i = 0; i < fields.length; i++) {
      if (!identical(other[i], fields[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(selected, focus, fields.length);
}
