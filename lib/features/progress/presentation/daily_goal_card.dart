import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../domain/daily_goal.dart';
import 'progress_providers.dart';
import 'progress_texts.dart';

/// Startseiten-Karte: Ring mit dem heutigen Stand des Tagesziels und die
/// Serie (Flamme, aktuell, Bestwert, freier Tag). Antippen öffnet den
/// Editor.
class DailyGoalCard extends ConsumerWidget {
  const DailyGoalCard({super.key, this.wide = false});

  /// Ring und Serie nebeneinander statt untereinander.
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final goal = ref.watch(dailyGoalProvider);
    final status = ref.watch(dailyGoalStatusProvider);
    final today = (status?.today ?? 0).floor();
    final reached = status?.reached ?? false;
    final streak = status?.streak ?? GoalStreak.empty;
    final unit = l10n.goalUnit(goal.unit);
    final accent = reached ? colors.success : theme.colorScheme.primary;

    final ring = SizedBox(
      width: wide ? 112 : 96,
      height: wide ? 112 : 96,
      child: GoalRing(
        value: status?.ratio ?? 0,
        color: accent,
        track: colors.surfaceHigh,
        child: reached
            ? Icon(Icons.check_rounded, key: const Key('daily-goal-done'), color: accent, size: wide ? 44 : 38)
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.m),
                  child: Text('${((status?.ratio ?? 0) * 100).floor()} %',
                      style: look.chipNumber.copyWith(color: theme.colorScheme.onSurface)),
                ),
              ),
      ),
    );

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Kicker(l10n.dgTitle, color: accent),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.dgTodayLine(today, goal.amount, unit),
          key: const Key('daily-goal-today'),
          style: (wide ? theme.textTheme.headlineSmall : theme.textTheme.titleLarge)?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          reached ? l10n.dgReached : l10n.dgRemaining(math.max(0, goal.amount - today), unit),
          style: theme.textTheme.bodyMedium?.copyWith(color: reached ? colors.success : colors.textMuted),
        ),
      ],
    );

    final streakBlock = _StreakBlock(streak: streak, reachedToday: reached);

    return AppCard(
      key: const Key('daily-goal-card'),
      onTap: () => showDailyGoalEditor(context),
      child: Stack(
        children: [
          if (wide)
            IntrinsicHeight(
              child: Row(
                children: [
                  ring,
                  const SizedBox(width: AppSpacing.l),
                  Expanded(child: summary),
                  VerticalDivider(width: AppSpacing.xl * 2, color: theme.colorScheme.outline),
                  Expanded(child: Padding(padding: const EdgeInsets.only(right: 40), child: streakBlock)),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ring,
                    const SizedBox(width: AppSpacing.l),
                    Expanded(child: Padding(padding: const EdgeInsets.only(right: 32), child: summary)),
                  ],
                ),
                Divider(height: AppSpacing.xl, color: theme.colorScheme.outline),
                streakBlock,
              ],
            ),
          Positioned(
            top: -8,
            right: -8,
            child: IconButton(
              key: const Key('daily-goal-edit'),
              tooltip: l10n.dgEdit,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.tune_rounded, color: colors.textMuted),
              onPressed: () => showDailyGoalEditor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakBlock extends StatelessWidget {
  const _StreakBlock({required this.streak, required this.reachedToday});
  final GoalStreak streak;
  final bool reachedToday;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final active = streak.current > 0;
    final flame = active ? colors.record : colors.textMuted;
    return Row(
      children: [
        Icon(
          active ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
          key: const Key('daily-goal-flame'),
          color: flame,
          size: 40,
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Kicker(l10n.dgStreak),
              const SizedBox(height: AppSpacing.xxs),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: AppSpacing.m,
                runSpacing: AppSpacing.xxs,
                children: [
                  Text(
                    l10n.dgStreakDays(streak.current),
                    key: const Key('daily-goal-streak'),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(l10n.dgBest(streak.best), style: look.kicker.copyWith(color: colors.textMuted)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                streak.freeDayUsedThisWeek ? l10n.dgFreeDayUsed : l10n.dgFreeDayOpen,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fortschrittsring mit Inhalt in der Mitte.
class GoalRing extends StatelessWidget {
  const GoalRing({super.key, required this.value, required this.color, required this.track, this.child, this.stroke = 10});
  final double value;
  final Color color;
  final Color track;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1).toDouble()),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => CustomPaint(
        painter: _RingPainter(value: v, color: color, track: track, stroke: stroke),
        child: Center(child: child),
      ),
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track, required this.stroke});
  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - stroke / 2;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(c, r, base);
    if (value <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}

/// Editor für das Tagesziel: Einheit und Menge.
Future<void> showDailyGoalEditor(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const DailyGoalDialog(),
    );

class DailyGoalDialog extends ConsumerStatefulWidget {
  const DailyGoalDialog({super.key});

  @override
  ConsumerState<DailyGoalDialog> createState() => _DailyGoalDialogState();
}

class _DailyGoalDialogState extends ConsumerState<DailyGoalDialog> {
  late DailyGoalUnit _unit;
  late int _amount;

  @override
  void initState() {
    super.initState();
    final goal = ref.read(dailyGoalProvider);
    _unit = goal.unit;
    _amount = goal.amount;
  }

  void _setUnit(DailyGoalUnit u) {
    if (u == _unit) return;
    setState(() {
      _unit = u;
      _amount = u.defaultAmount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final look = context.look;
    final colors = context.dartColors;
    final steps = (_unit.max - _unit.min) ~/ _unit.step;
    return AlertDialog(
      title: Text(l10n.dgTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Kicker(l10n.dgUnitLabel),
            const SizedBox(height: AppSpacing.s),
            SegmentedButton<DailyGoalUnit>(
              key: const Key('daily-goal-unit'),
              showSelectedIcon: false,
              segments: [
                for (final u in DailyGoalUnit.values)
                  ButtonSegment(
                    value: u,
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(l10n.goalUnit(u), maxLines: 1, softWrap: false)),
                    tooltip: l10n.goalUnit(u),
                  ),
              ],
              selected: {_unit},
              onSelectionChanged: (s) => _setUnit(s.first),
            ),
            const SizedBox(height: AppSpacing.l),
            Row(
              children: [
                Expanded(child: Kicker(l10n.dgAmountLabel)),
                Text(
                  '$_amount ${l10n.goalUnit(_unit)}',
                  key: const Key('daily-goal-amount'),
                  style: look.chipNumber.copyWith(color: theme.colorScheme.onSurface),
                ),
              ],
            ),
            Slider(
              key: const Key('daily-goal-slider'),
              min: _unit.min.toDouble(),
              max: _unit.max.toDouble(),
              divisions: steps,
              value: _amount.toDouble(),
              label: '$_amount',
              onChanged: (v) => setState(() => _amount = _unit.clamp(v.round())),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(l10n.dgRules, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.dgCancel)),
        FilledButton(
          key: const Key('daily-goal-save'),
          onPressed: () {
            final unit = _unit;
            final amount = _amount;
            ref.read(settingsProvider.notifier).update((s) => s.copyWith(dailyGoalUnit: unit, dailyGoalAmount: amount));
            Navigator.of(context).pop();
          },
          child: Text(l10n.dgSave),
        ),
      ],
    );
  }
}
