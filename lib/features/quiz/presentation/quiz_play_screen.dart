import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/domain/engine/game_display.dart';
import '../domain/quiz_answer.dart';
import '../domain/quiz_run.dart';
import 'quiz_controller.dart';
import 'quiz_routes.dart';
import 'quiz_widgets.dart';

/// Das Quiz: Rest und Darts oben, Eingabe darunter, Tastenfeld unten
/// (Telefon) bzw. rechts (breite Fenster). Im Training folgt nach jeder
/// Antwort die Auflösung, im Modus Zeit sofort die nächste Frage.
class QuizPlayScreen extends ConsumerWidget {
  const QuizPlayScreen({super.key});

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final s = ref.read(quizProvider);
    if (s != null && !s.run.ended) {
      final l10n = context.l10n;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.quizLeaveTitle),
          content: Text(s.run.config.timed ? l10n.quizLeaveTimedText : l10n.quizLeaveText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.quizContinue)),
            FilledButton(
              key: const Key('quiz-confirm-end'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.quizFinish),
            ),
          ],
        ),
      );
      if (ok != true) return;
      // Erst das Ergebnis zeigen, verlassen dann über „Fertig“.
      await ref.read(quizProvider.notifier).finish();
      return;
    }
    await ref.read(quizProvider.notifier).close();
    if (context.mounted) context.go(QuizRoutes.setup);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(quizProvider);
    if (state == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: FilledButton(onPressed: () => context.go(QuizRoutes.setup), child: Text(l10n.quizTitle))),
      );
    }
    final run = state.run;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave(context, ref));
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('quiz-leave'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _leave(context, ref),
          ),
          title: Text(l10n.quizTitle, style: narrow ? Theme.of(context).textTheme.titleLarge : null),
          actions: [
            if (!run.ended) _ModePill(run: run),
            const SizedBox(width: AppSpacing.m),
          ],
        ),
        body: SafeArea(
          child: run.ended ? _ResultView(state: state) : _QuestionView(state: state),
        ),
      ),
    );
  }
}

/// Restzeit (Zeit) bzw. Modus (Training) oben rechts.
class _ModePill extends StatelessWidget {
  const _ModePill({required this.run});
  final QuizRun run;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final left = run.remainingTime();
    if (left == null) return StatusPill(label: l10n.quizModeTraining, color: Theme.of(context).colorScheme.primary);
    final s = (left.inMilliseconds / 1000).ceil();
    return StatusPill(
      key: const Key('quiz-timer'),
      label: '0:${s.toString().padLeft(2, '0')}',
      color: s <= 10 ? colors.danger : colors.warning,
      pulsing: s <= 10,
    );
  }
}

class _QuestionView extends ConsumerWidget {
  const _QuestionView({required this.state});
  final QuizState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = state.run;
    final ctrl = ref.read(quizProvider.notifier);
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final look = context.look;
      final feedback = run.phase == QuizPhase.feedback;
      final keypad = AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QuizKeypad(
              keyHeight: wide ? 52 : (c.maxHeight < 720 ? 38 : 42),
              enabled: !feedback,
              onPick: ctrl.tap,
              onUndo: ctrl.undo,
            ),
          ],
        ),
      );
      final actions = _Actions(run: run);
      if (wide) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(look.pagePadding(true), AppSpacing.l, AppSpacing.xl, AppSpacing.xl),
                    children: [
                      _StatsStrip(run: run),
                      SizedBox(height: look.gridGap),
                      _QuestionPanel(run: run, compact: false),
                      SizedBox(height: look.gridGap),
                      if (feedback)
                        AppCard(child: QuizFeedbackView(feedback: run.last!, out: run.config.out))
                      else
                        _Hint(run: run),
                    ],
                  ),
                ),
                SizedBox(
                  width: 420,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(0, AppSpacing.l, look.pagePadding(true), AppSpacing.xl),
                    children: [keypad, SizedBox(height: look.gridGap), actions],
                  ),
                ),
              ],
            ),
          ),
        );
      }
      // Telefon: alles ohne Scrollen, außer der Auflösung.
      final page = look.pagePadding(false);
      return ListView(
        key: const Key('quiz-phone'),
        padding: EdgeInsets.fromLTRB(page, AppSpacing.xs, page, page),
        children: [
          _StatsStrip(run: run),
          const SizedBox(height: AppSpacing.s),
          _QuestionPanel(run: run, compact: true),
          const SizedBox(height: AppSpacing.s),
          if (feedback) ...[
            AppCard(child: QuizFeedbackView(feedback: run.last!, out: run.config.out)),
            const SizedBox(height: AppSpacing.m),
            actions,
          ] else ...[
            _Hint(run: run),
            const SizedBox(height: AppSpacing.s),
            keypad,
            const SizedBox(height: AppSpacing.m),
            actions,
          ],
        ],
      );
    });
  }
}

