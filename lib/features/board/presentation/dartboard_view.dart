import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/design/tokens.dart';
import '../domain/board_geometry.dart';
import '../domain/segment.dart';
import 'board_style.dart';
import 'dartboard_painter.dart';

export 'dartboard_painter.dart' show BoardDecoration, ScatterMarker;

/// Großes, animiertes Dartboard.
///
/// * Tippen meldet Position und Feld an [onTap] (Simulator).
/// * Der neueste Treffer pulsiert, das getroffene Feld leuchtet kurz auf.
/// * [highlighted] hebt Zielfelder dauerhaft pulsierend hervor.
/// * [heat] zeichnet eine Heatmap über das Board, [scatter] ein Streubild,
///   [decoration] eine eigene ruhende Zeichnung (z. B. Streuungs-Ellipsen).
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
    this.decoration,
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

  /// Ruhende Zusatz-Zeichnung in Board-Koordinaten (siehe [BoardDecoration]).
  final BoardDecoration? decoration;
  final void Function(BoardPoint point, Segment segment)? onTap;

  @override
  ConsumerState<DartboardView> createState() => _DartboardViewState();
}

class _DartboardViewState extends ConsumerState<DartboardView> with TickerProviderStateMixin implements BoardAnimation {
  late final AnimationController _hit = AnimationController(vsync: this, duration: AppDurations.hit, value: 1);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _heat = AnimationController(vsync: this, duration: AppDurations.slow);
  late final Listenable _animations = Listenable.merge([_hit, _pulse]);
  Segment? _hover;

  // Die Animationen werden erst beim Zeichnen gelesen (siehe BoardAnimation):
  // ein Frame des Pulses zeichnet nur die obere Ebene neu, ohne Neuaufbau und
  // Layout, und damit nie den Rest des Bildschirms.
  @override
  void addListener(VoidCallback listener) => _animations.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _animations.removeListener(listener);

  @override
  double get hitProgress => _hit.value;

  @override
  double get highlightStrength => 0.45 + 0.55 * Curves.easeInOut.transform(_pulse.value);

  @override
  double get flashStrength => 1 - Curves.easeIn.transform(_hit.value);

