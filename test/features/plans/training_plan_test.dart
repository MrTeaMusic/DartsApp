import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/plans/domain/builtin_plans.dart';
import 'package:dartlab/features/plans/domain/training_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlanStep', () {
    test('JSON hin und zurück, leerer Hinweis fällt weg', () {
      const step = PlanStep(gameId: 'bull_drill', config: {'visits': 3}, note: 'locker');
      final list = PlanStep.decodeList(PlanStep.encodeList([step, const PlanStep(gameId: 'checkout', note: '')]));
      expect(list.first, step);
      expect(list.last.note, isNull);
      expect(list.last.config, isEmpty);
      expect(list.last.toJson().containsKey('note'), isFalse);
    });

    test('kaputte oder fremde Einträge werden übersprungen statt zu crashen', () {
      expect(PlanStep.decodeList('kein json'), isEmpty);
      expect(PlanStep.decodeList('{"gameId":"x"}'), isEmpty);
      final list = PlanStep.decodeList('[{"gameId":"bull_drill"}, {"config":{}}, 7, {"gameId":"x01","config":{"start":501}}]');
      expect(list.map((s) => s.gameId), ['bull_drill', 'x01']);
    });

    test('unbekanntes Spiel ist nicht verfügbar, Config bleibt erhalten', () {
      const step = PlanStep(gameId: 'game_from_the_future', config: {'a': 1});
      expect(step.available, isFalse);
      expect(step.definition, isNull);
      expect(step.resolvedConfig, {'a': 1});
      const plan = TrainingPlan(id: 'x', name: 'X', steps: [step]);
      expect(plan.playable, isFalse);
      expect(plan.availableSteps, 0);
    });

    test('resolvedConfig füllt Standardwerte auf', () {
      const step = PlanStep(gameId: 'bull_drill');
      expect(step.resolvedConfig, {'visits': 10});
    });
  });

  group('StepResult', () {
    test('JSON hin und zurück', () {
      const r = StepResult(step: 2, status: StepStatus.aborted, sessionUid: 'abc', darts: 9, summary: [('points', '150')]);
      final back = StepResult.decodeList(StepResult.encodeList([r])).single;
      expect(back.step, 2);
      expect(back.status, StepStatus.aborted);
      expect(back.sessionUid, 'abc');
      expect(back.darts, 9);
      expect(back.summary, [('points', '150')]);
      expect(StepResult.decodeList('[{"status":"done"}]'), isEmpty);
    });
  });

  group('Feste Pläne', () {
    test('stabile, eindeutige IDs und mindestens sechs Pläne', () {
      final ids = BuiltinPlans.all.map((p) => p.id).toList();
      expect(ids.length, greaterThanOrEqualTo(6));
      expect(ids.toSet(), hasLength(ids.length));
      for (final p in BuiltinPlans.all) {
        expect(TrainingPlan.isBuiltinId(p.id), isTrue);
        expect(p.builtIn, isTrue);
        expect(p.name, isNotEmpty);
        expect(p.description, isNotEmpty);
        expect(p.steps, isNotEmpty);
        expect(BuiltinPlans.byId(p.id), same(p));
      }
    });

    test('nutzen nur vorhandene Spiele und gültige Optionen', () {
      for (final p in BuiltinPlans.all) {
        for (final s in p.steps) {
          final def = GameCatalog.byId(s.gameId);
          expect(def, isNotNull, reason: '${p.id}: ${s.gameId}');
          final keys = def!.options.map((o) => o.key).toSet();
          expect(keys, containsAll(s.config.keys), reason: '${p.id}: ${s.gameId} ${s.config}');
          // Lässt sich starten.
          expect(() => def.start(s.config, 1), returnsNormally);
        }
      }
    });
  });

  test('Namen werden gekürzt', () {
    expect(TrainingPlan.cleanName('  Abend  '), 'Abend');
    expect(TrainingPlan.cleanName('x' * 80), hasLength(TrainingPlan.maxNameLength));
  });
}
