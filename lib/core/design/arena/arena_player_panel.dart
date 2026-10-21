import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../features/matches/domain/visit_history.dart';
import '../../l10n.dart';
import '../app_theme.dart';
import 'arena_palette.dart';

/// Größenvariante einer Spielertafel. Jede ist in „Vorlagen-Einheiten“
/// entworfen und wird auf die tatsächliche Fläche skaliert: so bleiben die
/// Verhältnisse (oberer Block etwa 43 % der Höhe, Tabelle darunter) auf jedem
/// Bildschirm gleich und nichts läuft über.
enum ArenaPanelStyle {
  /// Breit: eine Tafel pro Seite, Vorlagenmaß 526 × 877.
  full(refWidth: 526, refHeight: 877, refUpper: 380, statsSize: 42),

  /// Telefon: schmale Tafeln nebeneinander, Vorlagenbreite 376.
  compact(refWidth: 376, refHeight: 620, refUpper: 312, statsSize: 33),

  /// Breit mit drei oder mehr Spielern: Tafeln übereinander.
  mini(refWidth: 526, refHeight: 440, refUpper: 292, statsSize: 38);

  const ArenaPanelStyle({
    required this.refWidth,
    required this.refHeight,
    required this.refUpper,
    required this.statsSize,
  });

  final double refWidth;
  final double refHeight;

  /// Höhe des oberen Blocks (Name, Stand, Kennzahlen) in Vorlagen-Einheiten.
  final double refUpper;
  final double statsSize;
}

/// Zeile der einfachen Tabelle (Punkte | Wert), z. B. im Live-Modus ohne X01:
/// Punkte der Aufnahme und laufender Schnitt.
@immutable
class ArenaScoreRow {
  const ArenaScoreRow({required this.visit, required this.points, required this.value});

  /// Nummer der Aufnahme (für den Schlüssel `<prefix>-row-<n>`).
  final int visit;
  final int points;

  /// Rechte Spalte, fertig formatiert.
  final String value;
}

/// Alles, was eine Spielertafel anzeigt. Die Tafel selbst kennt weder Match
/// noch Training: Match und Solo-X01 füllen dasselbe Modell.
@immutable
class ArenaPlayer {
  const ArenaPlayer({
    required this.name,
    required this.remaining,
    required this.rows,
    required this.startScore,
    this.isBot = false,
    this.active = false,
    this.won = false,
    this.starter = false,
    this.lastVisit = 0,
    this.legAverage = '–',
    this.matchAverage = '–',
    this.legDarts = 0,
    this.legs,
    this.sets,
    this.panelKey,
    this.remainingKey,
    this.dartsKey,
    this.legsKey,
    this.setsKey,
    this.keyPrefix = 'visits',
    this.heroText,
    this.caption,
    this.scoreRows,
    this.scoreHeaders,
    this.stats,
    this.legsText,
    this.dartsLabel,
  });

  final String name;
  final int remaining;

  /// Aufnahmen des laufenden Legs, die älteste zuerst (`VisitHistory.legRowsOf`).
  final List<VisitRow> rows;
  final int startScore;
  final bool isBot;

  /// Am Zug (Verlauf Violett → Rot-Rosa).
  final bool active;
  final bool won;

  /// Hat das Leg begonnen (weißer Punkt vor dem Namen).
  final bool starter;

  /// Punkte der letzten abgeschlossenen Aufnahme (Schild neben dem Stand).
  final int lastVisit;
  final String legAverage;
  final String matchAverage;
  final int legDarts;

  /// Gewonnene Legs / Sätze; `null` blendet die Angabe aus.
  final int? legs;
  final int? sets;
  final Key? panelKey;
  final Key? remainingKey;
  final Key? dartsKey;
  final Key? legsKey;
  final Key? setsKey;

  /// Präfix der Zeilen-Schlüssel (`<prefix>-row-<n>`, `<prefix>-start`).
  final String keyPrefix;

  /// Statt des Rests die große Zahl selbst bestimmen (z. B. der Schnitt, wenn
  /// es keinen Rest gibt).
  final String? heroText;

  /// Kleine Zeile über der großen Zahl (erklärt [heroText]).
  final String? caption;

  /// Einfache Tabelle (Punkte | Wert) statt der Tabelle mit Rest und
  /// Startzeile; [scoreHeaders] beschriftet die beiden Spalten.
  final List<ArenaScoreRow>? scoreRows;
  final (String, String)? scoreHeaders;

  /// Kennzahlen statt „Leg Ø / Match Ø“: Paare aus Name und Wert.
  final List<(String, String)>? stats;

  /// Legs als Text (z. B. „2 : 1“) statt der Zahl [legs].
  final String? legsText;

  /// Beschriftung des Dart-Symbols (Standard: „Darts im Leg“).
  final String? dartsLabel;
}

