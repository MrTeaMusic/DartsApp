import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../dart_source/data/autodarts_local_source.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../dart_source/domain/dart_source.dart';
import '../../dart_source/presentation/dart_source_providers.dart';
import '../../games/data/game_repository.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../../games/presentation/active_game_controller.dart';
import '../../matches/presentation/match_controller.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/active_player.dart';
import '../domain/live_recorder.dart';
import '../domain/live_stats.dart';
import '../domain/live_x01.dart';

/// Was der Live-Bildschirm anzeigt.
@immutable
class LiveViewState {
  const LiveViewState({
    this.listening = false,
    this.current = const [],
    this.lastVisit,
    this.recentVisits = const [],
    this.stats = LiveStats.empty,
    this.sessionStartedAt,
    this.sessionCount = 0,
    this.dartSerial = 0,
    this.ended = false,
    this.x01Config,
    this.x01,
  });

  /// Die aktive Quelle ist Autodarts (lokal), DartLab hört mit.
  final bool listening;

  /// Darts der laufenden Aufnahme.
  final List<DartThrow> current;

  /// Zuletzt abgeschlossene Aufnahme (bis der nächste Dart kommt).
  final List<DartThrow>? lastVisit;

  /// Abgeschlossene Aufnahmen der Session, neueste zuerst (begrenzt).
  final List<List<DartThrow>> recentVisits;
  final LiveStats stats;

  /// Erster Dart der laufenden Session.
  final DateTime? sessionStartedAt;

  /// Begonnene Sessions seit dem Öffnen (mehr als eine nach langer Pause).
  final int sessionCount;

  /// Zählt neue Darts (für die Trefferanimation).
  final int dartSerial;

  /// „Beenden“ gedrückt, alles gespeichert.
  final bool ended;

  /// „X01 mitzählen“: Einstellungen, `null` = aus.
  final LiveX01Config? x01Config;

  /// Stand von „X01 mitzählen“ (nur wenn an).
  final LiveX01? x01;
}

/// Pause, nach der eine neue Session beginnt. In Tests überschreibbar.
final livePauseLimitProvider = Provider<Duration>((ref) => LiveRecorder.defaultPauseLimit);

/// Autodarts Live: schreibt die Darts vom eigenen Board mit, solange der
/// Bildschirm offen ist. Jede Öffnung ist eine eigene Session.
final autodartsLiveProvider =
    NotifierProvider.autoDispose<AutodartsLiveController, LiveViewState>(AutodartsLiveController.new);

typedef _Session = ({int id, int playerId, String gameId});

/// Verbindet die aktive Quelle mit dem [LiveRecorder] und speichert jeden
/// Dart sofort (wie die Spiele), damit auch beim Schließen der App nichts
/// verloren geht.
///
/// Garantiert passiv: Der Controller liest nur [DartSource.events] und
/// schaltet eine [AutodartsLocalSource] auf [AutodartsLocalSource.listenOnly],
/// damit auch von anderer Stelle kein Befehl an den Board Manager geht,
/// solange mitgeschrieben wird.
class AutodartsLiveController extends Notifier<LiveViewState> {
  /// So oft wird die laufende Session höchstens als abgeschlossen
  /// zwischengespeichert (Ende, Dartzahl, Kennzahlen). Würfe selbst werden
  /// immer sofort gespeichert.
  static const Duration checkpointInterval = Duration(minutes: 2);

  static const int recentLimit = 8;

  /// Letzte Wahl von „X01 mitzählen“, z. B. `501;double` oder `off`.
  static const String x01PrefsKey = 'live.x01';

  late LiveRecorder _recorder;
  late GameRepository _repo;
  late ProfileRepository _profiles;
  Future<void> _writes = Future.value();
  Future<_Session>? _session;
  DateTime? _lastCheckpoint;
  StreamSubscription<DartEvent>? _sub;
  void Function()? _release;
  bool _ended = false;
  bool _built = false;
  int _serial = 0;
  LiveX01Config? _x01Config;
  LiveX01? _x01;
  final List<LegMark> _marks = [];

