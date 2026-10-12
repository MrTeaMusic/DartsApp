import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../caller/caller.dart';
import '../domain/match_call_planner.dart';
import '../domain/match_session.dart';
import '../domain/x01_match.dart';
import 'match_controller.dart';

/// Verbindet das laufende Match (auch Turnierspiele) mit dem [Caller]. Wird
/// einmal in der App-Wurzel aktiviert, wie der Hook der Trainingsspiele.
///
/// Angesagt werden „Game on“ beim Start, jede abgeschlossene Aufnahme von
/// Menschen und Bots (Punkte oder „Bust“, dazu „You require“ für den
/// nächsten Spieler auf einem Finish) und „Game shot“ bei Leg, Satz und
/// Match. Rückgängig und Korrekturen bauen das Match neu auf; das erkennt der
/// Hook am neuen Match-Objekt und sagt dann nichts an.
final matchCallerProvider = Provider<void>((ref) {
  final tracker = _MatchTracker();
  ref.listen(matchControllerProvider, (_, next) => tracker.onChange(next, ref.read(callerProvider)));
});

class _MatchTracker {
  MatchSession? _session;
  X01Match? _match;

  /// Aufnahme (visitSerial), die zuletzt angesagt wurde, -1 = keine.
  int _announced = -1;
  int _lastSerial = 0;
  int _lastCurrent = 0;
  int _lastPhysical = 0;

  void onChange(MatchState? next, Caller caller) {
    if (next == null) {
      if (_session != null) unawaited(caller.stop());
      _session = null;
      _match = null;
      return;
    }
    final m = next.match;
    final closed = m.visitClosed || m.finished;
    if (!identical(next.session, _session)) {
      _session = next.session;
      _match = m;
      _announced = closed ? m.visitSerial : -1;
      _remember(m);
      if (!next.ended) unawaited(caller.gameOn());
      return;
    }
    if (!identical(m, _match)) {
      // Rückgängig/Korrektur: neu synchronisieren, nichts ansagen.
      _match = m;
      _announced = closed ? m.visitSerial : -1;
      _remember(m);
      return;
    }
    // Abgebrochen: keine Ansage mehr.
    if (next.ended && !m.finished) return;
    if (closed) {
      if (m.visitSerial != _announced) {
        _announced = m.visitSerial;
        unawaited(caller.announce(MatchCallPlanner.forClosedVisit(m)));
      }
    } else if (m.visitSerial != _lastSerial && _announced != _lastSerial && _lastPhysical > 0) {
      // Vor dem dritten Dart per Takeout/„Weiter“ beendet.
      _announced = _lastSerial;
      unawaited(caller.announce(MatchCallPlanner.forEndedVisit(m, _lastCurrent)));
    }
    _remember(m);
  }

  void _remember(X01Match m) {
    _lastSerial = m.visitSerial;
    _lastCurrent = m.current;
    _lastPhysical = m.physicalDartsInVisit;
  }
}