TextStyle _text(double size, {FontWeight weight = FontWeight.w500, Color color = ArenaPalette.text, double? spacing, double height = 1.1}) {
  return TextStyle(
    fontFamily: AppTypography.family,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: spacing,
    height: height,
    fontFeatures: AppTypography.tabular,
  );
}

/// Eine Spielertafel: oben Name, Stand, Schnitt und Darts, darunter die
/// Tabelle der Aufnahmen (links Punkte, rechts Rest).
class ArenaPlayerPanel extends StatelessWidget {
  const ArenaPlayerPanel({super.key, required this.player, this.style = ArenaPanelStyle.full});
  final ArenaPlayer player;
  final ArenaPanelStyle style;

  @override
  Widget build(BuildContext context) {
    final p = player;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : style.refWidth;
        final h = c.maxHeight.isFinite ? c.maxHeight : style.refHeight;
        final s = math.min(w / style.refWidth, h / style.refHeight);
        final upperH = math.min(style.refUpper * s, h * 0.7);
        final radius = (28 * s).clamp(8.0, 28.0);
        final lit = p.active || p.won;
        return KeyedSubtree(
          key: p.panelKey,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: ArenaPalette.surface),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: upperH,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: lit ? null : ArenaPalette.surfaceFlat,
                        gradient: lit
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: p.won
                                    ? const [ArenaPalette.wonStart, ArenaPalette.wonMid, ArenaPalette.wonEnd]
                                    : const [ArenaPalette.gradientStart, ArenaPalette.gradientMid, ArenaPalette.gradientEnd],
                              )
                            : null,
                      ),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(width: style.refWidth, height: style.refUpper, child: _Upper(player: p, style: style, lit: lit)),
                      ),
                    ),
                  ),
                  Container(height: 1, color: ArenaPalette.separator),
                  Expanded(child: ArenaVisitTable(player: p, scale: s)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Upper extends StatelessWidget {
  const _Upper({required this.player, required this.style, required this.lit});
  final ArenaPlayer player;
  final ArenaPanelStyle style;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final l10n = context.l10n;
    final inactive = lit ? 1.0 : 0.7;
    final compact = style == ArenaPanelStyle.compact;
    final scoreSize = switch (style) {
      ArenaPanelStyle.full => 138.0,
      ArenaPanelStyle.mini => 114.0,
      ArenaPanelStyle.compact => 124.0,
    };
    final stats = style.statsSize;
    final rowSize = compact ? 30.0 : 34.0;

    Widget number(String label, int value, {Key? key}) => Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label ', style: _text(rowSize - 4, weight: FontWeight.w400, color: ArenaPalette.text.withValues(alpha: 0.8))),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Text('$value', key: key, style: _text(rowSize, weight: FontWeight.w800)),
          ),
        ],
      ),
      maxLines: 1,
    );

    final legsRow = <Widget>[
      if (p.sets != null) ...[number(l10n.arenaSetsWon, p.sets!, key: p.setsKey), const SizedBox(width: 22)],
      if (p.legsText != null)
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${l10n.arenaLegsWon} ', style: _text(rowSize - 4, weight: FontWeight.w400, color: ArenaPalette.text.withValues(alpha: 0.8))),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Text(p.legsText!, key: p.legsKey, style: _text(rowSize, weight: FontWeight.w800)),
              ),
            ],
          ),
          maxLines: 1,
        )
      else if (p.legs != null)
        number(l10n.arenaLegsWon, p.legs!, key: p.legsKey),
    ];

    // Übersteigt der Inhalt die Vorlagenhöhe, wird er verkleinert statt abgeschnitten.
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 12 : 16, 16, 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: style.refWidth - 32,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
          _NameRow(player: p, size: compact ? 28 : 30, maxWidth: style.refWidth - 32),
          SizedBox(height: compact ? 2 : 6),
          if (p.caption != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                p.caption!,
                maxLines: 1,
                style: _text(stats * 0.8, weight: FontWeight.w500, color: ArenaPalette.text.withValues(alpha: 0.8)),
              ),
            ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  p.heroText ?? '${p.remaining}',
                  key: p.remainingKey,
                  softWrap: false,
                  maxLines: 1,
                  style: _text(scoreSize, weight: FontWeight.w800, spacing: -4, height: 1.05, color: ArenaPalette.text.withValues(alpha: inactive)),
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(color: ArenaPalette.badge, borderRadius: BorderRadius.circular(10)),
                  child: Text('${p.lastVisit}', key: Key('${p.keyPrefix}-last'), style: _text(compact ? 34 : 38, weight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 0 : 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                children: p.stats != null
                    ? [
                        for (final (i, (label, value)) in p.stats!.indexed) ...[
                          TextSpan(text: '${i == 0 ? '' : ' / '}$label ', style: _text(stats, weight: FontWeight.w400)),
                          TextSpan(text: value, style: _text(stats, weight: FontWeight.w800)),
                        ],
                      ]
                    : [
                        TextSpan(text: '${l10n.arenaLegAvg} ', style: _text(stats, weight: FontWeight.w400)),
                        TextSpan(text: p.legAverage, style: _text(stats, weight: FontWeight.w800)),
                        TextSpan(text: ' / ${l10n.arenaMatchAvg} ', style: _text(stats, weight: FontWeight.w400)),
                        TextSpan(text: p.matchAverage, style: _text(stats, weight: FontWeight.w800)),
                      ],
              ),
              maxLines: 1,
            ),
          ),
          SizedBox(height: compact ? 2 : 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: p.dartsLabel ?? l10n.arenaDartsThrown,
                  child: CustomPaint(size: Size(rowSize * 1.1, rowSize * 0.8), painter: ArenaDartIconPainter(ArenaPalette.text.withValues(alpha: 0.9))),
                ),
                const SizedBox(width: 8),
                Text('${p.legDarts}', key: p.dartsKey, style: _text(rowSize, weight: FontWeight.w800)),
                if (legsRow.isNotEmpty) const SizedBox(width: 28),
                ...legsRow,
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