  @override
  LiveViewState build() {
    _recorder = LiveRecorder(pauseLimit: ref.read(livePauseLimitProvider));
    _repo = ref.read(gameRepositoryProvider);
    _profiles = ref.read(profileRepositoryProvider);
    _ended = false;
    _built = false;
    _x01Config = decodeX01(ref.read(sharedPreferencesProvider).getString(x01PrefsKey));
    _replayX01();
    ref.listen<DartSource>(dartSourceProvider, (_, source) => _attach(source), fireImmediately: true);
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _sub = null;
      _release?.call();
      _release = null;
      unawaited(_finish());
    });
    // Sessions, die beim letzten Mal nicht sauber beendet wurden.
    _enqueue(() => repairLiveSessions(_repo.db));
    _built = true;
    return _view();
  }

  /// Wartet, bis alle Schreibvorgänge erledigt sind (für Tests).
  @visibleForTesting
  Future<void> get pendingWrites => _writes;

  static LiveX01Config? decodeX01(String? text) {
    if (text == null || text == 'off') return null;
    final [score, out, ...] = '$text;'.split(';');
    return LiveX01Config(
      startScore: int.tryParse(score) ?? 501,
      outMode: OutMode.values.where((o) => o.name == out).firstOrNull ?? OutMode.double,
    );
  }

  static String encodeX01(LiveX01Config? c) => c == null ? 'off' : '${c.startScore};${c.outMode.name}';

  void _attach(DartSource source) {
    unawaited(_sub?.cancel());
    _sub = null;
    _release?.call();
    _release = null;
    if (source.kind == DartSourceKind.autodartsLocal) {
      if (source is AutodartsLocalSource) _release = source.holdListenOnly();
      _sub = source.events.listen(_onEvent);
    }
    // Beim ersten Aufruf (aus build) setzt build den Zustand selbst.
    if (_built) state = _view();
  }

  /// Läuft gerade ein Trainingsspiel oder Match? Dann gehören die Darts
  /// dorthin und werden hier nicht doppelt gezählt.
  bool _otherGameRunning() {
    if (ref.exists(activeGameProvider)) {
      final game = ref.read(activeGameProvider);
      if (game != null && !game.ended) return true;
    }
    if (ref.exists(matchControllerProvider)) {
      final match = ref.read(matchControllerProvider);
      if (match != null && !match.ended) return true;
    }
    return false;
  }

  void _onEvent(DartEvent event) {
    if (_ended || _otherGameRunning()) return;
    final update = _recorder.apply(event);
    if (!update.changed) return;

    if (update.closedSession case final closed?) {
      // Lange Pause: alte Session abschließen, der neue Dart beginnt die nächste.
      _closeSession(closed);
    }
    _replayX01();

    if (update.added case final added?) {
      _serial++;
      final session = _session ??= _startSession(added.dart.timestamp, ref.read(activePlayerIdProvider));
      final seq = _recorder.dartCount - 1;
      final counted = _countedAt(seq);
      _enqueue(() async {
        final s = await session;
        await _repo.addThrow(
          sessionId: s.id,
          playerId: s.playerId,
          gameId: s.gameId,
          seq: seq,
          visitIndex: added.visitIndex,
          counted: counted,
          dart: added.dart,
        );
      });
    }

    // Korrekturen; mit X01 kann sich auch „gezählt“ früherer Darts ändern.
    if (update.rewritten) _rewrite();

    if (update.visitClosed && _session != null && _recorder.dartCount > 0) {
      final at = _recorder.lastDartAt!;
      final last = _lastCheckpoint;
      if (last == null || at.difference(last) >= checkpointInterval) {
        _lastCheckpoint = at;
        _enqueueSave(_session!, _result(), at);
      }
    }

    state = _view();
  }

  bool _countedAt(int seq) {
    final x = _x01;
    return x == null || seq >= x.counted.length || x.counted[seq];
  }

  void _rewrite() {
    final session = _session;
    if (session == null) return;
    final darts = _recorder.darts;
    final flags = [for (var i = 0; i < darts.length; i++) _countedAt(i)];
    _enqueue(() async {
      final s = await session;
      await _repo.replaceThrows(
        sessionId: s.id,
        playerId: s.playerId,
        gameId: s.gameId,
        darts: [for (final (i, d) in darts.indexed) (dart: d.dart, visitIndex: d.visitIndex, counted: flags[i])],
      );
    });
  }

  /// Schließt die laufende Session mit ihren Darts [darts] ab.
  void _closeSession(List<RecordedDart> darts) {
    final old = _session;
    _session = null;
    _lastCheckpoint = null;
    if (old != null) {
      _enqueueSave(old, liveSessionResult(darts, _x01Config, [..._marks]), darts.isEmpty ? null : darts.last.dart.timestamp);
    }
    _marks.clear();
  }

  void _replayX01() {
    final c = _x01Config;
    _x01 = c == null ? null : replayLive(c, _recorder.darts, _marks, visitOpen: _recorder.currentVisit.isNotEmpty);
  }

  /// „X01 mitzählen“ ein-/ausschalten oder Startwert/Ausstieg ändern.
  /// Hat die Session schon Darts, beginnt mit dem nächsten Dart eine neue.
  void setX01(LiveX01Config? config) {
    if (config == _x01Config) return;
    if (_recorder.dartCount > 0) _closeSession(_recorder.startNewSession());
    _marks.clear();
    _x01Config = config;
    unawaited(ref.read(sharedPreferencesProvider).setString(x01PrefsKey, encodeX01(config)));
    _replayX01();
    state = _view();
  }

  /// „Leg verloren“ bzw. „Leg neu starten“ (nur mit X01 und Darts im Leg).
  void markLeg(LegMarkKind kind) {
    final x = _x01;
    if (_ended || x == null || x.legDarts == 0) return;
    _marks.add((at: _recorder.dartCount, kind: kind));
    _replayX01();
    if (_session case final session?) _enqueueSave(session, _result(), _recorder.lastDartAt);
    state = _view();
  }

  Future<_Session> _startSession(DateTime startedAt, int? preferredPlayer) {
    final done = Completer<_Session>();
    final x01 = _x01Config;
    final gameId = x01 == null ? autodartsLiveGameId : autodartsLiveX01GameId;
    _enqueue(() async {
      try {
        final playerId = await _profiles.resolve(preferredPlayer);
        final id = await _repo.startSession(
          playerId: playerId,
          gameId: gameId,
          config: {
            'source': DartSourceKind.autodartsLocal.name,
            'mode': 'listen',
            'pauseMinutes': _recorder.pauseLimit.inMinutes,
            if (x01 != null) 'x01': x01.toJson(),
          },
          seed: 0,
          startedAt: startedAt,
        );
        done.complete((id: id, playerId: playerId, gameId: gameId));
      } catch (e, st) {
        done.completeError(e, st);
        rethrow;
      }
    });
    return done.future;
  }

  /// Schließt die Session (Kennzahlen, Ende = letzter Dart). Ohne Würfe wird
  /// sie gelöscht (siehe [GameRepository.endSession]).
  void _enqueueSave(Future<_Session> session, GameResult result, DateTime? endedAt) {
    _enqueue(() async {
      final s = await session;
      await _repo.endSession(s.id, result: result, finished: true, endedAt: endedAt);
    });
  }

  GameResult _result() => liveSessionResult(_recorder.darts, _x01Config, _marks);

  /// „Beenden“: Session speichern, danach nichts mehr mitschreiben.
  Future<void> end() async {
    if (_ended) return _writes;
    _ended = true;
    await _finish();
    state = _view();
  }

  Future<void> _finish() {
    final session = _session;
    _session = null;
    if (session != null) _enqueueSave(session, _result(), _recorder.lastDartAt);
    return _writes;
  }

  LiveViewState _view() {
    final closed = _recorder.closedVisits;
    return LiveViewState(
      listening: _sub != null && !_ended,
      current: _recorder.currentVisit,
      lastVisit: _recorder.lastClosedVisit,
      recentVisits: [for (final v in closed.reversed.take(recentLimit)) v],
      stats: _recorder.stats,
      sessionStartedAt: _recorder.darts.firstOrNull?.dart.timestamp,
      sessionCount: _recorder.sessionCount,
      dartSerial: _serial,
      ended: _ended,
      x01Config: _x01Config,
      x01: _x01,
    );
  }

  /// Schreibvorgänge strikt nacheinander.
  void _enqueue(Future<void> Function() write) {
    _writes = _writes.then((_) async {
      try {
        await write();
      } catch (e, st) {
        debugPrint('Autodarts Live: Speichern fehlgeschlagen: $e\n$st');
      }
    });
  }
}

