import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/quiz_repository.dart';
import '../domain/quiz_answer.dart';
import '../domain/quiz_config.dart';
import '../domain/quiz_scheduler.dart';
import 'quiz_controller.dart';
import 'quiz_routes.dart';
import 'quiz_widgets.dart';

/// Bestwerte und bisherige Antworten des aktiven Profils.
final quizOverviewProvider = FutureProvider.autoDispose<({QuizBests bests, List<QuizAnswer> history})>((ref) async {
  ref.watch(activePlayerProvider);
  final id = await ref.read(profileRepositoryProvider).resolve(ref.read(activePlayerIdProvider));
  return ref.read(quizRepositoryProvider).load(id);
});

/// Gespeicherte Einstellungen des Quiz.
const String quizPrefsKey = 'quiz.config';

/// Einstieg ins Checkout-Quiz: Modus, Reste, Darts, Bestwerte und die
/// Reste, die gerade öfter drankommen.
class QuizSetupScreen extends ConsumerStatefulWidget {
  const QuizSetupScreen({super.key});

  @override
  ConsumerState<QuizSetupScreen> createState() => _QuizSetupScreenState();
}

class _QuizSetupScreenState extends ConsumerState<QuizSetupScreen> {
  late QuizConfig _config = _load();
  bool _starting = false;

  // Schwache Reste nur neu berechnen, wenn sich Einstellungen oder Daten
  // ändern, nicht bei jedem Aufbau.
  (QuizConfig, List<QuizAnswer>)? _weakKey;
  List<QuizKey> _weak = const [];
  int _poolSize = 0;

  QuizConfig _load() {
    final raw = ref.read(sharedPreferencesProvider).getString(quizPrefsKey);
    if (raw == null) return const QuizConfig();
    try {
      final v = jsonDecode(raw);
      return v is Map<String, Object?> ? QuizConfig.fromJson(v) : const QuizConfig();
    } on FormatException {
      return const QuizConfig();
    }
  }

  void _set(QuizConfig c) => setState(() => _config = c);

