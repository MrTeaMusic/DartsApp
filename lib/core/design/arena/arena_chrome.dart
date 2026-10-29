import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../features/board/domain/segment.dart';
import '../../l10n.dart';
import '../app_theme.dart';
import '../dart_icon.dart';
import '../components/components.dart' show segmentColor;
import 'arena_palette.dart';

/// Ein Platz der Wurfleiste: leer (Dart-Symbol), geworfenes Feld oder der
/// empfohlene Wurf in Gelb.
@immutable
class ArenaDartSlot {
  const ArenaDartSlot({
    this.segment,
    this.planned,
    this.plannedColor,
    this.onTap,
    this.slotKey,
    this.edited = false,
    this.dim = false,
    this.addHint = false,
    this.editedTooltip,
    this.addTooltip,
  });
  final Segment? segment;
  final Segment? planned;
  final Color? plannedColor;
  final VoidCallback? onTap;
  final Key? slotKey;

  /// Von Hand gesetzter Dart: kleiner Stift in der Ecke.
  final bool edited;

  /// Gedämpft (z. B. die letzte Aufnahme, solange noch kein Dart der neuen kam).
  final bool dim;

  /// Leerer Platz, der sich antippen lässt, um einen Dart zu ergänzen („+“).
  final bool addHint;
  final String? editedTooltip;
  final String? addTooltip;
}

