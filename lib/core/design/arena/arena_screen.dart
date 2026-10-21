import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'arena_background.dart';
import 'arena_chrome.dart';
import 'arena_palette.dart';
import 'arena_player_panel.dart';

/// Aufbau der Arena-Spielansicht (Match und Solo-X01).
///
/// Breit (Querformat ab etwa 5:4): drei Spalten wie im Vorbild — Tafel links
/// (26 % der Breite), in der Mitte Wurfleiste, Schalterleiste und Board
/// (39 %), Tafel rechts (27 %). Die Tafeln sind rund 68 % so hoch wie der
/// Bildschirm und enden deutlich über dem unteren Rand. Bei drei oder mehr
/// Spielern teilen sich die Seitenspalten die Tafeln, übereinander.
///
/// Hochformat und Telefon: Kopfzeile, Wurfleiste, die Tafeln nebeneinander
/// (je Spieler gleich breit), darunter Board und Schalterleiste.
class ArenaScreen extends StatelessWidget {
  const ArenaScreen({
    super.key,
    required this.players,
    required this.topBar,
    required this.dartSlots,
    required this.visitSum,
    required this.board,
    required this.actions,
    required this.messages,
    this.visitBust = false,
    this.sumKey,
    this.keypad,
    this.result,
    this.header,
    this.zoom,
    this.zoomActive = false,
    this.sidePanel,
  });

  final List<ArenaPlayer> players;

  /// Kopfzeile; bekommt `compact` (Telefon) und die Skalierung.
  final ArenaTopBar Function(bool compact, double scale) topBar;
  final List<ArenaDartSlot> dartSlots;
  final int visitSum;
  final bool visitBust;
  final Key? sumKey;
  final Widget board;

  /// Schalterleiste in der gewünschten Höhe.
  final Widget Function(double height) actions;
  final Widget messages;

  /// Tastenfeld der manuellen Eingabe statt der Schalterleiste.
  final Widget? keypad;

  /// Nach dem Ende: Ergebnis statt Wurfleiste und Board in der Mitte.
  final Widget? result;

  /// Streifen über allem (z. B. die Aufgabe einer Challenge).
  final Widget? header;

  /// Doppel-Zoom: breit unter der rechten Tafel, auf dem Telefon über dem
  /// Board. [zoomActive] sagt, ob er gerade ein Ziel zeigt (Platz auf dem
  /// Telefon wird nur dann reserviert).
  final Widget? zoom;
  final bool zoomActive;

  /// Breit mit nur einem Spieler: füllt die freie rechte Spalte (im
  /// Live-Modus die Kennzahlen der Session). Auf dem Telefon nicht gezeigt.
  final Widget? sidePanel;

