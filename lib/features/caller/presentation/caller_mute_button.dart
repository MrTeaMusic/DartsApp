import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n.dart';
import '../caller.dart';

/// Stumm-Knopf für die App-Leiste der Spielansicht. Schaltet dieselbe
/// Einstellung wie „Caller“ in den Optionen.
class CallerMuteButton extends ConsumerWidget {
  const CallerMuteButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(callerSettingsProvider.select((s) => s.enabled));
    return IconButton(
      key: const Key('caller-mute'),
      icon: Icon(enabled ? Icons.record_voice_over_rounded : Icons.voice_over_off_rounded),
      tooltip: enabled ? l10n.callerMute : l10n.callerUnmute,
      onPressed: () => ref.read(callerSettingsProvider.notifier).toggleEnabled(),
    );
  }
}