class _NameRow extends StatelessWidget {
  const _NameRow({required this.player, required this.size, required this.maxWidth});
  final ArenaPlayer player;
  final double size;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final avatar = size * 1.9;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.starter) ...[
            Container(width: 14, height: 14, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: SizedBox(
              height: avatar,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: avatar * 0.62),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(avatar * 0.5, 4, 18, 4),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (p.won) ...[
                            const Icon(Icons.emoji_events_rounded, size: 28, color: ArenaPalette.record),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTypography.condensed,
                                fontSize: size,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.4,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: avatar,
                    height: avatar,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ArenaPalette.chip,
                      border: Border.all(color: Colors.black, width: 3),
                    ),
                    child: Icon(p.isBot ? Icons.smart_toy_outlined : Icons.person_rounded, size: avatar * 0.58, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tabelle der Aufnahmen: links die Punkte, rechts der Rest nach der
/// Aufnahme. Die erste Zeile ist der Startwert, danach folgt jede Aufnahme des
/// laufenden Legs; die neueste steht unten und trägt die helle Fläche. Passen
/// nicht alle Zeilen, fallen die ältesten oben heraus.
class ArenaVisitTable extends StatelessWidget {
  const ArenaVisitTable({super.key, required this.player, required this.scale});
  final ArenaPlayer player;

  /// Skalierung gegenüber dem Vorlagenmaß (Zeile 52, Schrift 28).
  final double scale;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final s = scale;
    final rowH = (52 * s).clamp(18.0, 60.0);
    final fontSize = (28 * s).clamp(11.0, 30.0);
    final padTop = 10 * s;
    final plain = p.scoreRows;
    final headers = p.scoreHeaders;
    final headerH = plain != null && headers != null ? rowH * 0.8 : 0.0;
    return Stack(
      children: [
        // Senkrechte Trennlinie in der Mitte.
        Positioned.fill(
          child: Center(child: FractionallySizedBox(heightFactor: 1, child: Container(width: 1, color: ArenaPalette.separator))),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final count = math.max(1, ((c.maxHeight - padTop - headerH) / rowH).floor());
            if (plain != null) {
              final shown = plain.length > count ? plain.sublist(plain.length - count) : plain;
              return ClipRect(
                child: Padding(
                  padding: EdgeInsets.only(top: padTop),
                  child: Column(
                    children: [
                      if (headers != null)
                        SizedBox(
                          height: headerH,
                          child: Row(
                            children: [
                              for (final h in [headers.$1, headers.$2])
                                Expanded(
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(h, maxLines: 1, style: _text(math.max(9, fontSize * 0.55), weight: FontWeight.w600, color: ArenaPalette.textMuted, spacing: 0.6)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      for (final (i, row) in shown.indexed)
                        SizedBox(
                          height: rowH,
                          child: _PlainLine(
                            key: Key('${p.keyPrefix}-row-${row.visit}'),
                            row: row,
                            latest: i == shown.length - 1,
                            fontSize: fontSize,
                            scale: s,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }
            final items = <VisitRow?>[null, ...p.rows];
            final shown = items.length > count ? items.sublist(items.length - count) : items;
            return ClipRect(
              child: Padding(
                padding: EdgeInsets.only(top: padTop),
                child: Column(
                  children: [
                    for (final (i, row) in shown.indexed)
                      SizedBox(
                        height: rowH,
                        child: _Line(
                          key: row == null ? Key('${p.keyPrefix}-start') : Key('${p.keyPrefix}-row-${row.visit}'),
                          row: row,
                          startScore: p.startScore,
                          latest: i == shown.length - 1,
                          fontSize: fontSize,
                          scale: s,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Zeile der einfachen Tabelle: Punkte links, Wert rechts, die neueste mit
/// hellem Schild.
class _PlainLine extends StatelessWidget {
  const _PlainLine({super.key, required this.row, required this.latest, required this.fontSize, required this.scale});
  final ArenaScoreRow row;
  final bool latest;
  final double fontSize;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final value = Text(
      r.value,
      maxLines: 1,
      softWrap: false,
      style: _text(fontSize, weight: FontWeight.w700, color: latest ? ArenaPalette.onLight : ArenaPalette.text.withValues(alpha: 0.8)),
    );
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${r.points}, ${r.value}',
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${r.points}',
                  maxLines: 1,
                  softWrap: false,
                  style: _text(
                    fontSize,
                    weight: latest || r.points >= 100 ? FontWeight.w700 : FontWeight.w500,
                    color: r.points >= 100 ? ArenaPalette.record : ArenaPalette.text,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: latest
                    ? Container(
                        padding: EdgeInsets.symmetric(horizontal: 12 * scale.clamp(0.5, 1.0), vertical: 2 * scale),
                        decoration: BoxDecoration(color: ArenaPalette.light, borderRadius: BorderRadius.circular(math.max(4, 6 * scale))),
                        child: value,
                      )
                    : value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({super.key, required this.row, required this.startScore, required this.latest, required this.fontSize, required this.scale});
  final VisitRow? row;
  final int startScore;
  final bool latest;
  final double fontSize;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final l10n = context.l10n;
    final bust = r?.bust ?? false;
    final checkout = r?.checkout ?? false;
    final remaining = r?.remaining ?? startScore;

    Color pointsColor() {
      if (bust) return ArenaPalette.danger;
      if (checkout) return ArenaPalette.success;
      if (r != null && r.points >= 100) return ArenaPalette.record;
      return ArenaPalette.text;
    }

    final chipBg = checkout ? ArenaPalette.success : ArenaPalette.light;
    final Widget restText = Text(
      '$remaining',
      maxLines: 1,
      softWrap: false,
      style: _text(fontSize, weight: FontWeight.w700, color: latest ? ArenaPalette.onLight : ArenaPalette.text.withValues(alpha: r == null ? 0.55 : 0.8)),
    );
    final Widget rest = latest
        ? Container(
            padding: EdgeInsets.symmetric(horizontal: 12 * scale.clamp(0.5, 1.0), vertical: 2 * scale),
            decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(math.max(4, 6 * scale))),
            child: restText,
          )
        : restText;

    final Widget points = r == null
        ? const SizedBox.shrink()
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (checkout) ...[Icon(Icons.emoji_events_rounded, size: fontSize * 0.9, color: ArenaPalette.success), const SizedBox(width: 4)],
              Text(
                '${r.points}',
                maxLines: 1,
                softWrap: false,
                style: _text(fontSize, weight: latest || r.points >= 100 || bust || checkout ? FontWeight.w700 : FontWeight.w500, color: pointsColor()),
              ),
              if (bust) ...[
                const SizedBox(width: 5),
                Text(
                  l10n.arenaBust.toUpperCase(),
                  key: Key('visit-bust-${r.visit}'),
                  style: _text(math.max(8, fontSize * 0.5), weight: FontWeight.w800, color: ArenaPalette.danger, spacing: 0.6),
                ),
              ],
            ],
          );

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: r == null
          ? l10n.visitTableRowStart(startScore)
          : bust
          ? l10n.visitTableRowBust(remaining)
          : l10n.visitTableRowSemantics(r.points, remaining),
      child: Row(
        children: [
          Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: points))),
          Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: rest))),
        ],
      ),
    );
  }
}

/// Kleines Dart-Symbol: Spitze links, Schaft, Flügel rechts.
class ArenaDartIconPainter extends CustomPainter {
  const ArenaDartIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cy = h / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // Spitze und Barrel.
    canvas.drawOval(Rect.fromLTWH(0, cy - h * 0.22, w * 0.30, h * 0.44), paint);
    // Schaft.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.26, cy - h * 0.05, w * 0.55, h * 0.10), Radius.circular(h * 0.05)),
      paint,
    );
    // Flügel.
    final flight = Path()
      ..moveTo(w * 0.78, cy)
      ..lineTo(w, cy - h * 0.32)
      ..lineTo(w, cy + h * 0.32)
      ..close();
    canvas.drawPath(flight, paint..color = color.withValues(alpha: 0.75));
  }

  @override
  bool shouldRepaint(covariant ArenaDartIconPainter old) => old.color != color;
}
