import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/domain/segment.dart';
import '../../dart_source/data/local_dart_source.dart';
import '../../dart_source/data/manual_source.dart';
import '../../dart_source/data/simulator_source.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../dart_source/presentation/dart_source_providers.dart';
import '../../games/data/game_repository.dart';
import '../../games/presentation/active_game_controller.dart';
import '../../profiles/data/profile_repository.dart';
import '../data/match_store.dart';
import '../domain/dart_bot.dart';
import '../domain/match_result.dart';
import '../domain/match_session.dart';
import '../domain/x01_match.dart';
import 'tournament_controller.dart';

/// Wie schnell der Bot wirft. In Tests überschreibbar.
class BotTiming {
  const BotTiming({
    this.firstDart = const Duration(milliseconds: 1200),
    this.betweenDarts = const Duration(milliseconds: 850),
    this.takeout = const Duration(milliseconds: 1600),
  });

  /// Pause vor dem ersten Dart einer Aufnahme (Gegner tritt ans Board).
  final Duration firstDart;
  final Duration betweenDarts;

  /// Wie lange die Bot-Darts nach der Aufnahme stehen bleiben.
  final Duration takeout;
}

final botTimingProvider = Provider<BotTiming>((ref) => const BotTiming());

/// Zufall der Bots. In Tests mit festem Startwert überschreibbar.
final botRandomProvider = Provider<math.Random>((ref) => math.Random());

/// Das laufende Match. Wird bei jeder Änderung neu erzeugt, die [session]
/// selbst ist veränderlich.
@immutable
class MatchState {
  const MatchState({required this.session, required this.revision, this.events = const [], this.ended = false});

  final MatchSession session;
  final int revision;

  /// Ereignisse der letzten Eingabe (für das Banner).
  final List<MatchEvent> events;

  /// Beendet und gespeichert.
  final bool ended;

  X01Match get match => session.match;
  MatchSetup get setup => session.setup;
  bool get finished => match.finished;

  /// Wirft gerade ein Mensch?
  bool get humanTurn => !finished && !setup.players[match.current].isBot;

  /// Zählt ein weiterer Dart vom Board für einen Menschen? Nicht, wenn die
  /// Aufnahme voll ist und als Nächstes der Bot wirft.
  bool get acceptsHumanDarts => humanTurn && !(match.visitClosed && setup.players[match.nextPlayer].isBot);

  MatchState copyWith({List<MatchEvent>? events, bool? ended}) =>
      MatchState(session: session, revision: revision + 1, events: events ?? this.events, ended: ended ?? this.ended);
}

final matchControllerProvider = NotifierProvider<MatchController, MatchState?>(MatchController.new);

/// Verbindet die Dart-Quelle mit dem laufenden Match, lässt Bots werfen und
/// speichert die Würfe der Menschen (mit Profil) in der Datenbank.
class MatchController extends Notifier<MatchState?> {
  Timer? _botTimer;
  final Map<int, DartBot> _bots = {};
  final Map<int, int> _sessionIds = {};
  Future<void> _writes = Future.value();

  @override
  MatchState? build() {
    ref.listen(dartEventsProvider, (_, next) {
      final event = next.value;
      if (event != null) handle(event);
    });
    ref.onDispose(() => _botTimer?.cancel());
    return null;
  }

  GameRepository get _repo => ref.read(gameRepositoryProvider);
  MatchStore get _store => ref.read(matchStoreProvider);

  /// Wartet, bis alle Schreibvorgänge erledigt sind (für Tests).
  @visibleForTesting
  Future<void> get pendingWrites => _writes;

  /// Startet ein Match, auf Wunsch als Fortsetzung eines gespeicherten.
  Future<void> start(MatchSetup setup, {SavedMatch? resume}) async {
    await close(keepForResume: state?.setup.tournamentMatch != null);
    // Ein offenes Trainingsspiel würde die Darts sonst mitzählen.
    await ref.read(activeGameProvider.notifier).close();
    final session = resume == null ? MatchSession(setup) : MatchSession.restore(setup, resume.inputs);
    final random = ref.read(botRandomProvider);
    _bots.clear();
    for (var i = 0; i < setup.players.length; i++) {
      final p = setup.players[i];
      if (p.isBot) _bots[i] = DartBot.forAverage(p.botAverage ?? 50, random: random);
    }
    await _openSessions(session, resume);
    _resetLocalSource();
    state = MatchState(session: session, revision: 0);
    _saveProgress();
    _scheduleBot();
  }