/// Richtig, Serie und Durchschnittszeit des Durchgangs.
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.run});
  final QuizRun run;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final look = context.look;
    final s = run.summary;
    Widget item(String label, String value, {Key? key, Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Kicker(label),
              const SizedBox(height: AppSpacing.xxs),
              Text(value, key: key, style: look.chipNumber.copyWith(color: color ?? theme.colorScheme.onSurface)),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          item(l10n.quizStatCorrect, '${s.correct} / ${s.answered}', key: const Key('quiz-correct')),
          item(l10n.quizStatStreak, '${run.streak}',
              key: const Key('quiz-streak'), color: run.streak >= 3 ? context.dartColors.record : null),
          item(l10n.quizStatPace, s.averageSeconds == null ? '–' : '${formatDecimal(s.averageSeconds)} s'),
        ],
      ),
    );
  }
}

/// Rest, übrige Darts und die eingegebenen Felder.
class _QuestionPanel extends StatelessWidget {
  const _QuestionPanel({required this.run, required this.compact});
  final QuizRun run;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final q = run.question!;
    final setup = run.phase == QuizPhase.setup;
    final feedback = run.phase == QuizPhase.feedback;
    // In der Auflösung bleibt die Antwort stehen.
    final shown = feedback ? (run.last!.answer.impossible ? run.last!.answer.setup : run.last!.answer.route) : run.input;
    final sum = shown.fold<int>(0, (a, s) => a + s.score);
    final slots = Row(
      children: [
        for (var i = 0; i < q.darts; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.s),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: DartChip(
                key: Key('quiz-slot-$i'),
                segment: i < shown.length ? shown[i] : null,
                label: '${i + 1}',
              ),
            ),
          ),
        ],
      ],
    );
    return ScorePanel(
      label: setup ? l10n.quizSetupLabel : l10n.quizRemaining,
      trailing: quizDartsText(l10n, q.darts),
      value: Text('${q.score}', key: const Key('quiz-score'), style: ScorePanel.valueStyle(context, compact: compact)),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          slots,
          const SizedBox(height: AppSpacing.s),
          Text(
            shown.isEmpty ? ' ' : l10n.quizSum(sum, q.score - sum),
            key: const Key('quiz-sum'),
            style: theme.textTheme.bodyMedium?.copyWith(color: q.score - sum < 0 ? colors.danger : colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Hinweis zur Eingabe bzw. im Modus Zeit das Ergebnis der letzten Antwort.
class _Hint extends StatelessWidget {
  const _Hint({required this.run});
  final QuizRun run;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final last = run.last;
    if (run.phase == QuizPhase.setup) {
      return _line(context, Icons.check_circle_rounded, colors.success, l10n.quizSetupHint);
    }
    if (run.config.timed && last != null) {
      final a = last.answer;
      final q = last.question;
      final solution = q.recommended ?? q.setup?.darts;
      return Row(
        key: const Key('quiz-last'),
        children: [
          Icon(a.correct ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 20, color: a.correct ? colors.success : colors.danger),
          const SizedBox(width: AppSpacing.s),
          Text('${q.score}', style: context.look.chipNumber.copyWith(fontSize: 16, color: theme.colorScheme.onSurface)),
          const SizedBox(width: AppSpacing.s),
          if (!a.correct && solution != null)
            Expanded(child: RouteTags(solution))
          else
            Expanded(child: Text(a.correct ? l10n.quizCorrect : l10n.quizImpossible, style: theme.textTheme.bodyMedium)),
        ],
      );
    }
    return _line(context, Icons.touch_app_rounded, colors.textMuted, l10n.quizRouteHint);
  }

  Widget _line(BuildContext context, IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.dartColors.textMuted)),
          ),
        ],
      );
}

