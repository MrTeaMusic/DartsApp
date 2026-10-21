import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../domain/tempo_stats.dart';

/// Ist das leise Wurftempo in den Spielansichten eingeschaltet (Optionen)?
final tempoHintEnabledProvider = Provider<bool>((ref) => ref.watch(settingsProvider.select((s) => s.tempoHint)));

/// „Aufnahme 9 s · Ø 3,1 s je Dart“; `null`, wenn es nichts zu zeigen gibt.
String? tempoHintText(AppLocalizations l10n, LiveTempo? tempo) {
  if (tempo == null) return null;
  final parts = [
    if (tempo.visit != null) l10n.tempoLiveVisit(formatSeconds(tempo.visit!)),
    if (tempo.perDart != null) l10n.tempoLivePerDart(formatSeconds(tempo.perDart!)),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Text für die Spielansicht oder `null`, wenn das Tempo in den Optionen aus
/// ist oder keine verlässlichen Zeiten vorliegen (Simulator, manuelle
/// Eingabe). Es gibt keinen Zähler und keine Uhr: Der Text ändert sich nur,
/// wenn ein Dart dazukommt.
String? tempoHintLine(WidgetRef ref, AppLocalizations l10n, LiveTempo? tempo) =>
    ref.watch(tempoHintEnabledProvider) ? tempoHintText(l10n, tempo) : null;

/// Leise Zeile mit dem Tempo der Aufnahme: gedämpfte Schrift, kein Warnton.
/// Für die Looks TV, Clean und Lab; die Arena-Ansicht zeigt den Text in
/// ihren Meldungen unter dem Board.
class TempoHint extends ConsumerWidget {
  const TempoHint({super.key, required this.tempo});
  final LiveTempo? tempo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = tempoHintLine(ref, context.l10n, tempo);
    if (text == null) return const SizedBox.shrink();
    final colors = context.dartColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: colors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              text,
              key: const Key('tempo-hint'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