  Future<void> _openSessions(MatchSession session, SavedMatch? resume) async {
    _sessionIds.clear();
    final profiles = {for (final p in await ref.read(profileRepositoryProvider).players()) p.id};
    final setup = session.setup;
    for (var i = 0; i < setup.players.length; i++) {
      final p = setup.players[i];
      // Eine beim Unterbrechen gespeicherte Teil-Session wird ersetzt, damit
      // keine Darts doppelt zählen. Gelöscht wird mit Markierung, sonst käme
      // sie über den Abgleich zurück.
      final old = resume?.sessionIds[i];
      if (old != null) await _repo.deleteSession(old);
      if (p.isBot || p.profileId == null || !profiles.contains(p.profileId)) continue;
      final id = await _repo.startSession(
        playerId: p.profileId!,
        gameId: matchGameId,
        config: {
          ...setup.format.toJson(),
          'opponents': [
            for (var j = 0; j < setup.players.length; j++)
              if (j != i) setup.players[j].name,
          ],
          'vsBot': setup.hasBot,
          if (setup.tournamentMatch != null) 'tournament': true,
        },
        seed: 0,
      );
      _sessionIds[i] = id;
    }
    if (resume != null) {
      for (final i in _sessionIds.keys) {
        await _writeAll(session, i, _sessionIds[i]!);
      }
    }
  }

  void _resetLocalSource() {
    final source = ref.read(dartSourceProvider);
    if (source is LocalDartSource) source.resetVisit();
  }

  @visibleForTesting
  void handle(DartEvent event) {
    final s = state;
    if (s == null || s.ended || s.finished) return;
    final session = s.session;
    final m = s.match;
    final ownerIsBot = s.setup.players[m.current].isBot;
    switch (event) {
      case DartThrown(:final dart):
        if (ownerIsBot) {
          // Der Mensch wirft schon, während die Bot-Darts noch stecken.
          if (!m.visitClosed || s.setup.players[m.nextPlayer].isBot) return;
          _botTimer?.cancel();
          session.endVisit();
        } else if (m.visitClosed &&
            m.physicalDartsInVisit >= X01Match.dartsPerVisit &&
            s.setup.players[m.nextPlayer].isBot) {
          // Vergessener Takeout vor dem Bot: Aufnahme beenden, der Dart
          // gehört nicht dem Bot.
          if (session.endVisit()) _after(s);
          return;
        }
        session.addDart(dart);
        _persistLast(session);
        _after(s);
        _releaseVisit(session);
      case DartCorrected(:final index, :final dart):
        if (ownerIsBot) return;
        final visit = session.currentVisitIndexes;
        if (index < 0 || index >= visit.length) return;
        if (session.correctAt(visit[index], dart)) {
          _persistAll(session);
          _after(s);
        }
      case DartUndone():
        if (ownerIsBot) return;
        if (session.undoLastDart()) {
          _persistAll(session);
          _after(s);
        }
      case TakeoutFinished() || TurnReset():
        if (ownerIsBot) return;
        if (session.endVisit()) _after(s, keepEvents: m.events.isEmpty);
      case TakeoutStarted():
        break;
    }
  }

  /// Ist die Aufnahme eines Menschen vorbei, schaltet eine lokale Quelle
  /// weiter, damit der nächste Spieler sofort werfen kann. Der Simulator
  /// macht das nach drei Darts selbst; bei Autodarts entscheidet der echte
  /// Takeout.
  void _releaseVisit(MatchSession session) {
    final m = session.match;
    if (m.finished || !m.visitClosed) return;
    final source = ref.read(dartSourceProvider);
    final full = m.physicalDartsInVisit >= X01Match.dartsPerVisit;
    final release = switch (source) {
      SimulatorSource() => !full || !source.autoTakeout,
      ManualSource() => true,
      _ => false,
    };
    if (release && source is LocalDartSource) scheduleMicrotask(source.finishTakeout);
  }

  /// Letzten Dart zurücknehmen (nur eigene Darts der laufenden Aufnahme).
  void undo() {
    final s = state;
    if (s == null || !s.session.canUndo) return;
    final source = ref.read(dartSourceProvider);
    if (source is LocalDartSource && source.undoLast()) return;
    handle(DartUndone(DateTime.now()));
  }

  /// Korrigiert einen Dart eines Menschen. [index] zählt alle Darts des
  /// Matches (wie `session.records`).
  bool correct(int index, Segment segment) {
    final s = state;
    if (s == null || s.ended) return false;
    final records = s.session.records;
    if (index < 0 || index >= records.length) return false;
    final old = records[index].dart;
    if (old.segment == segment) return false;
    final dart = DartThrow(segment: segment, timestamp: old.timestamp, source: old.source, raw: old.raw);
    if (!s.session.correctAt(index, dart)) return false;
    _persistAll(s.session);
    _after(s);
    return true;
  }

