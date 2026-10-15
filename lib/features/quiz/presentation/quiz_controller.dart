import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/domain/segment.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/quiz_repository.dart';
import '../domain/quiz_config.dart';
import '../domain/quiz_run.dart';
import '../domain/quiz_scheduler.dart';

/// Uhr des Quiz (in Tests überschreibbar).
final quizClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Neue Bestwerte eines Durchgangs.
enum QuizRecord { timedCorrect, bestStreak, fastest }

/// Stand des laufenden Quiz für die Anzeige. [version] ändert sich mit
/// jeder Eingabe, weil [run] selbst veränderlich ist.
class QuizState {
  const QuizState({
    required this.run,
    required this.version,
    required this.bestsBefore,
    this.records = const {},
    this.sessionId,
  });

  final QuizRun run;
  final int version;

  /// Bestwerte vor diesem Durchgang.
  final QuizBests bestsBefore;

  /// Nach dem Ende: im Durchgang erreichte neue Bestwerte.
  final Set<QuizRecord> records;

  /// Gespeicherte Session (nach dem Ende, mit mindestens einer Antwort).
  final int? sessionId;

  QuizState copyWith({Set<QuizRecord>? records, int? sessionId}) => QuizState(
        run: run,
        version: version + 1,
        bestsBefore: bestsBefore,
        records: records ?? this.records,
        sessionId: sessionId ?? this.sessionId,
      );
}

/// Steuert einen Quiz-Durchgang: Eingaben, Uhr im Modus Zeit und Speichern
/// am Ende.
class QuizController extends Notifier<QuizState?> {
  Timer? _timer;
  int _playerId = 0;
  int _lastSecond = -1;
  Future<void>? _saving;

  @override
  QuizState? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// Startet einen Durchgang. [seed] macht die Fragen in Tests
  /// vorhersagbar.
  Future<void> start(QuizConfig config, {int? seed}) async {
    _timer?.cancel();
    _playerId = await ref.read(profileRepositoryProvider).resolve(ref.read(activePlayerIdProvider));
    final loaded = await ref.read(quizRepositoryProvider).load(_playerId);
    final scheduler = QuizScheduler(
      pool: config.pool(),
      history: loaded.history,
      random: math.Random(seed ?? DateTime.now().microsecondsSinceEpoch),
    );
    final run = QuizRun(config: config, scheduler: scheduler, clock: ref.read(quizClockProvider));
    _saving = null;
    _lastSecond = -1;
    state = QuizState(run: run, version: 0, bestsBefore: loaded.bests);
    if (run.ended) {
      unawaited(_save());
    } else if (config.timed) {
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => tick());
    }
  }

  void _changed() {
    final s = state;
    if (s != null) state = s.copyWith();
  }

  void _act(void Function(QuizRun run) action) {
    final run = state?.run;
    if (run == null || run.ended) return;
    action(run);
    if (run.ended) {
      unawaited(_save());
    }
    _changed();
  }

  void tap(Segment s) => _act((r) => r.tap(s));
  void undo() => _act((r) => r.undo());
  void clearInput() => _act((r) => r.clearInput());
  void submit() => _act((r) => r.phase == QuizPhase.setup ? r.submitSetup() : r.submitRoute());
  void impossible() => _act((r) => r.declareImpossible());
  void next() => _act((r) => r.next());

  /// Uhr im Modus Zeit; aktualisiert die Anzeige einmal je Sekunde.
  @visibleForTesting
  void tick() {
    final run = state?.run;
    if (run == null || run.ended) return;
    if (run.tick()) {
      _timer?.cancel();
      unawaited(_save());
      _changed();
      return;
    }
    final second = run.remainingTime()?.inSeconds ?? -1;
    if (second != _lastSecond) {
      _lastSecond = second;
      _changed();
    }
  }

  /// „Beenden“: Durchgang abschließen und speichern.
  Future<void> finish() async {
    final run = state?.run;
    if (run == null) return;
    if (!run.ended) {
      run.finish();
      _timer?.cancel();
      _changed();
    }
    await _save();
  }

  /// Quiz verlassen (speichert einen offenen Durchgang).
  Future<void> close() async {
    await finish();
    _timer?.cancel();
    state = null;
  }

  Future<void> _save() => _saving ??= _doSave();

  Future<void> _doSave() async {
    final s = state;
    if (s == null) return;
    final run = s.run;
    final id = await ref.read(quizRepositoryProvider).save(
          playerId: _playerId,
          config: run.config,
          answers: List.of(run.answers),
          startedAt: run.startedAt,
          endedAt: run.endedAt ?? DateTime.now(),
          finished: run.completed,
        );
    final records = _records(run, s.bestsBefore);
    if (state?.run == run) state = state!.copyWith(records: records, sessionId: id);
  }

  static Set<QuizRecord> _records(QuizRun run, QuizBests before) {
    final sum = run.summary;
    if (sum.answered == 0) return const {};
    return {
      if (run.config.timed && run.completed && sum.correct > 0 && sum.correct > (before.timedCorrect ?? 0))
        QuizRecord.timedCorrect,
      if (sum.bestStreak >= 3 && sum.bestStreak > (before.bestStreak ?? 0)) QuizRecord.bestStreak,
      if (sum.answered >= QuizBests.minAnswersForPace &&
          (sum.rate ?? 0) >= 0.5 &&
          sum.averageSeconds != null &&
          (before.fastestSeconds == null || sum.averageSeconds! < before.fastestSeconds!))
        QuizRecord.fastest,
    };
  }
}

final quizProvider = NotifierProvider<QuizController, QuizState?>(QuizController.new);
