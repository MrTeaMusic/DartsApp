import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/design/components/components.dart';
import '../../../core/l10n.dart';
import '../data/profile_repository.dart';
import 'active_player.dart';

/// Profile wählen, anlegen, umbenennen und löschen.
class ProfilesCard extends ConsumerWidget {
  const ProfilesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final players = ref.watch(playersProvider).value ?? const <Player>[];
    final active = ref.watch(activePlayerProvider);
    final repo = ref.read(profileRepositoryProvider);

    return AppCard(
      padding: EdgeInsets.zero,
      child: RadioGroup<int>(
        groupValue: active?.id,
        onChanged: (id) {
          if (id != null) ref.read(activePlayerIdProvider.notifier).select(id);
        },
        child: Column(
          children: [
            for (final p in players)
              RadioListTile<int>(
                key: Key('profile-${p.id}'),
                value: p.id,
                title: Text(p.name),
                secondary: PopupMenuButton<String>(
                  key: Key('profile-menu-${p.id}'),
                  onSelected: (action) async {
                    if (action == 'rename') {
                      final name = await _askName(context, l10n.profileRename, p.name);
                      if (name != null) await repo.rename(p.id, name);
                    } else if (action == 'delete') {
                      final ok = await _confirmDelete(context, p.name);
                      if (ok) await repo.delete(p.id);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'rename', child: Text(l10n.profileRename)),
                    if (players.length > 1)
                      PopupMenuItem(key: const Key('profile-delete'), value: 'delete', child: Text(l10n.profileDelete)),
                  ],
                ),
              ),
            ListTile(
              key: const Key('profile-add'),
              leading: const Icon(Icons.person_add_alt_1_rounded),
              title: Text(l10n.profileAdd),
              onTap: () async {
                final name = await _askName(context, l10n.profileAdd, '');
                if (name == null) return;
                final id = await repo.create(name);
                await ref.read(activePlayerIdProvider.notifier).select(id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askName(BuildContext context, String title, String initial) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: title, initial: initial),
    );
    final clean = name == null ? null : ProfileRepository.clean(name);
    return clean == null || clean.isEmpty ? null : clean;
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.profileDeleteTitle(name)),
        content: Text(l10n.profileDeleteText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.gameCancelShort)),
          FilledButton(
            key: const Key('profile-delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.profileDelete),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});
  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('profile-name'),
        controller: _controller,
        autofocus: true,
        maxLength: ProfileRepository.maxNameLength,
        decoration: InputDecoration(labelText: l10n.profileName),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.gameCancelShort)),
        FilledButton(
          key: const Key('profile-save'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.goalsSave),
        ),
      ],
    );
  }
}
