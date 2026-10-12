import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/design/tokens.dart';
import '../domain/board_geometry.dart';
import '../domain/segment.dart';
import 'board_style.dart';
import 'dartboard_painter.dart';

export 'dartboard_painter.dart' show ScatterMarker;

/// Großes, animiertes Dartboard.
///
/// * Tippen meldet Position und Feld an [onTap] (Simulator).
/// * Der neueste Treffer pulsiert, das getroffene Feld leuchtet kurz auf.
/// * [highlighted] hebt Zielfelder dauerhaft pulsierend hervor.
/// * [heat] zeichnet eine Heatmap über das Board, [scatter] ein Streubild.
/// * Mit [focus] zeigt die Fläche nur einen vergrößerten Ausschnitt rund um
///   dieses Feld (Doppel-Zoom); Treffer und Antippen funktionieren dort genauso.
class DartboardView extends ConsumerStatefulWidget {
  const DartboardView({
    super.key,
    this.hits = const [],
    this.lastSegment,
    this.highlighted = const {},
    this.heat = const [],
    this.showHeat = false,
    this.scatter = const [],
    this.hitSerial = 0,
    this.onTap,
    this.style,
    this.focus,
    this.focusWidth = 0.62,
    this.aspectRatio = 1,
    this.semanticsLabel = 'Dartboard',
  });

  /// Feld, um das der Ausschnitt zentriert ist; null = ganze Scheibe.
  final Segment? focus;

  /// Breite des Ausschnitts in Board-Einheiten (Radius Double-Ring = 1).
  final double focusWidth;

  /// Seitenverhältnis der Fläche; die ganze Scheibe ist immer quadratisch.
  final double aspectRatio;
  final String semanticsLabel;

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

