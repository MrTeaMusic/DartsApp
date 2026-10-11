import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../domain/dart_event.dart';

/// Übersetzt den Board-Zustand des Autodarts Board Managers in [DartEvent]s.
///
/// ACHTUNG, UNGETESTET GEGEN ECHTE HARDWARE. Das erwartete Format stammt aus
/// Community-Projekten (siehe docs/autodarts-protokoll.md):
///
/// ```json
/// {
///   "connected": true, "running": true,
///   "status": "Throw", "event": "Throw detected",
///   "numThrows": 2,
///   "throws": [
///     {"segment": {"name": "T20", "number": 20, "bed": "Triple", "multiplier": 3},
///      "coords": {"x": 0.01, "y": 0.61}}
///   ]
/// }
/// ```
///
/// Der Zustand enthält immer alle Darts der laufenden Aufnahme. Neue Darts
/// werden durch Vergleich mit dem vorherigen Zustand erkannt.
class AutodartsStateMapper {
  AutodartsStateMapper({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  List<DartThrow>? _previous;
  bool _inTakeout = false;

  /// Hinweise zu Daten, die nicht verstanden wurden (für den Debug-Bildschirm).
  final List<String> warnings = [];

  /// Vergisst den bisherigen Zustand, z. B. nach einer Neuverbindung.
  /// Der nächste Zustand gilt dann als Ausgangslage und erzeugt keine Würfe.
  void resetBaseline() {
    _previous = null;
    _inTakeout = false;
  }

  List<DartEvent> update(Map<String, Object?> state) {
    final now = _clock();
    final events = <DartEvent>[];
    final current = _parseThrows(state, now);
    final numThrows = _asInt(state['numThrows']) ?? current?.length;
    final marker = '${state['event'] ?? state['status'] ?? ''}'.toLowerCase();

    final previous = _previous;
    if (previous == null) {
      // Ausgangslage: keine alten Darts als neu melden.
      _previous = current ?? const [];
      _inTakeout = _isTakeoutMarker(marker);
      return events;
    }

    if (marker == 'manual reset') {
      events.add(TurnReset(now));
      _inTakeout = false;
    }

    if (current != null) {
      final shared = current.length < previous.length ? current.length : previous.length;
      for (var i = 0; i < shared; i++) {
        if (!current[i].segment.sameField(previous[i].segment)) {
          events.add(DartCorrected(i, current[i]));
        }
      }
      if (current.length > previous.length) {
        if (_inTakeout) {
          // Neuer Dart, obwohl wir im Takeout waren: Takeout ist offenbar vorbei.
          events.add(TakeoutFinished(now));
          _inTakeout = false;
        }
        for (var i = previous.length; i < current.length; i++) {
          events.add(DartThrown(current[i], index: i));
        }
      } else if (current.isNotEmpty && current.length < previous.length) {
        for (var i = current.length; i < previous.length; i++) {
          events.add(DartUndone(now));
        }
      }
      _previous = current;
    }

    if (_isTakeoutMarker(marker) && !_inTakeout) {
      events.add(TakeoutStarted(now));
      _inTakeout = true;
    }

    final boardEmpty = numThrows == 0;
    final hadDarts = previous.isNotEmpty;
    if (marker == 'takeout finished' || (boardEmpty && (_inTakeout || hadDarts))) {
      if (marker != 'manual reset' &&
          !events.any((e) => e is TakeoutFinished)) {
        events.add(TakeoutFinished(now));
      }
      _inTakeout = false;
      _previous = const [];
    }
    return events;
  }

  static bool _isTakeoutMarker(String marker) =>
      marker == 'takeout started' || marker == 'takeout in progress';

  List<DartThrow>? _parseThrows(Map<String, Object?> state, DateTime now) {
    final raw = state['throws'];
    if (raw == null) return null;
    if (raw is! List) {
      warnings.add('"throws" ist keine Liste: ${raw.runtimeType}');
      return null;
    }
    final result = <DartThrow>[];
    for (final item in raw) {
      if (item is! Map) {
        warnings.add('Wurf ist kein Objekt: $item');
        continue;
      }
      final map = item.cast<String, Object?>();
      final segment = parseSegment(map['segment']);
      if (segment == null) {
        warnings.add('Segment nicht erkannt: ${map['segment']}');
        continue;
      }
      result.add(DartThrow(
        segment: segment,
        position: parseCoords(map['coords']),
        timestamp: now,
        source: DartSourceKind.autodartsLocal,
        raw: map,
      ));
    }
    return result;
  }

  /// Liest ein Segment-Objekt. Bevorzugt Zahl + Multiplikator, nutzt "bed"
  /// zur Unterscheidung innere/äußere Single und fällt auf "name" zurück.
  static Segment? parseSegment(Object? raw) {
    if (raw is String) return Segment.tryParse(raw);
    if (raw is! Map) return null;
    final bed = '${raw['bed'] ?? ''}';
    final number = _asInt(raw['number']);
    final multiplier = _asInt(raw['multiplier']);
    if (bed == 'Outside' || multiplier == 0) return Segment.miss;
    if (number != null && multiplier != null) {
      try {
        final s = Segment.fromNumber(number, multiplier);
        if (bed == 'SingleInner' && s.bed == Bed.singleOuter) {
          return Segment.single(number, inner: true);
        }
        return s;
      } on ArgumentError {
        // Weiter mit dem Namen.
      }
    }
    final name = raw['name'];
    return name is String ? Segment.tryParse(name) : null;
  }

  static BoardPoint? parseCoords(Object? raw) {
    if (raw is! Map) return null;
    final x = raw['x'];
    final y = raw['y'];
    if (x is num && y is num) return BoardPoint(x.toDouble(), y.toDouble());
    return null;
  }

  static int? _asInt(Object? v) => switch (v) {
        final int i => i,
        final double d => d.round(),
        final String s => int.tryParse(s),
        _ => null,
      };
}
