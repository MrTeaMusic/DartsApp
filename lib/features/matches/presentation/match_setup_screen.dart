import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/dart_look.dart';
import '../../../core/database/app_database.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/match_store.dart';
import '../domain/match_format.dart';
import '../domain/match_session.dart';
import 'match_controller.dart';
import 'match_routes.dart';
import 'match_texts.dart';
import 'match_widgets.dart';

enum _Opponent { cpu, friend }

enum _Starter { me, opponent, random }

/// Einstellungen für ein Match gegen einen Freund oder einen Bot. Die letzte
/// Wahl wird gemerkt.
class MatchSetupScreen extends ConsumerStatefulWidget {
  const MatchSetupScreen({super.key});

  @override
  ConsumerState<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _MatchSetupScreenState extends ConsumerState<MatchSetupScreen> {
  _Opponent _opponent = _Opponent.cpu;
  double _cpuAverage = 50;
  late final TextEditingController _cpuName = TextEditingController();
  late final TextEditingController _guestName = TextEditingController();
  int? _friendProfile;
  int _startScore = 501;
  OutMode _out = OutMode.double;
  bool _doubleIn = false;
  bool _useSets = false;
  int _legs = 3;
  int _sets = 2;
  int _legsPerSet = 3;
  _Starter _starter = _Starter.me;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    final j = ref.read(matchStoreProvider).lastSetup();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    int intOf(String k, int fallback, int min, int max) =>
        j[k] is num ? (j[k] as num).toInt().clamp(min, max) : fallback;
    _opponent = pick(_Opponent.values, j['opponent'], _Opponent.cpu);
    _cpuAverage = j['cpuAverage'] is num ? (j['cpuAverage'] as num).toDouble().clamp(20, 110) : 50;
    _cpuName.text = j['cpuName'] is String ? j['cpuName'] as String : '';
    _guestName.text = j['guestName'] is String ? j['guestName'] as String : '';
    _friendProfile = j['friendProfile'] is num ? (j['friendProfile'] as num).toInt() : null;
    final score = intOf('startScore', 501, 2, 1001);
    _startScore = MatchFormat.startScores.contains(score) ? score : 501;
    _out = pick(OutMode.values, j['outMode'], OutMode.double);
    _doubleIn = j['doubleIn'] == true;
    _useSets = j['useSets'] == true;
    _legs = intOf('legs', 3, 1, 15);
    _sets = intOf('sets', 2, 1, 10);
    _legsPerSet = intOf('legsPerSet', 3, 1, 6);
    _starter = pick(_Starter.values, j['starter'], _Starter.me);
  }

  @override
  void dispose() {
    _cpuName.dispose();
    _guestName.dispose();
    super.dispose();
  }