  /// Breit = drei Spalten.
  static bool isWide(Size size) => size.width >= 640 && size.width / math.max(1, size.height) >= 1.25;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ArenaPalette.theme,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: ArenaBackground(
          child: Column(
            children: [
              if (header != null)
                Padding(padding: const EdgeInsets.fromLTRB(12, 22, 12, 0), child: header),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => isWide(c.biggest) ? _wide(context, c.biggest) : _narrow(context, c.biggest),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panels(List<ArenaPlayer> list, ArenaPanelStyle style, double gap) {
    return Column(
      children: [
        for (final (i, p) in list.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          Expanded(child: ArenaPlayerPanel(player: p, style: style)),
        ],
      ],
    );
  }

  Widget _wide(BuildContext context, Size size) {
    final w = size.width;
    final h = size.height;
    final t = (h / 900).clamp(0.55, 1.5);
    final margin = w * 0.012;
    final panelW = w * 0.265;
    // Unter der Kopfzeile (Verlassen und Schilder), mindestens 9,8 % der Höhe wie im Vorbild.
    final panelTop = math.max(h * 0.098, h * 0.02 + 4 + 70);
    final panelH = h * 0.687;

    final actionH = (h * 0.05).clamp(30.0, 48.0);
    final top = h * 0.052;
    const gap = 6.0;
    const messagesMin = 46.0;
    // Das Board ist so breit wie die Wurfleiste (39 % der Breite), bei sehr
    // breiten Fenstern begrenzt die Höhe.
    final availH = h - top - actionH - gap * 2 - messagesMin - h * 0.01;
    final b = math.min(w * 0.3925, availH / 1.124);
    final barH = (b * 0.124).clamp(36.0, 120.0);
    final centerLeft = (w - b) / 2;
    final boardTop = top + barH + gap + actionH + gap;
    final stacked = players.length >= 3;
    final left = players.take(players.length ~/ 2).toList();
    final right = players.skip(players.length ~/ 2).toList();
    final single = players.length < 2;
    final style = stacked ? ArenaPanelStyle.mini : ArenaPanelStyle.full;

    Widget column(List<ArenaPlayer> list) => SizedBox(
      width: panelW,
      height: panelH,
      child: list.isEmpty ? const SizedBox.shrink() : _panels(list, style, 10 * t),
    );

    return Stack(
      children: [
        Positioned(
          left: margin,
          top: h * 0.02 + 4,
          right: margin,
          child: topBar(false, t),
        ),
        // Ein Spieler: nur die linke Tafel, die rechte Seite bleibt leer.
        Positioned(left: margin, top: panelTop, child: column(single ? players : left)),
        if (!single) Positioned(right: margin, top: panelTop, child: column(right)),
        if (single && sidePanel != null)
          Positioned(right: margin, top: panelTop, width: panelW, bottom: h * 0.03, child: ClipRRect(borderRadius: BorderRadius.circular(24), child: sidePanel!)),
        // Doppel-Zoom in der freien Fläche unter der rechten Tafel; was nicht
        // passt, wird verkleinert.
        if (zoom != null && result == null)
          Positioned(
            right: margin,
            width: panelW,
            top: panelTop + panelH + 8,
            bottom: h * 0.012,
            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: SizedBox(width: panelW, child: zoom)),
          ),
        if (result != null)
          Positioned(
            left: centerLeft,
            width: b,
            top: top,
            bottom: h * 0.03,
            child: result!,
          )
        else ...[
          Positioned(
            left: centerLeft,
            width: b,
            top: top,
            height: barH,
            child: ArenaDartBar(slots: dartSlots, sum: visitSum, bust: visitBust, sumKey: sumKey, height: barH),
          ),
          Positioned(
            left: centerLeft,
            width: b,
            top: top + barH + gap,
            height: actionH,
            child: Center(child: actions(actionH)),
          ),
          Positioned(left: centerLeft, top: boardTop, width: b, height: b, child: board),
          Positioned(
            left: centerLeft,
            width: b,
            top: boardTop + b + gap,
            bottom: 0,
            child: ClipRect(
              child: keypad == null
                  ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: SizedBox(width: math.max(b, 260), child: messages))
                  : SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [messages, const SizedBox(height: 6), keypad!]),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _narrow(BuildContext context, Size size) {
    final w = size.width;
    final h = size.height;
    const side = 12.0;
    final strip = math.min(26.0, h * 0.02);
    const gap = 8.0;
    final result = this.result;
    final barH = (w * 0.135).clamp(44.0, 64.0);
    const actionH = 44.0;
    const topH = 76.0;
    const messagesH = 62.0;
    final fixed = strip + 2 + topH + barH + actionH + messagesH + gap * 6;
    // Der Doppel-Zoom reserviert nur dann Platz, wenn er ein Ziel zeigt.
    final zoomH = zoom != null && zoomActive && result == null ? math.min((w - side * 2) / 2.4 + 40, 200.0) : 0.0;
    final rest = h - fixed - zoomH;
    final b = math.min(w - side * 2, math.max(rest * 0.47, 210.0));
    final panelsH = math.max(rest - b, 180.0);
    const panelStyle = ArenaPanelStyle.compact;
    final total = fixed + zoomH + b + panelsH;

    Widget content = Padding(
      padding: EdgeInsets.fromLTRB(side, strip + 2, side, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topH, child: topBar(true, 1)),
          const SizedBox(height: gap),
          if (result != null)
            result
          else ...[
            ArenaDartBar(slots: dartSlots, sum: visitSum, bust: visitBust, sumKey: sumKey, height: barH),
            const SizedBox(height: gap),
          ],
          SizedBox(
            height: panelsH,
            child: Row(
              children: [
                for (final (i, p) in players.indexed) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(child: ArenaPlayerPanel(player: p, style: panelStyle)),
                ],
              ],
            ),
          ),
          if (result == null) ...[
            if (zoomH > 0) ...[
              const SizedBox(height: gap),
              SizedBox(
                height: zoomH,
                child: FittedBox(fit: BoxFit.scaleDown, child: SizedBox(width: w - side * 2, child: zoom)),
              ),
            ],
            const SizedBox(height: gap),
            Center(child: SizedBox.square(dimension: b, child: board)),
            const SizedBox(height: gap),
            SizedBox(height: actionH, child: Center(child: actions(actionH))),
            const SizedBox(height: gap),
            if (keypad != null) keypad! else SizedBox(height: messagesH, child: FittedBox(fit: BoxFit.scaleDown, child: messages)),
          ],
          const SizedBox(height: gap),
        ],
      ),
    );

    // Zu niedrige Fenster (z. B. Telefon quer unter 5:4): scrollen statt überlaufen.
    if (total > h || keypad != null || result != null) {
      content = SingleChildScrollView(
        child: ConstrainedBox(constraints: BoxConstraints(minHeight: h), child: content),
      );
    }
    return content;
  }
}
