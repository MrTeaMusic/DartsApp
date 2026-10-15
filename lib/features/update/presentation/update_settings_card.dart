import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../data/update_client.dart';
import 'update_banner.dart';
import 'update_controller.dart';

/// Optionen › Updates: laufende Version und „Nach Updates suchen“.
class UpdateSettingsCard extends ConsumerWidget {
  const UpdateSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final s = ref.watch(updateControllerProvider);
    final ctrl = ref.read(updateControllerProvider.notifier);
    final current = s.current;
    final checking = s.status == UpdateStatus.checking;

    final versionText = current.isDevBuild
        ? l10n.updateDevBuildLabel(current.version)
        : l10n.updateBuildLabel(current.version, current.build);

    final (String status, Color? statusColor) = switch (s.status) {
      UpdateStatus.checking => (l10n.updateChecking, null),
      UpdateStatus.upToDate => (l10n.updateUpToDate, colors.success),
      UpdateStatus.available => (l10n.updateAvailableStatus(updateBuildText(context, s.latest!.build)), theme.colorScheme.primary),
      UpdateStatus.devBuild => (l10n.updateDevStatus(updateBuildText(context, s.latest!.build)), null),
      UpdateStatus.failed => (_failureText(context, s.failure), colors.warning),
      UpdateStatus.idle when s.updateAvailable => (l10n.updateAvailableStatus(updateBuildText(context, s.latest!.build)), theme.colorScheme.primary),
      UpdateStatus.idle when s.lastChecked != null => (l10n.updateLastChecked(_when(s.lastChecked!)), null),
      UpdateStatus.idle => (current.isDevBuild ? l10n.updateDevHint : l10n.updateAutoHint, null),
    };

    final button = OutlinedButton.icon(
      key: const Key('update-check'),
      onPressed: checking ? null : () => ctrl.check(),
      icon: checking
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh_rounded),
      label: Text(l10n.updateCheckButton),
    );

    return AppCard(
      key: const Key('update-settings-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            final info = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBadge(icon: Icons.system_update_alt_rounded, size: 40),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.settingsVersion(versionText), key: const Key('update-version'), style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        key: const Key('update-status'),
                        style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
                      ),
                    ],
                  ),
                ),
              ],
            );
            if (c.maxWidth >= 520) {
              return Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: AppSpacing.m),
                  button,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: AppSpacing.m), button],
            );
          }),
          if (s.updateAvailable) ...[
            const Divider(height: AppSpacing.xl),
            const UpdateActions(showLater: false),
          ] else if (s.status == UpdateStatus.devBuild) ...[
            const SizedBox(height: AppSpacing.s),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('update-release-page'),
                onPressed: ctrl.openReleasePage,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(l10n.updateReleasePage),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _failureText(BuildContext context, UpdateFailure? f) {
    final l10n = context.l10n;
    return switch (f) {
      UpdateFailure.offline => l10n.updateErrorOffline,
      UpdateFailure.rateLimited => l10n.updateErrorRateLimit,
      UpdateFailure.noRelease => l10n.updateErrorNoRelease,
      _ => l10n.updateErrorOther,
    };
  }

  static String _when(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}. ${two(t.hour)}:${two(t.minute)}';
  }
}