/// Leiste über dem Board: drei Plätze für die Darts der Aufnahme und rechts
/// die Summe. Geworfene Darts lassen sich antippen und korrigieren.
class ArenaDartBar extends StatelessWidget {
  const ArenaDartBar({
    super.key,
    required this.slots,
    required this.sum,
    this.bust = false,
    this.sumKey,
    required this.height,
  });
  final List<ArenaDartSlot> slots;
  final int sum;
  final bool bust;
  final Key? sumKey;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fontSize = height * 0.42;
    final iconColor = Colors.white.withValues(alpha: 0.92);
    return Container(
      height: height,
      decoration: BoxDecoration(color: ArenaPalette.surface, borderRadius: BorderRadius.circular(math.min(28, height * 0.3))),
      child: Row(
        children: [
          Expanded(
            flex: 83,
            child: Row(
              children: [
                for (final (i, slot) in slots.indexed)
                  Expanded(
                    child: Semantics(
                      button: slot.onTap != null,
                      label: l10n.arenaDartSlot(i + 1),
                      child: InkWell(
                        key: slot.slotKey,
                        borderRadius: BorderRadius.circular(height * 0.3),
                        onTap: slot.onTap,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Center(
                              child: slot.segment != null
                                  ? FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        slot.segment!.name,
                                        style: _style(fontSize, segmentColor(context, slot.segment!).withValues(alpha: slot.dim ? 0.6 : 1)),
                                      ),
                                    )
                                  : slot.planned != null
                                  ? FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        slot.planned!.name,
                                        style: _style(fontSize, (slot.plannedColor ?? ArenaPalette.hint).withValues(alpha: 0.7)),
                                      ),
                                    )
                                  : DartIcon(size: height * 0.5, color: iconColor),
                            ),
                            if (slot.edited)
                              Positioned(
                                top: height * 0.1,
                                right: height * 0.12,
                                child: _Corner(
                                  tooltip: slot.editedTooltip,
                                  icon: Icons.edit_rounded,
                                  size: math.max(11, height * 0.22),
                                ),
                              ),
                            if (slot.addHint && slot.segment == null)
                              Positioned(
                                bottom: height * 0.08,
                                right: height * 0.12,
                                child: _Corner(
                                  tooltip: slot.addTooltip,
                                  icon: Icons.add_circle_outline_rounded,
                                  size: math.max(11, height * 0.24),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(width: 1, height: height * 0.62, color: ArenaPalette.separator.withValues(alpha: 0.6)),
          Expanded(
            flex: 17,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    bust ? l10n.arenaBust.toUpperCase() : '$sum',
                    key: sumKey,
                    maxLines: 1,
                    style: _style(bust ? fontSize * 0.7 : fontSize * 1.05, bust ? ArenaPalette.danger : Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static TextStyle _style(double size, Color color) => TextStyle(
    fontFamily: AppTypography.family,
    fontSize: size,
    fontWeight: FontWeight.w800,
    color: color,
    height: 1.0,
    fontFeatures: AppTypography.tabular,
  );
}

/// Kleines Symbol in der Ecke eines Dart-Platzes (Stift, „+“).
class _Corner extends StatelessWidget {
  const _Corner({required this.tooltip, required this.icon, required this.size});
  final String? tooltip;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = Icon(icon, size: size, color: ArenaPalette.blueLight);
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// Kleines Schild in der Kopfzeile („501“, „Erster bis 1 Leg“, „SI-DO“).
class ArenaChip extends StatelessWidget {
  const ArenaChip({super.key, required this.label, this.alt = false, this.size = 14});
  final String label;
  final bool alt;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.95, vertical: size * 0.38),
      decoration: BoxDecoration(color: alt ? ArenaPalette.chipAlt : ArenaPalette.chip, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(fontFamily: AppTypography.family, fontSize: size, fontWeight: FontWeight.w500, color: Colors.white, height: 1.15),
      ),
    );
  }
}

/// Kopfzeile: links „Verlassen“ mit den Schildern darunter, rechts die
/// kleinen Symbole (Quelle, Caller, Vollbild).
class ArenaTopBar extends StatelessWidget {
  const ArenaTopBar({
    super.key,
    required this.leaveKey,
    required this.onLeave,
    required this.chips,
    required this.trailing,
    this.compact = false,
    this.scale = 1,
  });
  final Key leaveKey;
  final VoidCallback onLeave;
  final List<String> chips;
  final List<Widget> trailing;

  /// Telefon: Schilder in einer eigenen Zeile.
  final bool compact;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = 14 * scale.clamp(0.9, 1.3);
    final leave = InkWell(
      key: leaveKey,
      borderRadius: BorderRadius.circular(8),
      onTap: onLeave,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chevron_left_rounded, size: size * 1.7, color: Colors.white),
            Text(
              l10n.arenaLeave,
              style: TextStyle(fontFamily: AppTypography.family, fontSize: size + 1, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        ),
      ),
    );
    final chipRow = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final (i, c) in chips.indexed) ArenaChip(label: c, alt: i.isOdd, size: size),
      ],
    );
    // Kompakte Symbolknöpfe, damit die Kopfzeile niedrig bleibt.
    final icons = IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
          minimumSize: const Size(34, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: trailing),
    );
    // Symbole und Schaltflächen im dunklen Arena-Theme (weiße Symbole).
    return IconTheme(
      data: const IconThemeData(color: Colors.white, size: 22),
      child: compact
          // Telefon: bei knapper Höhe (Schilder in zwei Zeilen) verkleinern statt überlaufen.
          ? LayoutBuilder(
              builder: (context, c) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: c.maxWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [leave, const Spacer(), Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: icons))]),
                      const SizedBox(height: 4),
                      Padding(padding: const EdgeInsets.only(left: 4), child: chipRow),
                    ],
                  ),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [leave, const Spacer(), icons]),
                const SizedBox(height: 6),
                Padding(padding: const EdgeInsets.only(left: 4), child: chipRow),
              ],
            ),
    );
  }
}

/// Schalterleiste: Rückgängig, Weiter und die kleinen Symbole (Korrigieren,
/// Beenden) auf blauem Grund.
class ArenaActionBar extends StatelessWidget {
  const ArenaActionBar({
    super.key,
    required this.undoKey,
    required this.onUndo,
    required this.nextKey,
    required this.onNext,
    required this.undoLabel,
    required this.nextLabel,
    this.icons = const [],
    this.height = 44,
    this.showUndoNext = true,
    this.showUndo = true,
    this.undoIcon = Icons.undo_rounded,
    this.nextIcon = Icons.skip_next_rounded,
  });
  final Key undoKey;
  final VoidCallback? onUndo;
  final Key nextKey;
  final VoidCallback? onNext;
  final String undoLabel;
  final String nextLabel;

  /// Kleine Symbolknöpfe links (Korrigieren, Beenden).
  final List<Widget> icons;
  final double height;

  /// Beim Tastenfeld der manuellen Eingabe gibt es beides dort.
  final bool showUndoNext;

  /// Nur die rechte Schaltfläche (z. B. „Beenden“ im Live-Modus).
  final bool showUndo;
  final IconData undoIcon;
  final IconData nextIcon;