/// Aufnahmen aus den Darts einer Session (nach `visitIndex`).
List<List<LiveDart>> _visitsOf(Iterable<({LiveDart dart, int visitIndex})> darts) {
  final visits = <int, List<LiveDart>>{};
  for (final d in darts) {
    visits.putIfAbsent(d.visitIndex, () => []).add(d.dart);
  }
  final keys = visits.keys.toList()..sort();
  return [for (final k in keys) visits[k]!];
}

/// X01-Stand aus den Darts einer Session.
LiveX01 replayLive(LiveX01Config config, List<RecordedDart> darts, List<LegMark> marks, {required bool visitOpen}) =>
    LiveX01.replay(
      config,
      [
        for (final v in _visitsOf([for (final d in darts) (dart: (segment: d.dart.segment, position: null), visitIndex: d.visitIndex)]))
          [for (final d in v) d.segment],
      ],
      marks,
      visitOpen: visitOpen,
    );

/// Ergebnis einer Live-Session aus ihren Darts (Rohwerte, mit X01 auch
/// Legs, Checkouts und die Leg-Markierungen).
GameResult liveSessionResult(List<RecordedDart> darts, LiveX01Config? x01, List<LegMark> marks) {
  final raw = LiveStats.of(_visitsOf([
    for (final d in darts) (dart: (segment: d.dart.segment, position: d.dart.position), visitIndex: d.visitIndex),
  ]));
  return _combine(raw, x01 == null ? null : replayLive(x01, darts, marks, visitOpen: false), marks);
}