  @override
  void initState() {
    super.initState();
    _syncPulse();
    _heat.value = widget.showHeat ? 1 : 0;
    // Ende der Ein-/Ausblendung: zwischen eigener Ebene und Bild wechseln.
    _heat.addStatusListener((status) {
      if (!status.isAnimating && mounted) setState(() {});
    });
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
    _base.dispose();
    _heatImage.dispose();
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
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    // Eigene Ebene: Treffer und Puls zeichnen nie den Rest des Bildschirms neu.
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: focus == null ? 1 : widget.aspectRatio,
        child: LayoutBuilder(builder: (context, constraints) {
          final view = _Viewport.of(constraints.biggest, style, focus, widget.focusWidth);
          Segment segmentAt(Offset local) => BoardGeometry.segmentAt(view.toBoard(local));
          final interactive = widget.onTap != null;
          DartboardPainter layer(BoardLayer layer, {double heatOpacity = 0}) => DartboardPainter(
                colors: colors,
                style: style,
                layer: layer,
                heat: layer == BoardLayer.heat ? widget.heat : const [],
                heatOpacity: heatOpacity,
                markerScale: view.markerScale,
                viewRotation: view.rotation,
              );
          CustomPainter framed(DartboardPainter p) => focus == null ? p : _ZoomPainter(p, view);
          var image = _base.image(
            _RasterKey(view, style, colors, pixelRatio),
            (canvas) => framed(layer(BoardLayer.base)).paint(canvas, view.size),
          );
          var imageKey = _base.key!;
          // Die Heatmap ändert sich nur mit ihren Punkten. Steht sie, ist sie
          // mit der Scheibe in einem Bild gerastert (zusammengesetzt wie zuvor
          // auf dem Bildschirm); nur während der Ein- und Ausblendung wird sie
          // als eigene Ebene gezeichnet.
          final heatOn = widget.heat.isNotEmpty;
          final heatFading = heatOn && _heat.isAnimating;
          if (heatOn && !heatFading && _heat.value >= 1) {
            final base = image;
            image = _heatImage.image(
              _RasterKey(view, style, colors, pixelRatio, content: widget.heat, under: base),
              (canvas) {
                _ImagePainter(base, _base.key!).paint(canvas, view.size);
                framed(layer(BoardLayer.heat, heatOpacity: 1)).paint(canvas, view.size);
              },
            );
            imageKey = _heatImage.key!;
          }
          final board = DartboardPainter(
            colors: colors,
            style: style,
            layer: BoardLayer.overlay,
            animation: this,
            hits: [
              for (var i = 0; i < widget.hits.length; i++)
                HitMarker(widget.hits[i], latest: i == widget.hits.length - 1),
            ],
            highlighted: widget.highlighted,
            flash: widget.lastSegment,
            hover: _hover,
            scatter: widget.scatter,
            decoration: widget.decoration,
            markerScale: view.markerScale,
            viewRotation: view.rotation,
          );
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
                    child: CustomPaint(size: view.size, painter: _ImagePainter(image, imageKey)),
                  ),
                  if (heatFading)
                    RepaintBoundary(
                      child: CustomPaint(
                        size: view.size,
                        painter: _FadingHeatPainter(_heat, (opacity) => framed(layer(BoardLayer.heat, heatOpacity: opacity))),
                      ),
                    ),
                  // Treffer und Hervorhebungen bewegen sich: nur diese Ebene wird
                  // bei jeder Animation neu gezeichnet.
                  RepaintBoundary(
                    child: CustomPaint(
                      size: view.size,
                      painter: focus == null ? board : _ZoomPainter(board, view),
                    ),
                  ),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  // Gerasterte Scheibe und Heatmap.
  late final _Raster _base = _Raster(_invalidate);
  late final _Raster _heatImage = _Raster(_invalidate);

  void _invalidate() {
    if (mounted) setState(() {});
  }

  void _setHover(Segment? s) {
    if (s != _hover) setState(() => _hover = s);
  }
}

/// Ein als Bild gerasterter Painter (Scheibe oder Heatmap) in Pixeln des
/// Bildschirms. Ändert sich nur die Größe (z. B. während der Doppel-Zoom ein-
/// oder ausfährt), wird das bisherige Bild gestreckt, bis die Größe wieder
/// still steht.
class _Raster {
  _Raster(this._invalidate);
  final VoidCallback _invalidate;

  ui.Image? _image;
  _RasterKey? key;
  Timer? _resize;

  ui.Image image(_RasterKey next, void Function(Canvas canvas) paint) {
    final current = _image;
    final old = key;
    if (current != null && old == next) return current;
    if (current != null && old != null && old.sameExceptSize(next)) {
      _resize?.cancel();
      _resize = Timer(const Duration(milliseconds: 120), () {
        key = null;
        _invalidate();
      });
      return current;
    }
    _resize?.cancel();
    final view = next.view;
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder)..scale(next.pixelRatio));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      math.max(1, (view.size.width * next.pixelRatio).ceil()),
      math.max(1, (view.size.height * next.pixelRatio).ceil()),
    );
    picture.dispose();
    current?.dispose();
    _image = image;
    key = next;
    return image;
  }

  void dispose() {
    _resize?.cancel();
    _image?.dispose();
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

/// Wofür ein gerastertes Bild gilt. [content] sind die Punkte der Heatmap:
/// gleiche Punkte in einer neuen Liste brauchen kein neues Bild. [under] ist
/// das Bild der Scheibe darunter.
@immutable
class _RasterKey {
  const _RasterKey(this.view, this.style, this.colors, this.pixelRatio, {this.content, this.under});
  final _Viewport view;
  final BoardStyle style;
  final DartColors colors;
  final double pixelRatio;
  final List<BoardPoint>? content;
  final ui.Image? under;

  /// Gleich bis auf die Größe der Fläche (bei gleicher Form).
  bool sameExceptSize(_RasterKey o) =>
      style == o.style &&
      identical(colors, o.colors) &&
      pixelRatio == o.pixelRatio &&
      view.rotation == o.view.rotation &&
      view.isZoom == o.view.isZoom &&
      (view.size.aspectRatio - o.view.size.aspectRatio).abs() < 0.01 &&
      identical(under, o.under) &&
      (identical(content, o.content) || listEquals(content, o.content));

  @override
  bool operator ==(Object other) =>
      other is _RasterKey &&
      sameExceptSize(other) &&
      view.size == other.view.size &&
      view.board == other.view.board &&
      view.target == other.view.target;

  @override
  int get hashCode =>
      Object.hash(style, colors, pixelRatio, view.size, view.board, view.target, view.rotation, content?.length);
}

/// Zeichnet ein gerastertes Bild: Pixel für Pixel, oder gestreckt, solange
/// die Fläche gerade ihre Größe ändert.
class _ImagePainter extends CustomPainter {
  _ImagePainter(this.image, this.key);
  final ui.Image image;
  final _RasterKey key;

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

/// Die Heatmap während der Ein- und Ausblendung: jeder Frame zeichnet nur
/// diese Ebene mit der aktuellen Deckkraft.
class _FadingHeatPainter extends CustomPainter {
  _FadingHeatPainter(this.opacity, this.painter) : super(repaint: opacity);
  final Animation<double> opacity;
  final CustomPainter Function(double opacity) painter;

  @override
  void paint(Canvas canvas, Size size) => painter(opacity.value).paint(canvas, size);

  @override
  bool shouldRepaint(_FadingHeatPainter old) => true;
}

/// Zeichnet den Ausschnitt einer großen Scheibe in die kleine Fläche.
class _ZoomPainter extends CustomPainter {
  _ZoomPainter(this.board, this.view) : super(repaint: board.animation);

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
