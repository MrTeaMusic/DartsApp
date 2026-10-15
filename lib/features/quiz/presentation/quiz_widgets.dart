import 'package:flutter/material.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../board/domain/segment.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../domain/checkout_route.dart';
import '../domain/quiz_answer.dart';
import '../domain/quiz_run.dart';

/// Kompaktes Tastenfeld: Single/Double/Triple wählen, dann Zahl, 25 oder
/// Bull. Nach jedem Feld springt der Multiplikator auf Single zurück.
class QuizKeypad extends StatefulWidget {
  const QuizKeypad({super.key, required this.onPick, required this.onUndo, this.enabled = true, this.keyHeight = 44});

  final ValueChanged<Segment> onPick;
  final VoidCallback onUndo;
  final bool enabled;
  final double keyHeight;

  @override
  State<QuizKeypad> createState() => _QuizKeypadState();
}

class _QuizKeypadState extends State<QuizKeypad> {
  int _multiplier = 1;

  void _pick(Segment s) {
    widget.onPick(s);
    setState(() => _multiplier = 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final enabled = widget.enabled;
    const gap = AppSpacing.s - 2;
    final numberColor = switch (_multiplier) {
      3 => colors.tripleHit,
      2 => colors.doubleHit,
      _ => null,
    };
    final prefix = switch (_multiplier) {
      3 => 'T',
      2 => 'D',
      _ => '',
    };
    Widget row(List<Widget> keys) => Row(
          children: [
            for (final (i, k) in keys.indexed) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(child: k),
            ],
          ],
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row([
          for (final (m, label, color) in [
            (1, l10n.single, null),
            (2, l10n.double, colors.doubleHit),
            (3, l10n.triple, colors.tripleHit),
          ])
            _Key(
              key: Key('quiz-mult-$m'),
              label: label,
              height: widget.keyHeight - 4,
              color: color,
              selected: _multiplier == m,
              onTap: enabled ? () => setState(() => _multiplier = m) : null,
            ),
        ]),
        const SizedBox(height: gap + 2),
        for (var r = 0; r < 4; r++) ...[
          if (r > 0) const SizedBox(height: gap),
          row([
            for (var n = r * 5 + 1; n <= r * 5 + 5; n++)
              _Key(
                key: Key('quiz-key-$n'),
                label: '$prefix$n',
                height: widget.keyHeight,
                color: numberColor,
                onTap: enabled ? () => _pick(Segment.fromNumber(n, _multiplier)) : null,
              ),
          ]),
        ],
        const SizedBox(height: gap),
        row([
          _Key(
            key: const Key('quiz-key-25'),
            label: '25',
            height: widget.keyHeight,
            onTap: enabled ? () => _pick(Segment.outerBull) : null,
          ),
          _Key(
            key: const Key('quiz-key-bull'),
            label: 'BULL',
            height: widget.keyHeight,
            color: colors.doubleHit,
            onTap: enabled ? () => _pick(Segment.bull) : null,
          ),
          _Key(
            key: const Key('quiz-undo'),
            icon: Icons.backspace_outlined,
            label: '',
            height: widget.keyHeight,
            color: colors.textMuted,
            onTap: enabled ? widget.onUndo : null,
          ),
        ]),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({super.key, required this.label, required this.height, this.onTap, this.color, this.selected = false, this.icon});

  final String label;
  final double height;
  final VoidCallback? onTap;
  final Color? color;
  final bool selected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final accent = color ?? theme.colorScheme.primary;
    final fg = selected ? accent : (color ?? theme.colorScheme.onSurface);
    final radius = BorderRadius.circular(look.id == DartLookId.clean ? AppRadii.s + 2 : look.radiusS);
    final style = look.chipNumber.copyWith(fontSize: (look.chipNumber.fontSize ?? 20) * 0.82, color: fg);
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.16) : colors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: selected
              ? BorderSide(color: accent.withValues(alpha: 0.8), width: 1.5)
              : (look.id == DartLookId.lab ? BorderSide(color: theme.colorScheme.outline) : BorderSide.none),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 20, color: fg)
                  : FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: style, maxLines: 1)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kleines Feld-Schild, z. B. „T20“, eingefärbt nach Multiplikator.
class SegmentTag extends StatelessWidget {
  const SegmentTag(this.segment, {super.key, this.dim = false});
  final Segment segment;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final c = segmentColor(context, segment);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: AppSpacing.xxs + 1),
      decoration: BoxDecoration(
        color: (segment.isSingle ? context.dartColors.surfaceHigh : c.withValues(alpha: 0.14)),
        borderRadius: BorderRadius.circular(look.id == DartLookId.clean ? AppRadii.pill : look.radiusS),
        border: look.id == DartLookId.lab ? Border.all(color: c.withValues(alpha: 0.4)) : null,
      ),
      child: Text(
        segment.name,
        style: look.chipNumber.copyWith(fontSize: 15, color: dim ? c.withValues(alpha: 0.6) : c),
      ),
    );
  }
}

/// Ein Weg als Reihe von [SegmentTag]s, optional mit Text dahinter.
class RouteTags extends StatelessWidget {
  const RouteTags(this.route, {super.key, this.trailing});
  final List<Segment> route;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs + 2,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final s in route) SegmentTag(s),
        if (trailing != null)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: Text(trailing!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.dartColors.textMuted)),
          ),
      ],
    );
  }
}

/// „3 Darts“ bzw. „1 Dart“.
String quizDartsText(AppLocalizations l10n, int darts) => l10n.quizDartsLeft(darts);