  @override
  Widget build(BuildContext context) {
    final inner = height - 10;
    final label = TextStyle(fontFamily: AppTypography.family, fontSize: math.max(12, inner * 0.38), fontWeight: FontWeight.w600);
    return Container(
      height: height,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: ArenaPalette.pill, borderRadius: BorderRadius.circular(height / 2)),
      // Bei schmaler Breite (Telefon mit vielen Symbolen) verkleinern statt überlaufen.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, icon) in icons.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            icon,
          ],
          if (showUndoNext) ...[
            if (icons.isNotEmpty) const SizedBox(width: 6),
            if (showUndo) ...[
              _Pill(
                key: undoKey,
                height: inner,
                onPressed: onUndo,
                filled: false,
                icon: undoIcon,
                label: undoLabel,
                style: label,
              ),
              const SizedBox(width: 6),
            ],
            _Pill(
              key: nextKey,
              height: inner,
              onPressed: onNext,
              filled: true,
              icon: nextIcon,
              label: nextLabel,
              style: label,
            ),
          ],
        ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.height, required this.onPressed, required this.filled, required this.icon, required this.label, required this.style});
  final double height;
  final VoidCallback? onPressed;
  final bool filled;
  final IconData icon;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = Colors.white.withValues(alpha: enabled ? 1 : 0.6);
    return Material(
      color: filled ? (enabled ? ArenaPalette.blue : ArenaPalette.blue.withValues(alpha: 0.45)) : Colors.transparent,
      shape: StadiumBorder(side: filled ? BorderSide.none : BorderSide(color: ArenaPalette.blue.withValues(alpha: enabled ? 1 : 0.6), width: 1.5)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: height * 0.45),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: height * 0.5, color: fg),
                SizedBox(width: height * 0.15),
                Text(label, maxLines: 1, style: style.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Runder Symbolknopf in der Schalterleiste.
class ArenaIconButton extends StatelessWidget {
  const ArenaIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.size = 34});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: ArenaPalette.blue.withValues(alpha: onPressed == null ? 0.35 : 1),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: size, height: size, child: Icon(icon, size: size * 0.55, color: Colors.white)),
        ),
      ),
    );
  }
}

/// Meldungen unter dem Board: Hinweis zum Wurf (Checkout-Weg), Status und
/// Ereignis (Leg gewonnen, Bust).
class ArenaMessages extends StatelessWidget {
  const ArenaMessages({
    super.key,
    this.hint,
    this.hintKey,
    this.hintColor = ArenaPalette.hint,
    this.status,
    this.statusKey,
    this.statusMuted = false,
    this.statusColor,
    this.event,
    this.eventKey,
    this.eventColor = ArenaPalette.blue,
    this.tempo,
    this.scale = 1,
  });
  final String? hint;
  final Key? hintKey;
  final Color hintColor;
  final String? status;
  final Key? statusKey;
  final bool statusMuted;

  /// Abweichende Farbe des Status (z. B. Warnung bei fehlender Verbindung).
  final Color? statusColor;
  final String? event;
  final Key? eventKey;
  final Color eventColor;

  /// Leise Zeile mit dem Wurftempo (gedämpft, ganz unten).
  final String? tempo;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final t = scale.clamp(0.85, 1.3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (event != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: EdgeInsets.symmetric(horizontal: 16 * t, vertical: 7 * t),
            decoration: BoxDecoration(
              color: eventColor.withValues(alpha: 0.2),
              border: Border.all(color: eventColor.withValues(alpha: 0.8)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              event!,
              key: eventKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppTypography.family, fontSize: 16 * t, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              hint!,
              key: hintKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppTypography.family, fontSize: 15 * t, fontWeight: FontWeight.w700, color: hintColor),
            ),
          ),
        if (status != null)
          Text(
            status!,
            key: statusKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTypography.family,
              fontSize: 14 * t,
              fontWeight: FontWeight.w500,
              color: statusColor ?? (statusMuted ? ArenaPalette.textMuted : Colors.white.withValues(alpha: 0.9)),
            ),
          ),
        if (tempo != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 13 * t, color: ArenaPalette.textMuted),
                SizedBox(width: 4 * t),
                Text(
                  tempo!,
                  key: const Key('tempo-hint'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.family,
                    fontSize: 12.5 * t,
                    fontWeight: FontWeight.w500,
                    color: ArenaPalette.textMuted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
