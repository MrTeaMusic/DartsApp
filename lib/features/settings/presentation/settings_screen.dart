import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/app_version.dart';
import '../../../core/settings/app_settings.dart';
import '../../backup/presentation/backup_card.dart';
import '../../caller/presentation/caller_settings_card.dart';
import '../../dart_source/domain/coordinate_calibration.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../dart_source/presentation/diagnostics_dialog.dart';
import '../../dart_source/presentation/recording_sheet.dart';
import '../../dart_source/presentation/source_status_badge.dart';
import '../../profiles/presentation/profiles_card.dart';
import '../../sync/presentation/sync_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppPageBar(maxWidth: 720, title: Text(l10n.settingsTitle)),
      body: AppPage(
            children: [
              SectionHeader(l10n.profilesTitle),
              const ProfilesCard(),
              const SectionGap(),
              SectionHeader(l10n.settingsAppearance),
              const _LookPicker(),
              const SizedBox(height: AppSpacing.l),
              if (settings.look.supportsLight) ...[
                Kicker(l10n.settingsBrightness),
                const SizedBox(height: AppSpacing.s),
                SegmentedButton<ThemeMode>(
                  key: const Key('theme-selector'),
                  segments: [
                    ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark), icon: const Icon(Icons.dark_mode_rounded)),
                    ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight), icon: const Icon(Icons.light_mode_rounded)),
                    ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeSystem), icon: const Icon(Icons.brightness_auto_rounded)),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => notifier.update((x) => x.copyWith(themeMode: s.first)),
                ),
              ] else
                Text(l10n.settingsBrightnessFixed, key: const Key('theme-fixed'), style: Theme.of(context).textTheme.bodySmall),
              const SectionGap(),
              SectionHeader(l10n.settingsSource, trailing: const SourceStatusBadge()),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: RadioGroup<DartSourceKind>(
                  groupValue: settings.sourceKind,
                  onChanged: (v) {
                    if (v != null) notifier.update((x) => x.copyWith(sourceKind: v));
                  },
                  child: Column(
                    children: [
                      for (final kind in DartSourceKind.values)
                        RadioListTile<DartSourceKind>(
                          key: Key('source-${kind.name}'),
                          value: kind,
                          secondary: Icon(kind.icon),
                          title: Text(kind.label(l10n)),
                          subtitle: Text(switch (kind) {
                            DartSourceKind.simulator => l10n.sourceSimulatorHint,
                            DartSourceKind.manual => l10n.sourceManualHint,
                            DartSourceKind.autodartsLocal => l10n.sourceAutodartsHint,
                          }),
                        ),
                    ],
                  ),
                ),
              ),
              if (settings.sourceKind == DartSourceKind.autodartsLocal) ...[
                const SizedBox(height: AppSpacing.m),
                _AutodartsConnectionCard(settings: settings),
              ],
              const SectionGap(),
              SectionHeader(l10n.settingsFeedback),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: settings.soundEnabled,
                      onChanged: (v) => notifier.update((x) => x.copyWith(soundEnabled: v)),
                      title: Text(l10n.settingsSound),
                      subtitle: Text(l10n.settingsSoundHint),
                      secondary: const Icon(Icons.volume_up_rounded),
                    ),
                    SwitchListTile(
                      value: settings.hapticsEnabled,
                      onChanged: (v) => notifier.update((x) => x.copyWith(hapticsEnabled: v)),
                      title: Text(l10n.settingsHaptics),
                      subtitle: Text(l10n.settingsHapticsHint),
                      secondary: const Icon(Icons.vibration_rounded),
                    ),
                  ],
                ),
              ),
              const SectionGap(),
              SectionHeader(l10n.callerTitle),
              const CallerSettingsCard(),
              const SectionGap(),
              SectionHeader(l10n.syncTitle),
              const SyncCard(),
              const SectionGap(),
              SectionHeader(l10n.backupTitle),
              const BackupCard(),
              const SectionGap(),
              SectionHeader(l10n.settingsDeveloper),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  children: [
                    ListTile(
                      key: const Key('open-debug'),
                      leading: const Icon(Icons.terminal_rounded),
                      title: Text(l10n.debugTitle),
                      subtitle: Text(l10n.settingsDebugHint),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.go(Routes.debug),
                    ),
                    SwitchListTile(
                      value: settings.logRawToFile,
                      onChanged: (v) => notifier.update((x) => x.copyWith(logRawToFile: v)),
                      title: Text(l10n.settingsLogToFile),
                      subtitle: Text(l10n.settingsLogToFileHint),
                      secondary: const Icon(Icons.save_alt_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Center(child: Text(l10n.settingsVersion(appVersion), style: Theme.of(context).textTheme.bodySmall)),
            ],
      ),
    );
  }
}

