import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../games/domain/engine/game_display.dart';
import '../../games/domain/engine/game_session.dart';
import '../../games/domain/engine/training_game.dart';
import '../../games/presentation/active_game_controller.dart';
import '../caller.dart';
import '../domain/training_call_planner.dart';

/// Verbindet das laufende Trainingsspiel mit dem [Caller]. Wird einmal in
/// der App-Wurzel aktiviert (wie das Dart-Feedback).
///
/// Angesagt wird nur bei Fortschritt: Spielstart („Game on“) und jede
/// abgeschlossene Aufnahme (3 Darts, Bust, Checkout oder Takeout).
/// Rückgängig und Korrekturen bauen das Spiel neu auf; das erkennt der Hook
/// am neuen Spielobjekt und sagt dann nichts an.
final trainingGameCallerProvider = Provider<void>((ref) {
  final tracker = _VisitTracker();
  ref.listen(activeGameProvider, (_, next) => tracker.onChange(next, ref.read(callerProvider)));
});

class _VisitTracker {
  GameSession? _session;
  TrainingGame? _game;
  bool _callable = false;

  /// Index der zuletzt angesagten Aufnahme, -1 = keine.
  int _announced = -1;

  /// Anzeige vor der laufenden Aufnahme.
  GameDisplay? _before;

  void onChange(ActiveGame? next, Caller caller) {
    if (next == null) {
      if (_session != null) unawaited(caller.stop());
      _session = null;
      _game = null;
      return;
    }
    final game = next.game;
    if (!identical(next.session, _session)) {
      _session = next.session;
      _game = game;
      _callable = TrainingCallPlanner.isCallable(game);
      _announced = -1;
      _before = game.display;
      if (_callable && !next.ended) unawaited(caller.gameOn());
      return;
    }
    if (!_callable) return;
    final closed = game.visitClosed || game.finished;
    if (!identical(game, _game)) {
      // Rückgängig/Korrektur: neu synchronisieren, nichts ansagen.
      _game = game;
      _announced = closed ? game.visitIndex : -1;
      if (closed) _before = game.display;
      return;
    }
    // Vorzeitig beendet: keine Ansage mehr.
    if (next.ended && !game.finished) return;
    if (!closed || game.visitIndex == _announced) return;
    _announced = game.visitIndex;
    unawaited(caller.announce(TrainingCallPlanner.forVisit(game, before: _before ?? game.display)));
    _before = game.display;
  }
}