  List<QuizKey> _weakFor(List<QuizAnswer> history) {
    final key = (_config, history);
    if (_weakKey == null || _weakKey!.$1 != key.$1 || !identical(_weakKey!.$2, history)) {
      final pool = _config.pool();
      _poolSize = pool.length;
      _weak = QuizScheduler(pool: pool, history: history).weakest(8);
      _weakKey = key;
    }
    return _weak;
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    await ref.read(sharedPreferencesProvider).setString(quizPrefsKey, jsonEncode(_config.toJson()));
    await ref.read(quizProvider.notifier).start(_config);
    if (!mounted) return;
    setState(() => _starting = false);
    context.go(QuizRoutes.play);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final overview = ref.watch(quizOverviewProvider).value;
    final weak = overview == null ? const <QuizKey>[] : _weakFor(overview.history);
    if (overview == null) _poolSize = _config.pool().length;
    final bests = overview?.bests;
    final c = _config;

    Widget chips<T>(String label, List<T> values, T selected, String Function(T) text, void Function(T) pick, String key) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.s),
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                for (final v in values)
                  ChoiceChip(
                    key: Key('quiz-$key-${v is Enum ? v.name : v}'),
                    label: Text(text(v)),
                    selected: v == selected,
                    onSelected: (_) => pick(v),
                  ),
              ],
            ),
          ],
        );

    return Scaffold(
      appBar: AppPageBar(maxWidth: 640, title: Text(l10n.quizTitle)),
      // Start immer erreichbar, auch auf dem Telefon ohne Scrollen.
      bottomNavigationBar: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final pad = AppPageBar.contentInset(context, box.maxWidth, 640);
          return Padding(
            padding: EdgeInsets.fromLTRB(pad, AppSpacing.s, pad, AppSpacing.m),
            child: FilledButton.icon(
              key: const Key('quiz-start'),
              onPressed: _starting || _poolSize == 0 ? null : _start,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l10n.quizStart),
            ),
          );
        }),
      ),
      body: AppPage(
        maxWidth: 640,
        listKey: const Key('quiz-setup'),
        children: [
          AppCard(
            child: Row(
              children: [
                const IconBadge(icon: Icons.quiz_rounded, size: 52),
                const SizedBox(width: AppSpacing.l),
                Expanded(child: Text(l10n.quizIntro, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
          const SectionGap(),
          SectionHeader(l10n.quizMode),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ModeCard(
                    key: const Key('quiz-mode-training'),
                    icon: Icons.school_rounded,
                    title: l10n.quizModeTraining,
                    text: l10n.quizModeTrainingText,
                    selected: c.mode == QuizMode.training,
                    onTap: () => _set(c.copyWith(mode: QuizMode.training)),
                  ),
                ),
                SizedBox(width: context.look.gridGap),
                Expanded(
                  child: _ModeCard(
                    key: const Key('quiz-mode-timed'),
                    icon: Icons.timer_rounded,
                    title: l10n.quizModeTimed,
                    text: l10n.quizModeTimedText(QuizConfig.timedSeconds),
                    selected: c.mode == QuizMode.timed,
                    onTap: () => _set(c.copyWith(mode: QuizMode.timed)),
                  ),
                ),
              ],
            ),
          ),
          const SectionGap(),
          SectionHeader(l10n.gameSettings),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                chips<QuizRange>(l10n.quizRange, QuizRange.values, c.range,
                    (r) => r == QuizRange.all ? l10n.quizRangeAll : r.label, (r) => _set(c.copyWith(range: r)), 'range'),
                const Divider(height: AppSpacing.xl),
                chips<QuizDarts>(l10n.quizDartsOption, QuizDarts.values, c.darts,
                    (d) => d == QuizDarts.mixed ? l10n.quizDartsMixed : '${d.count}', (d) => _set(c.copyWith(darts: d)), 'darts'),
                const Divider(height: AppSpacing.xl),
                chips<OutMode>(l10n.optOutMode, const [OutMode.double, OutMode.master], c.out,
                    (o) => o == OutMode.master ? l10n.quizOutMaster : l10n.quizOutDouble, (o) => _set(c.copyWith(out: o)), 'out'),
                const Divider(height: AppSpacing.xl),
                SwitchListTile(
                  key: const Key('quiz-only-checkable'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.quizOnlyCheckable, style: theme.textTheme.titleSmall),
                  subtitle: Text(l10n.quizOnlyCheckableHint),
                  value: c.onlyCheckable,
                  onChanged: (v) => _set(c.copyWith(onlyCheckable: v)),
                ),
                SwitchListTile(
                  key: const Key('quiz-ask-setup'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.quizAskSetup, style: theme.textTheme.titleSmall),
                  subtitle: Text(l10n.quizAskSetupHint),
                  value: c.askSetup && !c.onlyCheckable,
                  onChanged: c.onlyCheckable ? null : (v) => _set(c.copyWith(askSetup: v)),
                ),
              ],
            ),
          ),
          if (_poolSize == 0) ...[
            const SizedBox(height: AppSpacing.m),
            Text(l10n.quizNoQuestions, key: const Key('quiz-no-questions'), style: theme.textTheme.bodyMedium?.copyWith(color: colors.danger)),
          ],
          const SectionGap(),
          SectionHeader(l10n.quizBests),
          if (bests == null || bests.sessions == 0)
            AppCard(child: Text(l10n.quizBestsEmpty, style: theme.textTheme.bodySmall))
          else
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Best(
                    key: const Key('quiz-best-timed'),
                    icon: Icons.timer_rounded,
                    label: l10n.quizBestTimed,
                    value: bests.timedCorrect == null ? '–' : '${bests.timedCorrect}',
                  ),
                  _Best(
                    key: const Key('quiz-best-streak'),
                    icon: Icons.local_fire_department_rounded,
                    label: l10n.quizBestStreak,
                    value: bests.bestStreak == null ? '–' : '${bests.bestStreak}',
                  ),
                  _Best(
                    key: const Key('quiz-best-pace'),
                    icon: Icons.bolt_rounded,
                    label: l10n.quizBestPace,
                    value: bests.fastestSeconds == null ? '–' : '${formatDecimal(bests.fastestSeconds)} s',
                  ),
                ],
              ),
            ),
          if (weak.isNotEmpty) ...[
            const SectionGap(),
            SectionHeader(l10n.quizWeak),
            AppCard(
              key: const Key('quiz-weak'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.s,
                    runSpacing: AppSpacing.s,
                    children: [for (final k in weak) _WeakChip(k)],
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Text(l10n.quizWeakHint, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({super.key, required this.icon, required this.title, required this.text, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = context.look;
    final colors = context.dartColors;
    final accent = theme.colorScheme.primary;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(look.radiusL),
        border: Border.all(color: selected ? accent : Colors.transparent, width: 2),
      ),
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon: icon, size: 36, color: selected ? accent : colors.textMuted),
                const Spacer(),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? accent : colors.textMuted,
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(text, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Ein Bestwert: Symbol, Beschriftung, Zahl.
class _Best extends StatelessWidget {
  const _Best({super.key, required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.dartColors.record),
          const SizedBox(height: AppSpacing.s),
          Kicker(label),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: look.statValue.copyWith(color: Theme.of(context).colorScheme.onSurface)),
          ),
        ],
      ),
    );
  }
}

class _WeakChip extends StatelessWidget {
  const _WeakChip(this.k);
  final QuizKey k;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final colors = context.dartColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(look.id == DartLookId.clean ? AppRadii.pill : look.radiusS),
        border: look.id == DartLookId.lab ? Border.all(color: colors.warning.withValues(alpha: 0.45)) : null,
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${k.score}', style: look.chipNumber.copyWith(fontSize: 17, color: theme.colorScheme.onSurface)),
          TextSpan(
            text: '  ${quizDartsText(context.l10n, k.darts)}',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ]),
      ),
    );
  }
}