  /// „Weiter“: Aufnahme des Menschen beenden.
  void nextVisit() {
    final s = state;
    if (s == null || !s.humanTurn) return;
    final source = ref.read(dartSourceProvider);
    if (source is LocalDartSource) {
      source.finishTakeout();
    } else {
      handle(TakeoutFinished(DateTime.now()));
    }
  }

  /// Match verlassen. Im Turnier bleibt es zum Fortsetzen gespeichert
  /// ([keepForResume]), sonst wird es verworfen. Die bisherigen Würfe zählen
  /// in der Statistik als abgebrochene Session.
  Future<void> close({bool keepForResume = false}) async {
    _botTimer?.cancel();
    final s = state;
    if (s == null) return;
    if (!s.ended) {
      if (keepForResume) {
        _saveProgress();
      } else {
        unawaited(_store.saveCurrentMatch(null));
      }
      await _endSessions(s, finished: false);
    }
    state = null;
  }

  void _after(MatchState s, {bool keepEvents = false}) {
    final m = s.session.match;
    final latest = state ?? s;
    final events = keepEvents ? latest.events : List.of(m.events);
    if (m.finished) {
      _botTimer?.cancel();
      state = latest.copyWith(events: events, ended: true);
      unawaited(_finish(s));
      return;
    }
    state = latest.copyWith(events: events);
    _saveProgress();
    _scheduleBot();
  }

  Future<void> _finish(MatchState s) async {
    unawaited(_store.saveCurrentMatch(null));
    final tm = s.setup.tournamentMatch;
    if (tm != null) await ref.read(tournamentControllerProvider.notifier).recordMatch(tm, s.match);
    await _endSessions(s, finished: true);
  }

  Future<void> _endSessions(MatchState s, {required bool finished}) {
    for (final e in _sessionIds.entries) {
      final result = matchResultFor(s.match, e.key, s.setup);
      final repo = _repo;
      _enqueue(() => repo.endSession(e.value, result: result, finished: finished));
    }
    return _writes;
  }

  void _saveProgress() {
    final s = state;
    if (s == null || s.ended) return;
    unawaited(
      _store.saveCurrentMatch(SavedMatch(setup: s.setup, inputs: s.session.inputs, sessionIds: Map.of(_sessionIds))),
    );
  }

  // --- Bot ---

  void _scheduleBot() {
    _botTimer?.cancel();
    _botTimer = null;
    final s = state;
    if (s == null || s.ended || s.finished) return;
    final m = s.match;
    if (!s.setup.players[m.current].isBot) return;
    final timing = ref.read(botTimingProvider);
    if (m.visitClosed) {
      _botTimer = Timer(timing.takeout, _botTakeout);
    } else {
      _botTimer = Timer(m.physicalDartsInVisit == 0 ? timing.firstDart : timing.betweenDarts, _botThrow);
    }
  }

  void _botThrow() {
    final s = state;
    if (s == null || s.ended || s.finished) return;
    final bot = _bots[s.match.current];
    if (bot == null) return;
    s.session.addDart(bot.next(s.match));
    _after(s);
  }

  void _botTakeout() {
    final s = state;
    if (s == null || s.ended || s.finished) return;
    if (!s.session.endVisit()) return;
    final nextIsHuman = !s.setup.players[s.match.current].isBot;
    _after(s, keepEvents: true);
    // Neue Aufnahme für den Menschen: die lokale Quelle beginnt leer.
    if (nextIsHuman) _resetLocalSource();
  }

  // --- Speichern ---

  void _persistLast(MatchSession session) {
    final record = session.records.last;
    final id = _sessionIds[record.player];
    if (id == null) return;
    final seq = session.records.where((r) => r.player == record.player).length - 1;
    final repo = _repo;
    _enqueue(
      () => repo.addThrow(
        sessionId: id,
        playerId: session.setup.players[record.player].profileId!,
        gameId: matchGameId,
        seq: seq,
        visitIndex: record.visitSerial,
        counted: record.counted,
        dart: record.dart,
      ),
    );
  }

  void _persistAll(MatchSession session) {
    final repo = _repo;
    for (final e in _sessionIds.entries) {
      _enqueue(() => _writeAll(session, e.key, e.value, repo: repo));
    }
  }

  Future<void> _writeAll(MatchSession session, int player, int sessionId, {GameRepository? repo}) =>
      (repo ?? _repo).replaceThrows(
        sessionId: sessionId,
        playerId: session.setup.players[player].profileId!,
        gameId: matchGameId,
        darts: [
          for (final r in session.records)
            if (r.player == player) (dart: r.dart, visitIndex: r.visitSerial, counted: r.counted),
        ],
      );

  Future<void> _enqueue(Future<Object?> Function() write) {
    _writes = _writes.then((_) async {
      try {
        await write();
      } catch (e, st) {
        debugPrint('Speichern fehlgeschlagen: $e\n$st');
      }
    });
    return _writes;
  }
}