/// „Nicht möglich“ und „Prüfen“, in der Auflösung „Weiter“.
class _Actions extends ConsumerWidget {
  const _Actions({required this.run});
  final QuizRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ctrl = ref.read(quizProvider.notifier);
    if (run.phase == QuizPhase.feedback) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('quiz-finish'),
              onPressed: () => ctrl.finish(),
              child: Text(l10n.quizFinish),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              key: const Key('quiz-next'),
              onPressed: ctrl.next,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(l10n.quizNext),
            ),
          ),
        ],
      );
    }
    final setup = run.phase == QuizPhase.setup;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: const Key('quiz-impossible'),
            onPressed: setup ? null : ctrl.impossible,
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(l10n.quizImpossible)),
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: FilledButton.icon(
            key: const Key('quiz-check'),
            onPressed: run.canSubmit ? ctrl.submit : null,
            icon: const Icon(Icons.check_rounded),
            label: Text(l10n.quizCheck),
          ),
        ),
      ],
    );
  }
}

/// Ergebnis nach dem Durchgang: Richtige, Kennzahlen, neue Bestwerte und die
/// falsch beantworteten Fragen mit Lösung.
class _ResultView extends ConsumerWidget {
  const _ResultView({required this.state});
  final QuizState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final run = state.run;
    final s = run.summary;
    final timedOut = run.config.timed && run.completed;
    final wrong = [for (final a in run.answers) if (!a.correct) a];
    String recordName(QuizRecord r) => switch (r) {
          QuizRecord.timedCorrect => l10n.quizBestTimed,
          QuizRecord.bestStreak => l10n.quizBestStreak,
          QuizRecord.fastest => l10n.quizBestPace,
        };
    return AppPage(
      maxWidth: 720,
      listKey: const Key('quiz-result'),
      children: [
        ScorePanel(
          label: timedOut ? l10n.quizTimeUp : l10n.quizResultTitle,
          trailing: run.config.timed ? l10n.quizModeTimed : l10n.quizModeTraining,
          value: Text('${s.correct} / ${s.answered}', key: const Key('quiz-result-score'), style: ScorePanel.valueStyle(context, compact: true)),
          progress: s.rate ?? 0,
        ),
        for (final r in state.records) ...[
          const SizedBox(height: AppSpacing.m),
          LookBanner(key: Key('quiz-record-${r.name}'), text: l10n.quizNewRecord(recordName(r)), color: colors.record),
        ],
        SizedBox(height: context.look.gridGap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, st) in quizStats(s).skip(1).indexed) ...[
                if (i > 0) SizedBox(width: context.look.gridGap),
                Expanded(child: StatTile(label: _label(l10n, st.key), value: st.value)),
              ],
            ],
          ),
        ),
        const SectionGap(),
        SectionHeader(l10n.quizMistakes),
        AppCard(
          child: wrong.isEmpty
              ? Text(l10n.quizNoMistakes, style: theme.textTheme.bodyMedium)
              : Column(
                  children: [
                    for (final (i, a) in wrong.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      QuizAnswerTile(answer: a, out: run.config.out),
                    ],
                  ],
                ),
        ),
        const SectionGap(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('quiz-done'),
                onPressed: () async {
                  await ref.read(quizProvider.notifier).close();
                  if (context.mounted) context.go(QuizRoutes.setup);
                },
                child: Text(l10n.quizDone),
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: FilledButton.icon(
                key: const Key('quiz-again'),
                onPressed: () => ref.read(quizProvider.notifier).start(run.config),
                icon: const Icon(Icons.replay_rounded),
                label: Text(l10n.quizAgain),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _label(AppLocalizations l10n, String key) => switch (key) {
        'correctRate' => l10n.quizStatRate,
        'bestStreak' => l10n.quizBestStreak,
        'quizPace' => l10n.quizStatPace,
        _ => key,
      };
}
