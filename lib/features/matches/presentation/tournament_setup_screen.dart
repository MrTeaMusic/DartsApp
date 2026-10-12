import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/match_store.dart';
import '../domain/tournament.dart';
import 'match_routes.dart';
import 'match_texts.dart';
import 'match_widgets.dart';
import 'tournament_controller.dart';

/// Neues Turnier: Schwierigkeit und Legs je Runde.
class TournamentSetupScreen extends ConsumerStatefulWidget {
  const TournamentSetupScreen({super.key});

  @override
  ConsumerState<TournamentSetupScreen> createState() => _TournamentSetupScreenState();
}

class _TournamentSetupScreenState extends ConsumerState<TournamentSetupScreen> {
  int _percent = 60;
  List<int> _bestOf = TournamentPreset.short.bestOf;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    final j = ref.read(matchStoreProvider).lastTournamentSetup();
    if (j['percent'] case final num p) _percent = (p.toInt() ~/ 5 * 5).clamp(30, 100);
    final b = j['bestOf'];
    if (b is List && b.length == Tournament.roundCount && b.every((e) => e is num)) {
      _bestOf = [for (final e in b) _odd((e as num).toInt())];
    }
  }

  static int _odd(int v) => (v.isEven ? v + 1 : v).clamp(1, 41);

  Future<void> _start() async {
    if (_starting) return;
    final l10n = context.l10n;
    final running = ref.read(tournamentControllerProvider);
    if (running != null && !running.finished) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.tourReplaceTitle),
          content: Text(l10n.tourReplaceText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cpuCancel)),
            FilledButton(
              key: const Key('confirm-replace-tournament'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.tourReplace),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _starting = true);
    await ref.read(matchStoreProvider).saveLastTournamentSetup({'percent': _percent, 'bestOf': _bestOf});
    final meId = await ref.read(profileRepositoryProvider).resolve(ref.read(activePlayerIdProvider));
    final me = (await ref.read(profileRepositoryProvider).players()).where((p) => p.id == meId).firstOrNull;
    await ref
        .read(tournamentControllerProvider.notifier)
        .create(humanName: me?.name ?? 'Ich', profileId: meId, difficulty: _percent / 100, bestOf: _bestOf);
    if (!mounted) return;
    setState(() => _starting = false);
    context.go(MatchRoutes.tournament);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final me = ref.watch(activePlayerProvider);
    final pool = ref.watch(cpuPlayersProvider);
    final averages = [for (final c in pool) c.average]..sort();
    final preset = TournamentPreset.of(_bestOf);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tourNew)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              Text(l10n.tournamentText, style: theme.textTheme.bodyLarge),
              const SizedBox(height: AppSpacing.l),
              if (me != null) ...[
                Text('${l10n.tourPlayer}: ${me.name}', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.l),
              ],
              SectionHeader(l10n.tourDifficulty),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(l10n.tourDifficulty, style: theme.textTheme.titleSmall)),
                        Text(
                          '$_percent %',
                          key: const Key('tour-difficulty-value'),
                          style: theme.textTheme.headlineSmall,
                        ),
                      ],
                    ),
                    Slider(
                      key: const Key('tour-difficulty'),
                      value: _percent.toDouble(),
                      min: 30,
                      max: 100,
                      divisions: 14,
                      label: '$_percent %',
                      onChanged: (v) => setState(() => _percent = v.round()),
                    ),
                    if (averages.isNotEmpty)
                      Text(
                        l10n.tourDifficultyHint(
                          _percent,
                          (averages.last * _percent / 100).round(),
                          (averages.first * _percent / 100).round(),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(l10n.tourFormat),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: AppSpacing.s,
                      runSpacing: AppSpacing.s,
                      children: [
                        for (final p in TournamentPreset.values)
                          ChoiceChip(
                            key: Key('tour-preset-${p.name}'),
                            label: Text(switch (p) {
                              TournamentPreset.sprint => l10n.tourPresetSprint,
                              TournamentPreset.short => l10n.tourPresetShort,
                              TournamentPreset.pdc => l10n.tourPresetPdc,
                            }),
                            selected: preset == p,
                            onSelected: (_) => setState(() => _bestOf = p.bestOf),
                          ),
                        ChoiceChip(label: Text(l10n.tourPresetCustom), selected: preset == null, onSelected: null),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.m),
                    for (var r = 0; r < Tournament.roundCount; r++) ...[
                      StepperRow(
                        label: l10n.tourRoundName(r),
                        caption: l10n.tourBestOf(_bestOf[r]),
                        value: _bestOf[r],
                        min: 1,
                        max: 41,
                        step: 2,
                        keyPrefix: 'tour-round-$r',
                        onChanged: (v) => setState(() => _bestOf = [..._bestOf]..[r] = _odd(v)),
                      ),
                      const SizedBox(height: AppSpacing.s),
                    ],
                    Text(l10n.tourFormatHint, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
                  ],
                ),
              ),
              if (pool.length < Tournament.size - 1) ...[
                const SizedBox(height: AppSpacing.m),
                Text(l10n.cpuTooFew, style: theme.textTheme.bodySmall?.copyWith(color: colors.warning)),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                key: const Key('start-tournament'),
                onPressed: _starting ? null : _start,
                icon: const Icon(Icons.emoji_events_rounded),
                label: Text(l10n.tourStart),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
