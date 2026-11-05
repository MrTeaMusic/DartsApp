import 'package:flutter/material.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../share/shared_match.dart';

/// Hinweis über einem geteilten Match: von wem es kommt und dass es nicht
/// in die eigene Statistik geht.
class SharedMatchBanner extends StatelessWidget {
  const SharedMatchBanner({super.key, required this.match});
  final SharedMatch match;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final accent = theme.colorScheme.primary;
    final name = match.player.trim().isEmpty ? l10n.sharedMatchSomeone : match.player.trim();
    return Container(
      key: const Key('shared-match-banner'),
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(context.look.radiusM),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppIcon(Icons.mark_email_read_rounded, size: 22, color: accent),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.sharedMatchFrom(name), style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.sharedMatchNotSaved,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