/// Ergebnis zum Speichern: ohne X01 die Rohwerte, mit X01 zusätzlich die
/// Kennzahlen wie beim Match und die Leg-Markierungen (für die Reparatur).
GameResult _combine(LiveStats raw, LiveX01? x01, List<LegMark> marks) {
  final plain = raw.toResult();
  if (x01 == null) return plain;
  final r = x01.result(plain.metrics);
  return GameResult(
    metrics: r.metrics,
    summary: const [],
    details: {
      ...r.details,
      'marks': [for (final m in marks) {'at': m.at, 'kind': m.kind.name}],
    },
  );
}

/// Schließt Live-Sessions ab, die nicht sauber beendet wurden (App
/// geschlossen, bevor die Session zwischengespeichert war): Ende, Dartzahl
/// und Kennzahlen kommen aus den gespeicherten Würfen. Gibt die Zahl der
/// reparierten Sessions zurück.
Future<int> repairLiveSessions(AppDatabase db) async {
  const ids = [autodartsLiveGameId, autodartsLiveX01GameId];
  final sessions = await (db.select(db.sessions)..where((s) => s.gameId.isIn(ids))).get();
  if (sessions.isEmpty) return 0;
  final count = db.throws.id.count();
  final counts = {
    for (final r in await (db.selectOnly(db.throws)
          ..addColumns([db.throws.sessionId, count])
          ..where(db.throws.gameId.isIn(ids))
          ..groupBy([db.throws.sessionId]))
        .get())
      r.read(db.throws.sessionId)!: r.read(count) ?? 0,
  };
  final repo = GameRepository(db);
  var repaired = 0;
  for (final s in sessions) {
    if (s.endedAt != null && s.dartCount == (counts[s.id] ?? 0)) continue;
    final rows = await repo.throwsOf(s.id);
    final darts = <RecordedDart>[
      for (final t in rows)
        (
          dart: DartThrow(
            segment: Segment.tryParse(t.segment) ?? Segment.miss,
            position: t.x == null || t.y == null ? null : BoardPoint(t.x!, t.y!),
            timestamp: t.timestamp,
            source: DartSourceKind.autodartsLocal,
          ),
          visitIndex: t.visitIndex,
        ),
    ];
    final x01 = s.gameId == autodartsLiveX01GameId
        ? LiveX01Config.fromJson(GameRepositoryJson.decode(s.configJson)['x01'])
        : null;
    final details = GameRepositoryJson.decode(s.resultJson)['details'];
    final marks = legMarksFromJson(details is Map ? details['marks'] : null);
    await repo.endSession(
      s.id,
      result: liveSessionResult(darts, x01, marks),
      finished: true,
      endedAt: rows.isEmpty ? null : rows.map((t) => t.timestamp).reduce((a, b) => a.isAfter(b) ? a : b),
    );
    repaired++;
  }
  return repaired;
}

/// JSON aus der Datenbank lesen, ohne bei kaputten Daten abzubrechen.
abstract final class GameRepositoryJson {
  static Map<String, Object?> decode(String? json) {
    if (json == null) return const {};
    try {
      final v = jsonDecode(json);
      return v is Map<String, Object?> ? v : const {};
    } on FormatException {
      return const {};
    }
  }
}
