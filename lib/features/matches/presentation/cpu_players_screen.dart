import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../domain/cpu_players.dart';
import 'tournament_controller.dart';

/// Liste der Computergegner bearbeiten (Name und Average bei 100 %).
class CpuPlayersScreen extends ConsumerWidget {
  const CpuPlayersScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, int? index) async {
    final list = ref.read(cpuPlayersProvider);
    final current = index == null ? null : list[index];
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (context) => _EditDialog(player: current),
    );
    if (result == null) return;
    final controller = ref.read(cpuPlayersProvider.notifier);
    if (result.delete) {
      if (index != null) await controller.remove(index);
    } else if (result.player != null) {
      await controller.upsert(index, result.player!);
    }
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cpuResetTitle),
        content: Text(l10n.cpuResetText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cpuCancel)),
          FilledButton(
            key: const Key('confirm-cpu-reset'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.cpuReset),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(cpuPlayersProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final players = ref.watch(cpuPlayersProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cpuPlayersTitle),
        actions: [
          TextButton.icon(
            key: const Key('cpu-reset'),
            onPressed: () => _reset(context, ref),
            icon: const Icon(Icons.restore_rounded),
            label: Text(l10n.cpuReset),
          ),
          const SizedBox(width: AppSpacing.s),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('cpu-add'),
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.cpuAdd),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.page, AppSpacing.page, 96),
            children: [
              Text(l10n.cpuHint, style: theme.textTheme.bodySmall?.copyWith(color: context.dartColors.textMuted)),
              const SizedBox(height: AppSpacing.l),
              SectionHeader(l10n.cpuCount(players.length)),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  children: [
                    for (var i = 0; i < players.length; i++)
                      ListTile(
                        key: Key('cpu-player-$i'),
                        leading: const Icon(Icons.smart_toy_outlined),
                        title: Text(players[i].name),
                        trailing: Text(players[i].average.round().toString(), style: theme.textTheme.titleMedium),
                        onTap: () => _edit(context, ref, i),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditResult {
  const _EditResult({this.player, this.delete = false});
  final CpuPlayer? player;
  final bool delete;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.player});
  final CpuPlayer? player;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.player?.name ?? '');
  late double _average = widget.player?.average.roundToDouble() ?? 85;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, _EditResult(player: CpuPlayer(name, _average)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.player == null ? l10n.cpuAdd : l10n.cpuEdit),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('cpu-name'),
            controller: _name,
            autofocus: widget.player == null,
            maxLength: CpuPlayer.maxNameLength,
            decoration: InputDecoration(labelText: l10n.cpuName),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.m),
          Row(
            children: [
              Expanded(child: Text(l10n.cpuAverage, style: theme.textTheme.titleSmall)),
              Text('${_average.round()}', style: theme.textTheme.headlineSmall),
            ],
          ),
          Slider(
            key: const Key('cpu-average'),
            value: _average,
            min: CpuPlayer.minAverage,
            max: CpuPlayer.maxAverage,
            divisions: (CpuPlayer.maxAverage - CpuPlayer.minAverage).round(),
            onChanged: (v) => setState(() => _average = v.roundToDouble()),
          ),
        ],
      ),
      actions: [
        if (widget.player != null)
          TextButton(
            key: const Key('cpu-delete'),
            onPressed: () => Navigator.pop(context, const _EditResult(delete: true)),
            style: TextButton.styleFrom(foregroundColor: context.dartColors.danger),
            child: Text(l10n.cpuDelete),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cpuCancel)),
        FilledButton(key: const Key('cpu-save'), onPressed: _save, child: Text(l10n.cpuSave)),
      ],
    );
  }
}
