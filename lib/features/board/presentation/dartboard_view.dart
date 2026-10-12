import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/design/tokens.dart';
import '../domain/board_geometry.dart';
import '../domain/segment.dart';
import 'board_style.dart';
import 'dartboard_painter.dart';

/// Großes, animiertes Dartboard.
///
/// * Tippen meldet Position und Feld an [onTap] (Simulator).
/// * Der neueste Treffer pulsiert, das getroffene Feld leuchtet kurz auf.
/// * [highlighted] hebt Zielfelder dauerhaft pulsierend hervor.
/// * [heat] zeichnet eine Heatmap über das Board.
class DartboardView extends ConsumerStatefulWidget {
  const DartboardView({
    super.key,
    this.hits = const [],
    this.lastSegment,
    this.highlighted = const {},
    this.heat = const [],
    this.showHeat = false,
    this.hitSerial = 0,
    this.onTap,
    this.style,
  });

  /// Feste Optik (z. B. Vorschau); sonst die Wahl aus den Optionen.
  final BoardStyle? style;

  /// Zählt geworfene Darts. Steigt der Wert, startet die Trefferanimation.
  final int hitSerial;

  /// Positionen der Darts der aktuellen Aufnahme, neuester zuletzt.
  final List<BoardPoint> hits;

  /// Zuletzt getroffenes Feld; ändert es sich, leuchtet es auf. Wichtig für
  /// Quellen ohne Koordinaten (manuelle Eingabe).
  final Segment? lastSegment;
  final Set<Segment> highlighted;
  final List<BoardPoint> heat;
  final bool showHeat;
  final void Function(BoardPoint point, Segment segment)? onTap;

  @override
  ConsumerState<DartboardView> createState() => _DartboardViewState();
}

class _DartboardViewState extends ConsumerState<DartboardView> with TickerProviderStateMixin {
  late final AnimationController _hit = AnimationController(vsync: this, duration: AppDurations.hit, value: 1);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _heat = AnimationController(vsync: this, duration: AppDurations.slow);
  Segment? _hover;

  @override
  void initState() {
    super.initState();
    _syncPulse();
    _heat.value = widget.showHeat ? 1 : 0;
  }

  @override
  void didUpdateWidget(DartboardView old) {
    super.didUpdateWidget(old);
    if (widget.hitSerial > old.hitSerial) _hit.forward(from: 0);
    if (widget.highlighted.isNotEmpty != old.highlighted.isNotEmpty) _syncPulse();
    if (widget.showHeat != old.showHeat) {
      widget.showHeat ? _heat.forward() : _heat.reverse();
    }
  }

  void _syncPulse() {
    if (widget.highlighted.isNotEmpty) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _hit.dispose();
    _pulse.dispose();
    _heat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final BoardStyle style = widget.style ?? ref.watch(settingsProvider.select((s) => s.boardStyle));
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        Segment segmentAt(Offset local) => BoardGeometry.segmentAt(DartboardPainter.toBoard(local, size, style));
        final interactive = widget.onTap != null;
        return MouseRegion(
          cursor: interactive ? SystemMouseCursors.precise : MouseCursor.defer,
          onHover: interactive ? (e) => _setHover(segmentAt(e.localPosition)) : null,
          onExit: interactive ? (_) => _setHover(null) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: interactive
                ? (d) {
                    final p = DartboardPainter.toBoard(d.localPosition, size, style);
                    widget.onTap!(p, BoardGeometry.segmentAt(p));
                  }
                : null,
            child: Semantics(
              label: 'Dartboard',
              child: AnimatedBuilder(
                animation: Listenable.merge([_hit, _pulse, _heat]),
                builder: (context, _) => CustomPaint(
                  size: size,
                  painter: DartboardPainter(
                    colors: colors,
                    style: style,
                    hits: [
                      for (var i = 0; i < widget.hits.length; i++)
                        HitMarker(widget.hits[i], latest: i == widget.hits.length - 1),
                    ],
                    hitProgress: _hit.value,
                    highlighted: widget.highlighted,
                    highlightStrength: 0.45 + 0.55 * Curves.easeInOut.transform(_pulse.value),
                    flash: widget.lastSegment,
                    flashStrength: 1 - Curves.easeIn.transform(_hit.value),
                    hover: _hover,
                    heat: widget.heat,
                    heatOpacity: _heat.value,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _setHover(Segment? s) {
    if (s != _hover) setState(() => _hover = s);
  }
}
