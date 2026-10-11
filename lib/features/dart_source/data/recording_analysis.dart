import 'dart:convert';

import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../domain/coordinate_calibration.dart';
import '../domain/dart_event.dart';
import 'autodarts_state_mapper.dart';

/// Ein Dart aus einem Mitschnitt.
class RecordedDart {
  const RecordedDart({required this.time, required this.segment, this.rawPoint});
  final DateTime time;

  /// Feld laut Autodarts.
  final Segment segment;

  /// Rohe Koordinaten, wie Autodarts sie schickt (vor Kalibrierung).
  final BoardPoint? rawPoint;

  /// Feld, das DartLab aus den Koordinaten berechnet.
  Segment? fieldFrom(CoordinateCalibration c) => rawPoint == null ? null : BoardGeometry.segmentAt(c.apply(rawPoint!));

  bool? matches(CoordinateCalibration c) => switch (fieldFrom(c)) {
        final f? => f.sameField(segment),
        null => null,
      };
}

/// Auswertung eines Mitschnitts (JSON Lines aus dem Debug-Bildschirm).
///
/// Spielt alle Board-Zustände durch denselben Mapper wie die Live-Quelle und
/// prüft, ob Feld und Koordinaten zusammenpassen. So lässt sich am echten
/// Board klären, ob die Annahmen in `docs/autodarts-protokoll.md` stimmen.
class RecordingAnalysis {
  RecordingAnalysis._({
    required this.lines,
    required this.states,
    required this.darts,
    required this.takeouts,
    required this.corrections,
    required this.undos,
    required this.resets,
    required this.warnings,
    required this.sawThrowsField,
    required this.messageTypes,
  });

  final int lines;

  /// Ausgewertete Board-Zustände.
  final int states;
  final List<RecordedDart> darts;
  final int takeouts;
  final int corrections;
  final int undos;
  final int resets;
  final List<String> warnings;

  /// Enthielt mindestens ein Zustand das Feld `throws`? Wenn nicht, liefert
  /// der Board Manager lokal womöglich keine Würfe.
  final bool sawThrowsField;

  /// Gesehene WebSocket-Nachrichtentypen mit Anzahl.
  final Map<String, int> messageTypes;

  List<RecordedDart> get withCoords => [for (final d in darts) if (d.rawPoint != null) d];

  /// Anteil der Darts, bei denen Feld und Koordinaten zusammenpassen.
  double? agreement(CoordinateCalibration c) {
    final list = withCoords;
    if (list.isEmpty) return null;
    return list.where((d) => d.matches(c) ?? false).length / list.length;
  }

  /// Beste Kalibrierung: alle Drehungen/Spiegelungen, Maßstab aus Darts im
  /// Triple- und Double-Ring geschätzt. `null` ohne Koordinaten.
  CoordinateCalibration? suggestCalibration() {
    final list = withCoords;
    if (list.isEmpty) return null;
    final scale = _estimateScale(list);
    CoordinateCalibration? best;
    var bestScore = -1.0;
    for (final o in CoordinateCalibration.orientations) {
      for (final s in {1.0, scale}) {
        final c = o.withScale(s);
        final score = agreement(c)!;
        // Bei Gleichstand gewinnt die einfachere Variante (zuerst geprüft).
        if (score > bestScore + 1e-9) {
          best = c;
          bestScore = score;
        }
      }
    }
    return best;
  }

  /// Verhältnis aus erwartetem und gemessenem Radius für Triples und Doubles.
  static double _estimateScale(List<RecordedDart> list) {
    final ratios = <double>[];
    for (final d in list) {
      final r = d.rawPoint!.distance;
      if (r <= 0) continue;
      final expected = switch (d.segment.bed) {
        Bed.triple => (BoardGeometry.tripleInnerR + BoardGeometry.tripleOuterR) / 2,
        Bed.double => (BoardGeometry.doubleInnerR + BoardGeometry.doubleOuterR) / 2,
        _ => null,
      };
      if (expected != null) ratios.add(expected / r);
    }
    if (ratios.isEmpty) return 1.0;
    ratios.sort();
    final median = ratios[ratios.length ~/ 2];
    // Auf drei Stellen runden, kleine Abweichungen ignorieren.
    final rounded = (median * 1000).round() / 1000;
    return (rounded - 1).abs() < 0.02 ? 1.0 : rounded;
  }

  /// Liest JSON Lines. Unterstützt das Format des Debug-Bildschirms
  /// (`{"ts","dir","channel","payload"}`) und reine Zustände pro Zeile.
  static RecordingAnalysis analyze(String jsonLines) {
    var time = DateTime.fromMillisecondsSinceEpoch(0);
    final mapper = AutodartsStateMapper(clock: () => time);
    final darts = <RecordedDart>[];
    final types = <String, int>{};
    var lines = 0;
    var states = 0;
    var takeouts = 0;
    var corrections = 0;
    var undos = 0;
    var resets = 0;
    var sawThrows = false;
    // Index des ersten Darts der laufenden Aufnahme in [darts].
    var visitStart = 0;

    void feed(Map<String, Object?> state) {
      states++;
      if (state.containsKey('throws')) sawThrows = true;
      for (final e in mapper.update(state)) {
        switch (e) {
          case DartThrown(:final dart):
            final raw = dart.raw?['coords'];
            darts.add(RecordedDart(time: time, segment: dart.segment, rawPoint: AutodartsStateMapper.parseCoords(raw)));
          case DartCorrected(:final index, :final dart):
            corrections++;
            // Korrigierten Dart in der laufenden Aufnahme ersetzen.
            final i = visitStart + index;
            if (i >= 0 && i < darts.length) {
              darts[i] = RecordedDart(
                time: time,
                segment: dart.segment,
                rawPoint: AutodartsStateMapper.parseCoords(dart.raw?['coords']),
              );
            }
          case DartUndone():
            undos++;
          case TakeoutFinished():
            takeouts++;
            visitStart = darts.length;
          case TurnReset():
            resets++;
            visitStart = darts.length;
          default:
            break;
        }
      }
    }

    for (final line in const LineSplitter().convert(jsonLines)) {
      if (line.trim().isEmpty) continue;
      lines++;
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (decoded is! Map) continue;
      final map = decoded.cast<String, Object?>();
      final ts = map['ts'];
      if (ts is String) time = DateTime.tryParse(ts) ?? time;

      final channel = map['channel'];
      if (channel is String) {
        if (map['dir'] == 'out' || channel == 'info') continue;
        final payload = map['payload'];
        if (payload is! String) continue;
        final Object? inner;
        try {
          inner = jsonDecode(payload);
        } on FormatException {
          continue;
        }
        if (inner is! Map) continue;
        final msg = inner.cast<String, Object?>();
        if (channel == 'ws') {
          final type = msg['type'];
          if (type is String) types[type] = (types[type] ?? 0) + 1;
          final data = msg['data'];
          if (type == 'state' && data is Map) {
            feed(data.cast<String, Object?>());
          } else if (type == null && _looksLikeState(msg)) {
            feed(msg);
          }
        } else if (channel.startsWith('http GET /api/state')) {
          feed(msg);
        }
      } else if (_looksLikeState(map)) {
        feed(map);
      }
    }

    return RecordingAnalysis._(
      lines: lines,
      states: states,
      darts: darts,
      takeouts: takeouts,
      corrections: corrections,
      undos: undos,
      resets: resets,
      warnings: List.unmodifiable(mapper.warnings),
      sawThrowsField: sawThrows,
      messageTypes: types,
    );
  }

  static bool _looksLikeState(Map<String, Object?> m) => m.containsKey('throws') || m.containsKey('numThrows');
}
