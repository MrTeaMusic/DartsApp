import 'package:flutter/material.dart';

import '../../../features/matches/domain/visit_history.dart';
import '../../l10n.dart';
import '../dart_colors.dart';
import '../dart_look.dart';
import 'components.dart';

/// Kleine Tabelle der letzten Aufnahmen eines Spielers im laufenden Leg:
/// links die Punkte der Aufnahme, rechts der Rest danach. Die neueste
/// Aufnahme steht oben und ist hervorgehoben, ganz unten (sobald alle
/// Aufnahmen Platz haben) der Startwert.
///
/// * Bust: die Punkte stehen als rote 0 mit „Bust“-Marke.
/// * Checkout: die Zeile ist grün, der Rest 0 trägt ein Häkchen.
/// * Aufnahmen ab 100 Punkten stehen in der Akzentfarbe.
///
/// Die Höhe ist fest (Kopfzeile + [maxRows] Zeilen), damit die Ansicht nicht
/// springt, wenn Aufnahmen dazukommen; ältere Aufnahmen fallen unten heraus.
/// Aussehen je Look: TV flach mit Farbbalken, Clean mit runden Flächen, Lab
/// mit feinen Linien.
class VisitTable extends StatelessWidget {
  const VisitTable({
    super.key,
    required this.rows,
    required this.startScore,
    this.maxRows = 5,
    this.active = true,
    this.showDarts = false,
    this.dense = false,
    this.keyPrefix = 'visits',
  });

  /// Aufnahmen des Legs, die älteste zuerst (`VisitHistory.legRowsOf`).
  final List<VisitRow> rows;
  final int startScore;

  /// Sichtbare Zeilen inklusive der Startzeile.
  final int maxRows;

  /// Der Spieler ist am Zug: die neueste Zeile trägt die Akzentfarbe, sonst
  /// eine zurückhaltende Tönung.
  final bool active;

  /// Mittlere Spalte mit den einzelnen Darts („T20 · 5 · 1“), z. B. im Solo.
  final bool showDarts;

  /// Sehr schmale Tabelle (drei oder mehr Spieler auf dem Telefon): die
  /// „Bust“-Marke entfällt, die rote 0 und die rote Zeile bleiben.
  final bool dense;

  /// Präfix der Schlüssel: `<prefix>`, `<prefix>-row-<Aufnahme>`,
  /// `<prefix>-start`.
  final String keyPrefix;

  static double rowHeight(DartLook look) => switch (look.id) {
    DartLookId.tv => 22,
    DartLookId.clean => 25,
    DartLookId.lab => 22,
  };

  static const double _headerHeight = 18;

  /// Gesamthöhe, damit Umgebungen sie vorab einplanen können.
  static double heightFor(DartLook look, int maxRows) => _headerHeight + rowHeight(look) * maxRows;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final l10n = context.l10n;
    final h = rowHeight(look);

    // Neueste zuerst, am Ende die Startzeile; was nicht passt, fällt unten heraus.
    final entries = <Object>[...rows.reversed, #start].take(maxRows).toList();

    return SizedBox(
      key: Key(keyPrefix),
      height: heightFor(look, maxRows),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _headerHeight,
            child: Padding(
              padding: _rowPadding(look, dense: dense),
              child: Row(
                children: [
                  Expanded(child: _headerText(context, l10n.visitTablePoints, TextAlign.start)),
                  if (showDarts) Expanded(flex: 2, child: _headerText(context, l10n.visitTableDarts, TextAlign.center)),
                  Expanded(child: _headerText(context, l10n.visitTableRest, TextAlign.end)),
                ],
              ),
            ),
          ),
          for (var i = 0; i < entries.length; i++)
            SizedBox(
              height: h,
              child: entries[i] is VisitRow
                  ? _VisitLine(
                      key: Key('$keyPrefix-row-${(entries[i] as VisitRow).visit}'),
                      row: entries[i] as VisitRow,
                      latest: i == 0,
                      active: active,
                      showDarts: showDarts,
                      dense: dense,
                    )
                  : _StartLine(key: Key('$keyPrefix-start'), score: startScore, showDarts: showDarts, dense: dense),
            ),
          // Freie Plätze bleiben leer, die Höhe der Tabelle ändert sich nicht.
          const Spacer(),
        ],
      ),
    );
  }

  /// Abstand links und rechts in den Zeilen; schmale Tabellen brauchen weniger.
  static EdgeInsets _rowPadding(DartLook look, {bool dense = false}) =>
      EdgeInsets.symmetric(horizontal: dense ? 4 : (look.id == DartLookId.clean ? 8 : 6));

  Widget _headerText(BuildContext context, String text, TextAlign align) {
    final look = context.look;
    final size = switch (look.id) {
      DartLookId.tv => 13.0,
      DartLookId.clean => 11.0,
      DartLookId.lab => 9.5,
    };
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: switch (align) {
        TextAlign.end => Alignment.centerRight,
        TextAlign.center => Alignment.center,
        _ => Alignment.centerLeft,
      },
      child: Text(
        look.caps(text),
        maxLines: 1,
        style: look.kicker.copyWith(fontSize: size, color: context.dartColors.textMuted),
      ),
    );
  }
}

/// Zahlenstil der Tabelle im aktuellen Look.
TextStyle _numberStyle(DartLook look) => look.chipNumber.copyWith(
  fontSize: switch (look.id) {
    DartLookId.tv => 18,
    DartLookId.clean => 14.5,
    DartLookId.lab => 13.5,
  },
);

