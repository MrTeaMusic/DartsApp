import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../caller.dart';
import 'caller_sound_pack_section.dart';

/// Einstellungen des Callers für den Optionen-Bildschirm.
class CallerSettingsCard extends ConsumerWidget {
  const CallerSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(callerSettingsProvider);
    final notifier = ref.read(callerSettingsProvider.notifier);
    // Beispiele in der gewählten Sprache, direkt aus dem Satz-Baukasten.
    final phrases = CallerPhrases.of(s.language);
    String examples(List<CallerPhrase> list) => list.map((p) => '„${p.text}“').join(', ');

    Widget announceSwitch(String key, bool value, String title, String subtitle, CallerSettings Function(bool) change) =>
        SwitchListTile(
          key: Key('caller-$key'),
          value: value,
          onChanged: s.enabled ? (v) => notifier.update((_) => change(v)) : null,
          title: Text(title),
          subtitle: Text(subtitle),
          dense: true,
        );

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('caller-enabled'),
            value: s.enabled,
            onChanged: (v) => notifier.update((x) => x.copyWith(enabled: v)),
            title: Text(l10n.callerEnabled),
            subtitle: Text(l10n.callerEnabledHint),
            secondary: const Icon(Icons.record_voice_over_rounded),
          ),
          if (s.enabled) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s),
              child: SegmentedButton<CallerLanguage>(
                key: const Key('caller-language'),
                segments: [
                  ButtonSegment(value: CallerLanguage.english, label: Text(l10n.callerLanguageEnglish)),
                  ButtonSegment(value: CallerLanguage.german, label: Text(l10n.callerLanguageGerman)),
                ],
                selected: {s.language},
                onSelectionChanged: (v) => notifier.update((x) => x.copyWith(language: v.first)),
              ),
            ),
            _SliderRow(
              sliderKey: const Key('caller-volume'),
              icon: Icons.volume_up_rounded,
              label: l10n.callerVolume,
              value: s.volume,
              min: 0,
              max: 1,
              onChanged: (v) => notifier.update((x) => x.copyWith(volume: v)),
            ),
            _SliderRow(
              sliderKey: const Key('caller-rate'),
              icon: Icons.speed_rounded,
              label: l10n.callerRate,
              value: s.rate,
              min: CallerSettings.minRate,
              max: CallerSettings.maxRate,
              onChanged: (v) => notifier.update((x) => x.copyWith(rate: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, 0),
              child: Kicker(l10n.callerAnnounce),
            ),
            announceSwitch(
              'scores',
              s.announceScores,
              l10n.callerAnnounceScores,
              examples([phrases.score(60), phrases.score(180), phrases.noScore(), phrases.bust()]),
              (v) => s.copyWith(announceScores: v),
            ),
            announceSwitch(
              'remaining',
              s.announceRemaining,
              l10n.callerAnnounceRemaining,
              examples([phrases.requires(32)]),
              (v) => s.copyWith(announceRemaining: v),
            ),
            announceSwitch(
              'checkout',
              s.announceCheckout,
              l10n.callerAnnounceCheckout,
              examples([phrases.gameShot(GameShotKind.leg)]),
              (v) => s.copyWith(announceCheckout: v),
            ),
            announceSwitch(
              'gameOn',
              s.announceGameOn,
              l10n.callerAnnounceGameOn,
              examples([phrases.gameOn()]),
              (v) => s.copyWith(announceGameOn: v),
            ),
            const CallerSoundPackSection(),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.s),
              child: LayoutBuilder(builder: (context, c) {
                final hint = Text(l10n.callerGamesHint, style: theme.textTheme.bodySmall);
                final preview = OutlinedButton.icon(
                  key: const Key('caller-preview'),
                  onPressed: () => ref.read(callerProvider).preview(),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(l10n.callerPreview),
                );
                // Schmal: Hinweis über dem Knopf, sonst nebeneinander.
                if (c.maxWidth < 440) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [hint, const SizedBox(height: AppSpacing.s), preview],
                  );
                }
                return Row(
                  children: [Expanded(child: hint), const SizedBox(width: AppSpacing.m), preview],
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.sliderKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final Key sliderKey;
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: AppSpacing.m),
            SizedBox(width: 96, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: Slider(
                key: sliderKey,
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      );
}