/// Eine gespeicherte Antwort in Listen (Ergebnis, Verlauf).
class QuizAnswerTile extends StatelessWidget {
  const QuizAnswerTile({super.key, required this.answer, this.out = OutMode.double});
  final QuizAnswer answer;
  final OutMode out;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final a = answer;
    final possible = CheckoutRoutes.possible(a.score, a.darts, out);
    final rec = possible ? CheckoutRoutes.recommended(a.score, a.darts, out) : null;
    final setup = possible ? null : CheckoutRoutes.setupAdvice(a.score, a.darts, out);
    final given = a.impossible
        ? Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.quizImpossible, style: theme.textTheme.bodyMedium),
              if (a.setup.isNotEmpty) RouteTags(a.setup, trailing: l10n.quizLeave(a.score - _sum(a.setup))),
            ],
          )
        : RouteTags(a.route);
    final same = a.recommended || (rec != null && !a.impossible && CheckoutRoutes.sameRoute(a.route, rec));
    final solution = a.correct && same
        ? null
        : rec != null
            ? RouteTags(rec)
            : setup != null
                ? RouteTags(setup.darts, trailing: '${l10n.quizImpossible} · ${l10n.quizLeave(setup.leave)}')
                : Text(l10n.quizImpossible, style: theme.textTheme.bodySmall);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            a.correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: a.correct ? colors.success : colors.danger,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.m),
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a.score}', style: context.look.chipNumber.copyWith(color: theme.colorScheme.onSurface)),
                Text(quizDartsText(l10n, a.darts), style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                given,
                if (solution != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.s,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [Kicker(l10n.quizRecommended), solution],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Text('${formatDecimal(a.ms / 1000)} s', style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }

  static int _sum(List<Segment> r) => r.fold(0, (a, s) => a + s.score);
}

/// Erklärung einer Antwort (Training): was richtig/falsch war, empfohlener
/// Weg, Alternativen bzw. Stell-Vorschlag.
class QuizFeedbackView extends StatelessWidget {
  const QuizFeedbackView({super.key, required this.feedback, required this.out});
  final QuizFeedback feedback;
  final OutMode out;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final f = feedback;
    final q = f.question;
    final a = f.answer;
    final dartsText = quizDartsText(l10n, q.darts);
    final lines = <String>[];
    if (f.routeCheck case final c?) {
      if (c.valid) {
        lines.add(c.recommended ? l10n.quizIsRecommended : l10n.quizValidOther);
      } else if (!q.possible) {
        lines.add(l10n.quizNotPossible(q.score, dartsText));
        lines.add(l10n.quizShouldBeImpossible);
      } else {
        lines.add(switch (c.problem!) {
          RouteProblem.total => l10n.quizProblemTotal(c.sum, q.score),
          RouteProblem.bust => l10n.quizProblemBust,
          RouteProblem.finish => out == OutMode.master ? l10n.quizProblemFinishMaster : l10n.quizProblemFinish,
          RouteProblem.tooManyDarts || RouteProblem.empty || RouteProblem.miss => l10n.quizProblemTooMany,
        });
      }
    } else if (f.setupCheck case final s?) {
      lines.add('${l10n.quizImpossibleRight} ${l10n.quizNotPossible(q.score, dartsText)}');
      lines.add(s.problem != null ? l10n.quizSetupBust : (s.good ? l10n.quizSetupGood(s.leave) : l10n.quizSetupWeak(s.leave)));
    } else if (a.impossible) {
      lines.add(q.possible ? l10n.quizWasPossible(q.score, dartsText) : l10n.quizNotPossible(q.score, dartsText));
    }
    final max = _maxFor(q.darts, out);
    if (!q.possible && out == OutMode.double && q.darts == 3 && q.score > 158) lines.add(l10n.quizBogeys);
    if (!q.possible && q.score > max) lines.add(l10n.quizMaxFor(dartsText, max));

    final given = a.impossible
        ? (a.setup.isEmpty
            ? Text(l10n.quizImpossible, style: theme.textTheme.titleMedium)
            : RouteTags(a.setup, trailing: l10n.quizLeave(q.score - a.setup.fold<int>(0, (x, s) => x + s.score))))
        : RouteTags(a.route, trailing: '= ${a.route.fold<int>(0, (x, s) => x + s.score)}');

    Widget section(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Kicker(label),
              const SizedBox(height: AppSpacing.xs + 2),
              child,
            ],
          ),
        );

    return Column(
      key: const Key('quiz-feedback'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LookBanner(
          textKey: const Key('quiz-verdict'),
          text: a.correct ? l10n.quizCorrect : l10n.quizWrong,
          kicker: '${q.score} · $dartsText',
          color: a.correct ? colors.success : colors.danger,
        ),
        const SizedBox(height: AppSpacing.s),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(l, style: theme.textTheme.bodyMedium),
          ),
        section(l10n.quizYourAnswer, given),
        if (q.recommended case final rec? when !(f.routeCheck?.recommended ?? false))
          section(l10n.quizRecommended, RouteTags(rec)),
        if (q.setup case final plan? when !(f.setupCheck?.recommended ?? false))
          section(l10n.quizSetupAdvice, RouteTags(plan.darts, trailing: l10n.quizLeave(plan.leave))),
        if (q.alternatives.isNotEmpty)
          section(
            l10n.quizAlternatives,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, r) in q.alternatives.indexed) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.xs + 2),
                  RouteTags(r),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// Höchstes Finish mit [darts] Darts.
  static int _maxFor(int darts, OutMode out) => out == OutMode.master
      ? 60 * darts
      : switch (darts) {
          1 => 50,
          2 => 110,
          _ => 170,
        };
}