/// Rahmen einer hervorgehobenen Zeile: TV und Lab mit Farbbalken links, Clean
/// als runde Fläche.
Decoration _lineDecoration(DartLook look, Color tint, Color bar, {required bool hairline, required Color line}) {
  switch (look.id) {
    case DartLookId.tv:
      return BoxDecoration(
        color: tint,
        border: Border(left: BorderSide(color: bar, width: 3)),
      );
    case DartLookId.clean:
      return BoxDecoration(color: tint, borderRadius: BorderRadius.circular(9));
    case DartLookId.lab:
      return BoxDecoration(
        color: tint,
        border: Border(
          left: BorderSide(color: bar, width: 2),
          bottom: hairline ? BorderSide(color: line) : BorderSide.none,
        ),
      );
  }
}

class _VisitLine extends StatelessWidget {
  const _VisitLine({
    super.key,
    required this.row,
    required this.latest,
    required this.active,
    required this.showDarts,
    required this.dense,
  });

  final VisitRow row;
  final bool latest;
  final bool active;
  final bool showDarts;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final l10n = context.l10n;
    final colors = context.dartColors;
    final theme = Theme.of(context);
    final style = _numberStyle(look);

    final Color tint;
    final Color bar;
    if (row.checkout) {
      tint = colors.success.withValues(alpha: 0.16);
      bar = colors.success;
    } else if (row.bust) {
      tint = colors.danger.withValues(alpha: latest ? 0.17 : 0.09);
      bar = colors.danger;
    } else if (latest) {
      // TV: Rot ist dort die Farbe des Spielers am Zug und von Bust, die
      // neueste Zeile bleibt daher neutral (hell).
      final accent = active && look.id != DartLookId.tv ? theme.colorScheme.primary : theme.colorScheme.onSurface;
      tint = accent.withValues(alpha: active ? 0.14 : 0.07);
      bar = active ? accent : colors.textMuted;
    } else {
      tint = Colors.transparent;
      bar = Colors.transparent;
    }

    final Color base = latest || row.checkout ? theme.colorScheme.onSurface : colors.textMuted;
    final Color pointsColor = row.bust
        ? colors.danger
        : row.checkout
        ? colors.success
        : row.points >= 100
        ? colors.record
        : base;

    Widget cell(Widget child, Alignment alignment) =>
        FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child);

    final points = cell(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (row.checkout) ...[Icon(Icons.emoji_events_rounded, size: 13, color: colors.success), const SizedBox(width: 3)],
          Text('${row.points}', style: style.copyWith(color: pointsColor)),
          if (row.bust && !dense) ...[
            const SizedBox(width: 4),
            Text(
              look.caps(l10n.visitTableBust),
              key: Key('visit-bust-${row.visit}'),
              style: look.kicker.copyWith(fontSize: look.id == DartLookId.tv ? 12 : 9.5, color: colors.danger),
            ),
          ],
        ],
      ),
      Alignment.centerLeft,
    );
    final rest = cell(
      Text('${row.remaining}', style: style.copyWith(color: row.checkout ? colors.success : base)),
      Alignment.centerRight,
    );

    final darts = showDarts
        ? Expanded(
            flex: 2,
            child: cell(
              Text.rich(
                TextSpan(
                  children: [
                    for (var i = 0; i < row.darts.length; i++) ...[
                      if (i > 0) TextSpan(text: '  ·  ', style: TextStyle(color: colors.textMuted.withValues(alpha: 0.6))),
                      TextSpan(
                        text: row.darts[i].name,
                        // Ältere Zeilen treten zurück: einfache Felder gedämpft, Double und Triple behalten ihre Farbe.
                        style: TextStyle(
                          color: latest || row.darts[i].isDouble || row.darts[i].isTriple
                              ? segmentColor(context, row.darts[i])
                              : base,
                        ),
                      ),
                    ],
                  ],
                ),
                style: style.copyWith(fontSize: (style.fontSize ?? 14) - 1.5, fontWeight: FontWeight.w600),
                maxLines: 1,
              ),
              Alignment.center,
            ),
          )
        : null;

    return Semantics(
      container: true,
      label: row.bust
          ? l10n.visitTableRowBust(row.remaining)
          : l10n.visitTableRowSemantics(row.points, row.remaining),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: _lineDecoration(look, tint, bar, hairline: true, line: theme.colorScheme.outline.withValues(alpha: 0.6)),
        child: Padding(
          padding: VisitTable._rowPadding(look, dense: dense),
          child: Row(
            children: [
              Expanded(child: points),
              ?darts,
              Expanded(child: rest),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartLine extends StatelessWidget {
  const _StartLine({super.key, required this.score, required this.showDarts, required this.dense});
  final int score;
  final bool showDarts;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final colors = context.dartColors;
    final theme = Theme.of(context);
    final style = _numberStyle(look).copyWith(color: colors.textMuted);
    return Semantics(
      container: true,
      label: context.l10n.visitTableRowStart(score),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: switch (look.id) {
          DartLookId.tv => const BoxDecoration(border: Border(left: BorderSide(color: Colors.transparent, width: 3))),
          DartLookId.clean => const BoxDecoration(),
          DartLookId.lab => BoxDecoration(
            border: Border(
              left: const BorderSide(color: Colors.transparent, width: 2),
              bottom: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.6)),
            ),
          ),
        },
        child: Padding(
          padding: VisitTable._rowPadding(look, dense: dense),
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    look.caps(context.l10n.visitTableStart),
                    style: look.kicker.copyWith(fontSize: look.id == DartLookId.tv ? 13 : 11, color: colors.textMuted),
                  ),
                ),
              ),
              if (showDarts) const Expanded(flex: 2, child: SizedBox.shrink()),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('$score', style: style),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
