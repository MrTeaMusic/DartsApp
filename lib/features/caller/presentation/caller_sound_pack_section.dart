import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../caller.dart';

/// Eigene Sounddateien für den Caller: importieren, ersetzen, entfernen.
/// Teil der [CallerSettingsCard].
class CallerSoundPackSection extends ConsumerStatefulWidget {
  const CallerSoundPackSection({super.key});

  @override
  ConsumerState<CallerSoundPackSection> createState() => _CallerSoundPackSectionState();
}

class _CallerSoundPackSectionState extends ConsumerState<CallerSoundPackSection> {
  bool _busy = false;

  static bool get _canPickFolder =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath();
    if (path != null) await _import([path]);
  }

  Future<void> _pickFiles() async {
    final files = await openFiles(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Sounds',
        extensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'zip'],
        uniformTypeIdentifiers: ['public.audio', 'public.zip-archive'],
      ),
    ]);
    if (files.isNotEmpty) await _import([for (final f in files) f.path]);
  }

  Future<void> _import(List<String> sources) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    String message;
    try {
      final count = await ref.read(soundPackProvider.notifier).import(sources);
      if (count == null) {
        message = l10n.callerSoundsNone;
      } else {
        message = l10n.callerSoundsImported(count);
        await ref.read(callerSettingsProvider.notifier).update((s) => s.copyWith(useSoundPack: true));
      }
    } catch (e) {
      debugPrint('Caller: Import fehlgeschlagen: $e');
      message = l10n.callerSoundsFailed;
    }
    if (mounted) setState(() => _busy = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settings = ref.watch(callerSettingsProvider);
    final pack = ref.watch(soundPackProvider).value ?? CallerSoundPack.empty;

    final pickButtons = [
      if (_canPickFolder)
        FilledButton.tonalIcon(
          key: const Key('caller-sounds-folder'),
          onPressed: _busy ? null : _pickFolder,
          icon: const Icon(Icons.folder_open_rounded),
          label: Text(pack.isEmpty ? l10n.callerSoundsPickFolder : l10n.callerSoundsReplace),
        ),
      OutlinedButton.icon(
        key: const Key('caller-sounds-files'),
        onPressed: _busy ? null : _pickFiles,
        icon: const Icon(Icons.audio_file_rounded),
        label: Text(l10n.callerSoundsPickFiles),
      ),
      if (!pack.isEmpty)
        TextButton.icon(
          key: const Key('caller-sounds-remove'),
          onPressed: _busy ? null : () => ref.read(soundPackProvider.notifier).clear(),
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(l10n.callerSoundsRemove),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.l, 0),
          child: Kicker(l10n.callerSounds),
        ),
        if (pack.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, 0),
            child: Text(l10n.callerSoundsHint, style: theme.textTheme.bodySmall),
          )
        else
          SwitchListTile(
            key: const Key('caller-sounds-use'),
            value: settings.useSoundPack,
            onChanged: (v) => ref.read(callerSettingsProvider.notifier).update((s) => s.copyWith(useSoundPack: v)),
            title: Text(l10n.callerSoundsUse),
            subtitle: Text(_summary(l10n, pack)),
            secondary: const Icon(Icons.library_music_rounded),
            dense: true,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, 0),
          child: Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...pickButtons,
              if (_busy) const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('caller-sounds-names'),
            tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
            childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.s),
            expandedAlignment: Alignment.centerLeft,
            dense: true,
            title: Text(l10n.callerSoundsNames, style: theme.textTheme.bodyMedium),
            children: [SelectableText(l10n.callerSoundsNamesList, style: theme.textTheme.bodySmall)],
          ),
        ),
      ],
    );
  }

  static String _label(String key) => switch (key) {
        'bust' => 'Bust',
        'game_on' => 'Game on',
        'game_shot' => 'Game shot',
        'you_require' => 'You require',
        _ => key,
      };

  static String _summary(AppLocalizations l10n, CallerSoundPack pack) {
    final missing = pack.missingScores;
    final scores = missing.isEmpty
        ? l10n.callerSoundsScoresComplete
        : l10n.callerSoundsScoresMissing(
            missing.length,
            missing.length <= 6 ? missing.join(', ') : '${missing.take(6).join(', ')} …',
          );
    final lines = ['${l10n.callerSoundsCount(pack.length)} · $scores'];
    final voice = pack.missingExtras;
    if (voice.isNotEmpty) lines.add(l10n.callerSoundsVoiceFor(voice.map(_label).join(', ')));
    return lines.join('\n');
  }
}