  MatchFormat get _format => MatchFormat(
    startScore: _startScore,
    outMode: _out,
    doubleIn: _doubleIn,
    legsToWin: _useSets ? _legsPerSet : _legs,
    setsToWin: _useSets ? _sets : 0,
  );

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    final l10n = context.l10n;
    await ref.read(matchStoreProvider).saveLastSetup({
      'opponent': _opponent.name,
      'cpuAverage': _cpuAverage.round(),
      'cpuName': _cpuName.text.trim(),
      'guestName': _guestName.text.trim(),
      'friendProfile': ?_friendProfile,
      'startScore': _startScore,
      'outMode': _out.name,
      'doubleIn': _doubleIn,
      'useSets': _useSets,
      'legs': _legs,
      'sets': _sets,
      'legsPerSet': _legsPerSet,
      'starter': _starter.name,
    });
    final meId = await ref.read(profileRepositoryProvider).resolve(ref.read(activePlayerIdProvider));
    final players = await ref.read(profileRepositoryProvider).players();
    final me = players.where((p) => p.id == meId).firstOrNull;
    final opponent = switch (_opponent) {
      _Opponent.cpu => MatchPlayer.bot(
        _cpuName.text.trim().isEmpty ? l10n.matchCpuDefaultName : _cpuName.text.trim(),
        average: _cpuAverage.roundToDouble(),
      ),
      _Opponent.friend => _friendPlayer(
        players.where((p) => p.id == _friendProfile && p.id != meId).firstOrNull?.name,
        l10n,
      ),
    };
    final setup = MatchSetup(
      format: _format,
      players: [
        MatchPlayer.human(me?.name ?? 'Ich', profileId: meId),
        opponent,
      ],
      firstStarter: switch (_starter) {
        _Starter.me => 0,
        _Starter.opponent => 1,
        _Starter.random => math.Random().nextInt(2),
      },
    );
    await ref.read(matchControllerProvider.notifier).start(setup);
    if (!mounted) return;
    setState(() => _starting = false);
    context.go(MatchRoutes.play);
  }

  MatchPlayer _friendPlayer(String? profileName, AppLocalizations l10n) {
    if (profileName != null) return MatchPlayer.human(profileName, profileId: _friendProfile);
    final guest = _guestName.text.trim();
    return MatchPlayer.human(guest.isEmpty ? l10n.matchGuestDefault : guest);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final me = ref.watch(activePlayerProvider);
    final profiles = [
      for (final p in ref.watch(playersProvider).value ?? const <Player>[])
        if (p.id != me?.id) p,
    ];
    final friendProfile = profiles.any((p) => p.id == _friendProfile) ? _friendProfile : null;

    return Scaffold(
      appBar: AppPageBar(maxWidth: 640, title: Text(l10n.matchOpponentTitle)),
      body: AppPage(
        maxWidth: 640,
        children: [
              SectionHeader(l10n.matchOpponent),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<_Opponent>(
                      segments: [
                        ButtonSegment(
                          value: _Opponent.cpu,
                          icon: const Icon(Icons.smart_toy_outlined),
                          label: Text(l10n.matchVsCpu, key: const Key('match-vs-cpu')),
                        ),
                        ButtonSegment(
                          value: _Opponent.friend,
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: Text(l10n.matchVsFriend, key: const Key('match-vs-friend')),
                        ),
                      ],
                      selected: {_opponent},
                      onSelectionChanged: (s) => setState(() => _opponent = s.first),
                    ),
                    const SizedBox(height: AppSpacing.l),
                    if (_opponent == _Opponent.cpu) ...[
                      Row(
                        children: [
                          Expanded(child: Text(l10n.matchCpuAverage, style: theme.textTheme.titleSmall)),
                          Text(
                            '${_cpuAverage.round()}',
                            key: const Key('match-cpu-average-value'),
                            style: context.look.chipNumber.copyWith(fontSize: 24, color: theme.colorScheme.onSurface),
                          ),
                        ],
                      ),
                      Slider(
                        key: const Key('match-cpu-average'),
                        value: _cpuAverage,
                        min: 20,
                        max: 110,
                        divisions: 90,
                        label: '${_cpuAverage.round()}',
                        onChanged: (v) => setState(() => _cpuAverage = v.roundToDouble()),
                      ),
                      Text(
                        l10n.matchCpuHint(_cpuAverage.round(), l10n.averageLevel(_cpuAverage)),
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.m),
                      TextField(
                        key: const Key('match-cpu-name'),
                        controller: _cpuName,
                        maxLength: 40,
                        decoration: InputDecoration(labelText: l10n.matchCpuName, hintText: l10n.matchCpuDefaultName),
                      ),
                    ] else ...[
                      DropdownButtonFormField<int?>(
                        key: ValueKey('match-friend-profile-$friendProfile'),
                        initialValue: friendProfile,
                        decoration: InputDecoration(labelText: l10n.matchFriendProfile),
                        items: [
                          DropdownMenuItem<int?>(value: null, child: Text(l10n.matchGuest)),
                          for (final p in profiles) DropdownMenuItem<int?>(value: p.id, child: Text(p.name)),
                        ],
                        onChanged: (v) => setState(() => _friendProfile = v),
                      ),
                      if (friendProfile == null) ...[
                        const SizedBox(height: AppSpacing.m),
                        TextField(
                          key: const Key('match-guest-name'),
                          controller: _guestName,
                          maxLength: 40,
                          decoration: InputDecoration(labelText: l10n.matchGuestName, hintText: l10n.matchGuestDefault),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.s),
                      Text(l10n.matchFriendHint, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
                    ],
                  ],
                ),
              ),
              const SectionGap(),
              SectionHeader(l10n.matchFormat),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ChoiceRow<int>(
                      label: l10n.matchStartScore,
                      values: MatchFormat.startScores,
                      selected: _startScore,
                      labelOf: (v) => '$v',
                      keyPrefix: 'match-start',
                      onSelected: (v) => setState(() => _startScore = v),
                    ),
                    const Divider(height: AppSpacing.xl),
                    ChoiceRow<OutMode>(
                      label: l10n.matchOutMode,
                      values: OutMode.values,
                      selected: _out,
                      labelOf: l10n.outModeLabel,
                      keyPrefix: 'match-out',
                      onSelected: (v) => setState(() => _out = v),
                    ),
                    SwitchListTile(
                      key: const Key('match-double-in'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.matchDoubleIn, style: theme.textTheme.titleSmall),
                      value: _doubleIn,
                      onChanged: (v) => setState(() => _doubleIn = v),
                    ),
                    const Divider(height: AppSpacing.xl),
                    ChoiceRow<bool>(
                      label: '${l10n.matchModeLegs} / ${l10n.matchModeSets}',
                      values: const [false, true],
                      selected: _useSets,
                      labelOf: (v) => v ? l10n.matchModeSets : l10n.matchModeLegs,
                      keyPrefix: 'match-sets',
                      onSelected: (v) => setState(() => _useSets = v),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    if (_useSets) ...[
                      StepperRow(
                        label: l10n.matchSetsToWin,
                        value: _sets,
                        min: 1,
                        max: 10,
                        keyPrefix: 'match-sets-to-win',
                        onChanged: (v) => setState(() => _sets = v),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      StepperRow(
                        label: l10n.matchLegsPerSet,
                        value: _legsPerSet,
                        min: 1,
                        max: 6,
                        keyPrefix: 'match-legs-per-set',
                        onChanged: (v) => setState(() => _legsPerSet = v),
                      ),
                    ] else
                      StepperRow(
                        label: l10n.matchLegsToWin,
                        value: _legs,
                        min: 1,
                        max: 15,
                        keyPrefix: 'match-legs',
                        onChanged: (v) => setState(() => _legs = v),
                      ),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      l10n.formatLabel(_format),
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                    const Divider(height: AppSpacing.xl),
                    ChoiceRow<_Starter>(
                      label: l10n.matchStarter,
                      values: _Starter.values,
                      selected: _starter,
                      labelOf: (v) => switch (v) {
                        _Starter.me => l10n.matchStarterMe,
                        _Starter.opponent => l10n.matchStarterOpponent,
                        _Starter.random => l10n.matchStarterRandom,
                      },
                      keyPrefix: 'match-starter',
                      onSelected: (v) => setState(() => _starter = v),
                    ),
                  ],
                ),
              ),
              const SectionGap(),
              FilledButton.icon(
                key: const Key('start-match'),
                onPressed: _starting ? null : _start,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n.matchStart),
              ),
            ],
      ),
    );
  }
}