  /// Streubild der Statistik (siehe [ScatterMarker]).
  final List<ScatterMarker> scatter;
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
    _resize?.cancel();
    _image?.dispose();
    _hit.dispose();
    _pulse.dispose();
    _heat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final BoardStyle style = widget.style ?? ref.watch(settingsProvider.select((s) => s.boardStyle));
    final focus = widget.focus;
    return AspectRatio(
      aspectRatio: focus == null ? 1 : widget.aspectRatio,
      child: LayoutBuilder(builder: (context, constraints) {
        final view = _Viewport.of(constraints.biggest, style, focus, widget.focusWidth);
        Segment segmentAt(Offset local) => BoardGeometry.segmentAt(view.toBoard(local));
        final interactive = widget.onTap != null;
        return MouseRegion(
          cursor: interactive ? SystemMouseCursors.precise : MouseCursor.defer,
          onHover: interactive ? (e) => _setHover(segmentAt(e.localPosition)) : null,
          onExit: interactive ? (_) => _setHover(null) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: interactive
                ? (d) {
                    final p = view.toBoard(d.localPosition);
                    widget.onTap!(p, BoardGeometry.segmentAt(p));
                  }
                : null,
            child: Semantics(
              label: widget.semanticsLabel,
              child: Stack(children: [
                // Die Scheibe selbst ändert sich nur mit Größe und Optik: einmal
                // als Bild gerastert statt in jedem Frame neu gezeichnet.
                RepaintBoundary(
                  child: CustomPaint(
                    size: view.size,
                    painter: _ImagePainter(_baseImage(context, view, style, colors), _imageKey!),
                  ),
                ),
                // Treffer und Hervorhebungen bewegen sich: nur diese Ebene wird
                // bei jeder Animation neu gezeichnet.
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_hit, _pulse, _heat]),
                    builder: (context, _) {
                      final board = DartboardPainter(
                        colors: colors,
                        style: style,
                        layer: BoardLayer.overlay,
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
                        scatter: widget.scatter,
                        markerScale: view.markerScale,
                        viewRotation: view.rotation,
                      );
                      return CustomPaint(
                        size: view.size,
                        painter: focus == null ? board : _ZoomPainter(board, view),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  // Gerasterte Scheibe und wofür sie gilt.
  ui.Image? _image;
  _BaseKey? _imageKey;
  Timer? _resize;

  /// Die Scheibe als Bild in Pixeln des Bildschirms. Ändert sich nur die
  /// Größe (z. B. während der Doppel-Zoom ein- oder ausfährt), wird das
  /// bisherige Bild gestreckt, bis die Größe wieder still steht.
  ui.Image _baseImage(BuildContext context, _Viewport view, BoardStyle style, DartColors colors) {
    final key = _BaseKey(view, style, colors, MediaQuery.devicePixelRatioOf(context));
    final current = _image;
    final old = _imageKey;
    if (current != null && old == key) return current;
    if (current != null && old != null && old.sameExceptSize(key)) {
      _resize?.cancel();
      _resize = Timer(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _imageKey = null);
      });
      return current;
    }
    _resize?.cancel();
    final base = DartboardPainter(
      colors: colors,
      style: style,
      layer: BoardLayer.base,
      markerScale: view.markerScale,
      viewRotation: view.rotation,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(key.pixelRatio);
    (widget.focus == null ? base : _ZoomPainter(base, view)).paint(canvas, view.size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      math.max(1, (view.size.width * key.pixelRatio).ceil()),
      math.max(1, (view.size.height * key.pixelRatio).ceil()),
    );
    picture.dispose();
    current?.dispose();
    _image = image;
    _imageKey = key;
    return image;
  }

  void _setHover(Segment? s) {
    if (s != _hover) setState(() => _hover = s);
  }
}

/// Wo die (virtuelle) ganze Scheibe in der sichtbaren Fläche liegt.
class _Viewport {
  const _Viewport(this.size, this.board, this.target, this.rotation, this.style, this.markerScale);

  /// Ganze Scheibe: Board = Fläche. Ausschnitt: eine größere, virtuelle
  /// Scheibe, so gedreht und verschoben, dass [focus] oben in der Mitte der
  /// Fläche liegt; ein Doppel verläuft dann immer waagerecht.
  factory _Viewport.of(Size size, BoardStyle style, Segment? focus, double focusWidth) {
    if (focus == null) return _Viewport(size, size, size.center(Offset.zero), 0, style, 1);
    final r = size.width / focusWidth;
    final board = Size.square(2 * r * style.spec.frameExtent);
    final angle = focus.isBull ? 0.0 : BoardGeometry.angleOf(focus.number);
    final center = focus.isBull ? BoardGeometry.centerOf(focus) : BoardGeometry.polar(_focusRadius(focus, focusWidth * size.height / size.width), angle);
    final rotation = -angle * math.pi / 180;
    // Marker wachsen nur schwach mit der Vergrößerung.
    final grow = r / math.max(1, size.shortestSide / 2 / style.spec.frameExtent);
    return _Viewport(size, board, DartboardPainter.toCanvas(center, board, style), rotation, style, math.pow(grow, -0.3).toDouble());
  }

  /// Beim Doppel reicht der Ausschnitt oben bis knapp über die Zahlen: so
  /// steht die Zahl über dem Feld, darunter so viel Scheibe wie möglich.
  static double _focusRadius(Segment s, double height) =>
      s.isDouble ? 1.2 - height / 2 : BoardGeometry.centerOf(s).distance;

  final Size size;

  /// Größe der virtuellen ganzen Scheibe.
  final Size board;

  /// Punkt der virtuellen (ungedrehten) Scheibe, der in der Mitte der Fläche liegt.
  final Offset target;
  final double rotation;
  final BoardStyle style;
  final double markerScale;

  bool get isZoom => board != size;

  BoardPoint toBoard(Offset local) {
    if (!isZoom) return DartboardPainter.toBoard(local, board, style);
    final v = local - size.center(Offset.zero);
    final cos = math.cos(-rotation), sin = math.sin(-rotation);
    final p = Offset(v.dx * cos - v.dy * sin, v.dx * sin + v.dy * cos) + target;
    return DartboardPainter.toBoard(p, board, style);
  }
}

/// Wofür ein gerastertes Bild der Scheibe gilt.
@immutable
class _BaseKey {
  const _BaseKey(this.view, this.style, this.colors, this.pixelRatio);
  final _Viewport view;
  final BoardStyle style;
  final DartColors colors;
  final double pixelRatio;

  /// Gleich bis auf die Größe der Fläche (bei gleicher Form).
  bool sameExceptSize(_BaseKey o) =>
      style == o.style &&
      identical(colors, o.colors) &&
      pixelRatio == o.pixelRatio &&
      view.rotation == o.view.rotation &&
      view.isZoom == o.view.isZoom &&
      (view.size.aspectRatio - o.view.size.aspectRatio).abs() < 0.01;

  @override
  bool operator ==(Object other) =>
      other is _BaseKey &&
      sameExceptSize(other) &&
      view.size == other.view.size &&
      view.board == other.view.board &&
      view.target == other.view.target;

  @override
  int get hashCode => Object.hash(style, colors, pixelRatio, view.size, view.board, view.target, view.rotation);
}

/// Zeichnet die gerasterte Scheibe: Pixel für Pixel, oder gestreckt, solange
/// die Fläche gerade ihre Größe ändert.
class _ImagePainter extends CustomPainter {
  _ImagePainter(this.image, this.key);
  final ui.Image image;
  final _BaseKey key;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / key.view.size.width / key.pixelRatio;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, image.width * scale, image.height * scale),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ImagePainter old) => !identical(old.image, image);
}

/// Zeichnet den Ausschnitt einer großen Scheibe in die kleine Fläche.
class _ZoomPainter extends CustomPainter {
  _ZoomPainter(this.board, this.view);

  final DartboardPainter board;
  final _Viewport view;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final c = size.center(Offset.zero);
    canvas.translate(c.dx, c.dy);
    canvas.rotate(view.rotation);
    canvas.translate(-view.target.dx, -view.target.dy);
    board.paint(canvas, view.board);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ZoomPainter old) =>
      old.view.target != view.target ||
      old.view.board != view.board ||
      old.view.rotation != view.rotation ||
      board.shouldRepaint(old.board);
}
