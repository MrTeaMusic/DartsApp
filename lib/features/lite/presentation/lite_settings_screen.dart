import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../../profiles/presentation/active_player.dart';
import '../../sync/domain/sync_role.dart';
import '../../sync/presentation/sync_card.dart';
import '../../update/presentation/update_controller.dart';
import '../../update/presentation/update_settings_card.dart';

/// Optionen der Lite-Variante: Verbindung, Update und „Über“. Nichts davon
/// ändert Spieldaten.
class LiteSettingsScreen extends ConsumerWidget {
  const LiteSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final players = ref.watch(playersProvider).value ?? const <Player>[];

    return Scaffold(
      appBar: AppPageBar(maxWidth: 720, title: Text(l10n.navSettings)),
      body: AppPage(
        listKey: const Key('lite-settings'),
        children: [
          SectionHeader(l10n.liteSectionConnection),
          AppCard(
            key: const Key('lite-connection-card'),
            child: CloudPanel(settings: settings, compact: true),
          ),
          const SizedBox(height: AppSpacing.s),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('lite-reset-setup'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _reset(context, ref),
              icon: const Icon(Icons.link_off_rounded),
              label: Text(l10n.liteResetSetup),
            ),
          ),
          // Nur wenn Ben mehrere Profile hat, gibt es etwas zu wählen.
          if (players.length > 1) ...[
            const SectionGap(),
            SectionHeader(l10n.liteSectionProfile),
            const _ProfileChoice(),
          ],
          const SectionGap(),
          SectionHeader(l10n.updateTitle),
          const UpdateSettingsCard(),
          const SectionGap(),
          SectionHeader(l10n.liteSectionAbout),
          const _AboutCard(),
        ],
      ),
    );
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('lite-reset-dialog'),
        title: Text(l10n.liteResetTitle),
        content: Text(l10n.liteResetText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.gameCancelShort)),
          FilledButton(
            key: const Key('lite-reset-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.liteResetConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Ohne Adresse und Geheimnis schickt der Router zur Einrichtung. Die
    // Daten auf dem Gerät bleiben.
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(syncRole: SyncRole.off, syncCloudUrl: '', syncCloudSecret: ''));
  }
}

/// Auswahl, wessen Statistik gezeigt wird (nur Ansicht, nichts wird geändert).
class _ProfileChoice extends ConsumerWidget {
  const _ProfileChoice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final players = ref.watch(playersProvider).value ?? const <Player>[];
    final active = ref.watch(activePlayerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.liteProfileHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.s),
        AppCard(
          key: const Key('lite-profile-card'),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: RadioGroup<int>(
            groupValue: active?.id,
            onChanged: (id) {
              if (id != null) ref.read(activePlayerIdProvider.notifier).select(id);
            },
            child: Column(
              children: [
                for (final p in players)
                  RadioListTile<int>(key: Key('lite-profile-${p.id}'), value: p.id, title: Text(p.name)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final current = ref.watch(currentBuildProvider);
    return AppCard(
      key: const Key('lite-about-card'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconBadge(icon: Icons.insights_rounded, size: 40),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.liteName, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  l10n.settingsVersion(
                    current.isDevBuild ? l10n.updateDevBuildLabel(current.version) : l10n.updateBuildLabel(current.version, current.build),
                  ),
                  key: const Key('lite-about-version'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.s),
                Text(l10n.liteAboutReadOnly, key: const Key('lite-about-readonly'), style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
