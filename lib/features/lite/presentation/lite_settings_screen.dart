import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
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
