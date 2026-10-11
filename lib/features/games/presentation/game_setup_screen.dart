import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/settings/app_settings.dart';
import '../data/game_repository.dart';
import '../domain/engine/game_definition.dart';
import '../domain/game_catalog.dart';
import '../domain/games/checkout/checkout_training.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/active_player.dart';
import 'active_game_controller.dart';
import 'game_texts.dart';

/// Einstellungen vor dem Spielstart. Die Formularfelder entstehen aus den
/// [ConfigOption]s der Spieldefinition; die letzte Wahl wird gemerkt.
class GameSetupScreen extends ConsumerStatefulWidget {
  const GameSetupScreen({super.key, required this.gameId});
  final String gameId;

  @override
  ConsumerState<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends ConsumerState<GameSetupScreen> {
  late final GameDefinition? _def = GameCatalog.byId(widget.gameId);
  late Map<String, Object?> _config;
  bool _starting = false;

  String get _prefsKey => 'game.config.${widget.gameId}';

  @override
  void initState() {
    super.initState();
    final def = _def;
    _config = def == null ? {} : {...def.defaults, ..._loadSaved()};
  }

  Map<String, Object?> _loadSaved() {
    final raw = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    if (raw == null) return const {};
    try {
      final v = jsonDecode(raw);
      return v is Map<String, Object?> ? v : const {};
    } on FormatException {
      return const {};
    }
  }

  void _set(String key, Object? value) => setState(() => _config = {..._config, key: value});

  Future<void> _start() async {
    final def = _def;
    if (def == null || _starting) return;
    setState(() => _starting = true);
    final resolved = def.resolve(_config);
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, jsonEncode(resolved));
    var config = resolved;
    if (def.id == CheckoutTraining.id && resolved['mode'] == 'weak') {
      final playerId = await ref.read(profileRepositoryProvider).resolve(ref.read(activePlayerIdProvider));
      final weak = await ref.read(gameRepositoryProvider).weakCheckoutTargets(playerId: playerId);
      config = {...resolved, 'weakTargets': weak};
    }
    await ref.read(activeGameProvider.notifier).start(def, config);
    if (!mounted) return;
    setState(() => _starting = false);
    context.go(Routes.play);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final def = _def;
    if (def == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(widget.gameId)));
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameTitle(def.id))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              Row(
                children: [
                  Icon(gameIcon(def.id), color: theme.colorScheme.primary, size: 32),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(child: Text(l10n.gameDescription(def.id), style: theme.textTheme.bodyLarge)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(l10n.gameSettings),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, o) in def.options.indexed) ...[
                      if (i > 0) const Divider(height: AppSpacing.xl),
                      _OptionField(option: o, gameId: def.id, value: _config[o.key], onChanged: (v) => _set(o.key, v)),
                    ],
                    if (def.id == CheckoutTraining.id && _config['mode'] == 'weak') ...[
                      const SizedBox(height: AppSpacing.m),
                      Text(l10n.gameWeakHint, style: theme.textTheme.bodySmall?.copyWith(color: context.dartColors.textMuted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                key: const Key('start-game'),
                onPressed: _starting ? null : _start,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n.gameStart),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionField extends StatelessWidget {
  const _OptionField({required this.option, required this.gameId, required this.value, required this.onChanged});

  final ConfigOption option;
  final String gameId;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final label = Text(l10n.optionLabel(option.key, gameId), style: theme.textTheme.titleSmall);
    switch (option) {
      case BoolOption():
        return SwitchListTile(
          key: Key('opt-${option.key}'),
          contentPadding: EdgeInsets.zero,
          title: label,
          value: value is bool ? value! as bool : false,
          onChanged: onChanged,
        );
      case ChoiceOption(:final values):
        final selected = value is String && values.contains(value) ? value! as String : values.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            const SizedBox(height: AppSpacing.s),
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                for (final v in values)
                  ChoiceChip(
                    key: Key('opt-${option.key}-$v'),
                    label: Text(l10n.optionValue(v, key: option.key)),
                    selected: v == selected,
                    onSelected: (_) => onChanged(v),
                  ),
              ],
            ),
          ],
        );
      case IntChoiceOption(:final values):
        final selected = value is num ? (value! as num).toInt() : values.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            const SizedBox(height: AppSpacing.s),
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                for (final v in values)
                  ChoiceChip(
                    key: Key('opt-${option.key}-$v'),
                    label: Text('$v'),
                    selected: v == selected,
                    onSelected: (_) => onChanged(v),
                  ),
              ],
            ),
          ],
        );
      case IntOption(:final min, :final max, :final step):
        final current = (value is num ? (value! as num).toInt() : min).clamp(min, max);
        if (max - min > 50) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: label),
                Text('$current', style: theme.textTheme.headlineSmall),
              ]),
              Slider(
                key: Key('opt-${option.key}'),
                value: current.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: (max - min) ~/ step,
                onChanged: (v) => onChanged(v.round()),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: label),
            IconButton.outlined(
              key: Key('opt-${option.key}-minus'),
              onPressed: current > min ? () => onChanged((current - step).clamp(min, max)) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 64,
              child: Text('$current', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            ),
            IconButton.outlined(
              key: Key('opt-${option.key}-plus'),
              onPressed: current < max ? () => onChanged((current + step).clamp(min, max)) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        );
    }
  }
}
