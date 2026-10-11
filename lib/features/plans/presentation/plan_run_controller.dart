import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../games/data/game_repository.dart';
import '../../games/domain/games/checkout/checkout_training.dart';
import '../../games/presentation/active_game_controller.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/plan_repository.dart';
import '../domain/training_plan.dart';

/// Der laufende Plan-Durchlauf und das Spiel des aktuellen Schritts.
@immutable
class PlanRunState {
  const PlanRunState({required this.run, this.stepIndex, this.sessionId, this.recorded = false});

  final PlanRun run;

  /// Schritt, der gerade gespielt wird (Index in `run.steps`).
  final int? stepIndex;

  /// Session des Spiels zu [stepIndex].
  final int? sessionId;

  /// Ergebnis des Schritts ist gespeichert.
  final bool recorded;

  int get total => run.steps.length;

  /// Ist [stepIndex] der letzte Schritt?
  bool get isLastStep => stepIndex != null && stepIndex! >= total - 1;
}

final planRunProvider = NotifierProvider<PlanRunController, PlanRunState?>(PlanRunController.new);

/// Spielt einen Trainingsplan Schritt für Schritt über den
/// [ActiveGameController]. Der Fortschritt steht in der Datenbank, damit
/// ein angefangener Plan später fortgesetzt werden kann.
///
/// Ein regulär beendetes Spiel zählt sofort als erledigt. Ein vorzeitig
/// beendetes zählt erst mit „Nächster Schritt“; wer stattdessen geht, spielt
/// den Schritt beim Fortsetzen noch einmal.
class PlanRunController extends Notifier<PlanRunState?> {
  Future<void> _pending = Future.value();

  @override
  PlanRunState? build() {
    ref.listen(activeGameProvider, (_, next) {
      final s = state;
      if (next == null || s == null || !next.ended || s.recorded) return;
      if (next.sessionId != s.sessionId || !next.game.finished) return;
      _pending = _record(next, StepStatus.done);
    });
    return null;
  }

  PlanRepository get _repo => ref.read(planRepositoryProvider);

  /// Wartet auf laufende Speichervorgänge (für Tests).
  @visibleForTesting
  Future<void> get pending => _pending;

  /// Gehört die Session zum laufenden Plan-Schritt?
  bool owns(ActiveGame? game) => game != null && state?.sessionId == game.sessionId;

  /// Startet den Plan (oder setzt den offenen Durchlauf fort) und das Spiel
  /// des nächsten Schritts. `false`, wenn kein Schritt mehr zu spielen war;
  /// der Durchlauf ist dann abgeschlossen.
  Future<bool> start(TrainingPlan plan, {bool resume = false}) async {
    final playerId = await ref.read(profileRepositoryProvider).resolve(ref.read(activePlayerIdProvider));
    final open = resume ? await _repo.openRun(plan.id, playerId: playerId) : null;
    final run = open ?? await _repo.startRun(plan, playerId: playerId);
    state = PlanRunState(run: run);
    return _startCurrent();
  }

  /// Nach dem Ende eines Spiels: Ergebnis sichern und den nächsten Schritt
  /// starten. `false`, wenn es keinen mehr gibt (dann [finish] aufrufen).
  Future<bool> next() async {
    await _recordIfNeeded();
    final s = state;
    if (s == null || s.run.allStepsDone) return false;
    return _startCurrent();
  }

  /// Schließt den Durchlauf ab und gibt seine ID für die Zusammenfassung
  /// zurück.
  Future<int?> finish() async {
    await _recordIfNeeded();
    final s = state;
    if (s == null) return null;
    final run = await _repo.finishRun(s.run.id);
    await ref.read(activeGameProvider.notifier).close();
    state = null;
    return run.id;
  }

  Future<void> _recordIfNeeded() async {
    await _pending;
    final s = state;
    final active = ref.read(activeGameProvider);
    if (s == null || s.recorded || !owns(active) || !active!.ended) return;
    _pending = _record(active, active.game.finished ? StepStatus.done : StepStatus.aborted);
    await _pending;
  }

  Future<void> _record(ActiveGame game, StepStatus status) async {
    final s = state;
    if (s == null || s.stepIndex == null) return;
    state = PlanRunState(run: s.run, stepIndex: s.stepIndex, sessionId: s.sessionId, recorded: true);
    final db = ref.read(appDatabaseProvider);
    final session = await (db.select(db.sessions)..where((x) => x.id.equals(game.sessionId))).getSingleOrNull();
    final run = await _repo.recordStep(
      s.run.id,
      StepResult(
        step: s.stepIndex!,
        status: status,
        sessionUid: session?.uid,
        darts: game.session.records.length,
        summary: [for (final stat in game.game.result.summary) (stat.key, stat.value)],
      ),
    );
    final now = state;
    if (now != null && now.run.id == run.id) {
      state = PlanRunState(run: run, stepIndex: now.stepIndex, sessionId: now.sessionId, recorded: now.recorded);
    }
  }

  /// Startet das Spiel des aktuellen Schritts. Schritte mit unbekanntem
  /// Spiel werden als „nicht verfügbar“ übersprungen.
  Future<bool> _startCurrent() async {
    var run = state!.run;
    while (!run.allStepsDone) {
      final index = run.currentStep;
      final step = run.steps[index];
      final def = step.definition;
      if (def == null) {
        run = await _repo.recordStep(run.id, StepResult(step: index, status: StepStatus.unavailable));
        state = PlanRunState(run: run);
        continue;
      }
      var config = step.resolvedConfig;
      if (def.id == CheckoutTraining.id && config['mode'] == 'weak') {
        final weak = await ref.read(gameRepositoryProvider).weakCheckoutTargets(playerId: run.playerId);
        config = {...config, 'weakTargets': weak};
      }
      final games = ref.read(activeGameProvider.notifier);
      await games.start(def, config);
      state = PlanRunState(run: run, stepIndex: index, sessionId: ref.read(activeGameProvider)?.sessionId);
      return true;
    }
    state = PlanRunState(run: run);
    return false;
  }
}
