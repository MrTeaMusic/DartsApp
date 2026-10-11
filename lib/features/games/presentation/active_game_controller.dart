import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dart_source/data/local_dart_source.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../dart_source/presentation/dart_source_providers.dart';
import '../data/game_repository.dart';
import '../domain/engine/game_definition.dart';
import '../domain/engine/game_display.dart';
import '../domain/engine/game_session.dart';
import '../domain/engine/training_game.dart';

/// Das laufende Spiel. Wird bei jeder Änderung neu erzeugt, damit Riverpod
/// neu zeichnet; die [session] selbst ist veränderlich.
@immutable
class ActiveGame {
  const ActiveGame({
    required this.session,
    required this.playerId,
    required this.revision,
    required this.sessionId,
    this.events = const [],
    this.ended = false,
  });

  final GameSession session;
  final int playerId;
  final int sessionId;

  /// Ereignisse der letzten Eingabe (für Banner).
  final List<GameEvent> events;
  final int revision;

  /// Beendet (regulär oder abgebrochen) und gespeichert.
  final bool ended;

  TrainingGame get game => session.game;
  String get gameId => session.definition.id;

  ActiveGame copyWith({List<GameEvent>? events, bool? ended}) => ActiveGame(
        session: session,
        playerId: playerId,
        sessionId: sessionId,
        revision: revision + 1,
        events: events ?? this.events,
        ended: ended ?? this.ended,
      );
}

final activeGameProvider = NotifierProvider<ActiveGameController, ActiveGame?>(ActiveGameController.new);

/// Verbindet die aktive [DartSource] mit dem laufenden Spiel und speichert
/// jeden Dart in der Datenbank.
class ActiveGameController extends Notifier<ActiveGame?> {
  Future<void> _writes = Future.value();

  @override
  ActiveGame? build() {
    ref.listen(dartEventsProvider, (_, next) {
      final event = next.value;
      if (event != null) handle(event);
    });
    return null;
  }

  GameRepository get _repo => ref.read(gameRepositoryProvider);

  /// Wartet, bis alle Schreibvorgänge erledigt sind (für Tests).
  @visibleForTesting
  Future<void> get pendingWrites => _writes;

  /// Startet ein neues Spiel. Ein noch laufendes wird vorher gespeichert.
  Future<void> start(GameDefinition definition, Map<String, Object?> config, {int? seed}) async {
    if (state != null && !state!.ended) await end();
    final session = GameSession(
      definition: definition,
      config: config,
      seed: seed ?? math.Random().nextInt(1 << 31),
    );
    final playerId = await _repo.defaultPlayerId();
    final id = await _repo.startSession(
      playerId: playerId,
      gameId: definition.id,
      config: session.config,
      seed: session.seed,
    );
    final source = ref.read(dartSourceProvider);
    if (source is LocalDartSource) source.resetVisit();
    state = ActiveGame(session: session, playerId: playerId, sessionId: id, revision: 0);
  }

  @visibleForTesting
  void handle(DartEvent event) {
    final current = state;
    if (current == null || current.ended) return;
    final session = current.session;
    switch (event) {
      case DartThrown(:final dart):
        session.addDart(dart);
        _persistLast(current);
        _afterInput(current);
        _maybeReleaseVisit();
      case DartCorrected(:final index, :final dart):
        if (session.correctDart(index, dart)) {
          _persistAll(current);
          _afterInput(current);
        }
      case DartUndone():
        if (session.undoLastDart()) {
          _persistAll(current);
          _afterInput(current);
        }
      case TakeoutFinished() || TurnReset():
        session.endVisit();
        // Ein Takeout ohne eigene Ereignisse lässt das Banner des letzten
        // Darts stehen (z. B. „Checkout“), statt es sofort zu löschen.
        _afterInput(current, keepEvents: current.session.game.events.isEmpty);
      case TakeoutStarted():
        break;
    }
  }

  /// Letzten Dart zurücknehmen. Bei lokalen Quellen über die Quelle, damit
  /// deren Aufnahme synchron bleibt.
  void undo() {
    final source = ref.read(dartSourceProvider);
    if (source is LocalDartSource && source.undoLast()) return;
    handle(DartUndone(DateTime.now()));
  }

  /// Nächste Aufnahme (Takeout) auslösen.
  void nextVisit() {
    final source = ref.read(dartSourceProvider);
    if (source is LocalDartSource) {
      source.finishTakeout();
    } else {
      handle(TakeoutFinished(DateTime.now()));
    }
  }

  /// Spiel beenden und speichern (auch vorzeitig).
  Future<void> end() async {
    final current = state;
    if (current == null || current.ended) return;
    state = current.copyWith(ended: true, events: const []);
    await _save(current);
  }

  /// Spielansicht verlassen.
  Future<void> close() async {
    await end();
    state = null;
  }

  void _afterInput(ActiveGame current, {bool keepEvents = false}) {
    final game = current.session.game;
    final finished = game.finished;
    final latest = state ?? current;
    state = latest.copyWith(events: keepEvents ? latest.events : List.of(game.events), ended: finished);
    if (finished) unawaited(_save(current));
  }

  /// Hat das Spiel die Aufnahme vorzeitig beendet (Bust, Checkout), gibt eine
  /// lokale Quelle die Aufnahme frei, damit der nächste Dart sofort zählt.
  /// Bei Autodarts entscheidet der echte Takeout.
  void _maybeReleaseVisit() {
    final game = state?.game;
    if (game == null || game.finished || !game.visitClosed) return;
    if (game.physicalDartsInVisit >= TrainingGame.dartsPerVisit) return;
    final source = ref.read(dartSourceProvider);
    if (source is LocalDartSource) scheduleMicrotask(source.finishTakeout);
  }

  void _persistLast(ActiveGame current) {
    final record = current.session.records.last;
    final seq = current.session.records.length - 1;
    _enqueue(current, (id) => _repo.addThrow(
          sessionId: id,
          playerId: current.playerId,
          gameId: current.gameId,
          seq: seq,
          visitIndex: record.visitIndex,
          counted: record.counted,
          dart: record.dart,
        ));
  }

  void _persistAll(ActiveGame current) {
    final records = current.session.records;
    _enqueue(current, (id) => _repo.replaceThrows(
          sessionId: id,
          playerId: current.playerId,
          gameId: current.gameId,
          darts: [for (final r in records) (dart: r.dart, visitIndex: r.visitIndex, counted: r.counted)],
        ));
  }

  Future<void> _save(ActiveGame current) {
    final game = current.session.game;
    return _enqueue(current, (id) => _repo.endSession(id, result: game.result, finished: game.finished));
  }

  /// Schreibvorgänge strikt nacheinander.
  Future<void> _enqueue(ActiveGame current, Future<Object?> Function(int sessionId) write) {
    final id = current.sessionId;
    _writes = _writes.then((_) async {
      try {
        await write(id);
      } catch (e, st) {
        debugPrint('Speichern fehlgeschlagen: $e\n$st');
      }
    });
    return _writes;
  }
}