/// Drei Vorschau-Kacheln; Antippen wechselt den Look sofort.
class _LookPicker extends ConsumerWidget {
  const _LookPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final platform = MediaQuery.platformBrightnessOf(context);
    final cleanBrightness = switch (settings.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platform,
    };
    final looks = [
      (DartLookId.tv, l10n.lookTvName, l10n.lookTvText),
      (DartLookId.clean, l10n.lookCleanName, l10n.lookCleanText),
      (DartLookId.lab, l10n.lookLabName, l10n.lookLabText),
    ];
    return LayoutBuilder(builder: (context, c) {
      final row = c.maxWidth >= 560;
      final gap = context.look.gridGap;
      Widget tile(DartLookId id, String name, String text) => LookPickerTile(
            key: Key('look-${id.name}'),
            id: id,
            title: name,
            subtitle: text,
            previewLabel: l10n.lookPreviewScore,
            selected: settings.look == id,
            brightness: id.supportsLight ? cleanBrightness : Brightness.dark,
            horizontal: !row,
            onTap: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(look: id)),
          );
      if (row) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, (id, name, text)) in looks.indexed) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: tile(id, name, text)),
            ],
          ],
        );
      }
      return Column(
        children: [
          for (final (i, (id, name, text)) in looks.indexed) ...[
            if (i > 0) SizedBox(height: gap),
            tile(id, name, text),
          ],
        ],
      );
    });
  }
}

class _AutodartsConnectionCard extends ConsumerStatefulWidget {
  const _AutodartsConnectionCard({required this.settings});
  final AppSettings settings;

  @override
  ConsumerState<_AutodartsConnectionCard> createState() => _AutodartsConnectionCardState();
}

class _AutodartsConnectionCardState extends ConsumerState<_AutodartsConnectionCard> {
  late final _host = TextEditingController(text: widget.settings.autodartsHost);
  late final _port = TextEditingController(text: '${widget.settings.autodartsPort}');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _test() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    showDiagnosticsDialog(context, host: _host.text.trim(), port: int.parse(_port.text.trim()));
  }

  void _apply() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    ref.read(settingsProvider.notifier).update(
          (x) => x.copyWith(autodartsHost: _host.text.trim(), autodartsPort: int.parse(_port.text.trim())),
        );
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key: const Key('host-field'),
                    controller: _host,
                    decoration: InputDecoration(labelText: l10n.settingsHost, hintText: '192.168.0.42'),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    validator: (v) => (v == null || v.trim().isEmpty || v.contains(' ')) ? l10n.settingsHostInvalid : null,
                    onFieldSubmitted: (_) => _apply(),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: TextFormField(
                    key: const Key('port-field'),
                    controller: _port,
                    decoration: InputDecoration(labelText: l10n.settingsPort),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final p = int.tryParse(v?.trim() ?? '');
                      return (p == null || p < 1 || p > 65535) ? l10n.settingsPortInvalid : null;
                    },
                    onFieldSubmitted: (_) => _apply(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            Text(l10n.autodartsUnverified, style: theme.textTheme.bodySmall?.copyWith(color: context.dartColors.warning)),
            const SizedBox(height: AppSpacing.m),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                OutlinedButton.icon(
                  key: const Key('test-connection'),
                  onPressed: _test,
                  icon: const Icon(Icons.network_check_rounded),
                  label: Text(l10n.diagButton),
                ),
                FilledButton(key: const Key('apply-connection'), onPressed: _apply, child: Text(l10n.settingsApply)),
              ],
            ),
            const Divider(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.calibTitle, style: theme.textTheme.titleSmall),
                      Text(
                        describeCalibration(l10n, widget.settings.coordCalibration),
                        key: const Key('calibration-value'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!widget.settings.coordCalibration.isIdentity)
                  TextButton(
                    key: const Key('reset-calibration'),
                    onPressed: () => ref
                        .read(settingsProvider.notifier)
                        .update((x) => x.copyWith(coordCalibration: CoordinateCalibration.identity)),
                    child: Text(l10n.calibReset),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
