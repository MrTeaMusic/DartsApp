import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/settings/app_settings.dart';
import '../../autodarts_live/presentation/autodarts_live_routes.dart';
import '../../backup/presentation/backup_card.dart';
import '../../board/presentation/board_style.dart';
import '../../board/presentation/dartboard_view.dart';
import '../../caller/presentation/caller_settings_card.dart';
import '../../dart_source/domain/coordinate_calibration.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../dart_source/presentation/diagnostics_dialog.dart';
import '../../dart_source/presentation/recording_sheet.dart';
import '../../dart_source/presentation/source_status_badge.dart';
import '../../matches/domain/bot_pace.dart';
import '../../profiles/presentation/profiles_card.dart';
import '../../progress/presentation/daily_goal_card.dart';
import '../../progress/presentation/progress_texts.dart';
import '../../sync/presentation/sync_card.dart';
import '../../update/presentation/update_settings_card.dart';

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
              const SizedBox(height: AppSpacing.l),
              Kicker(l10n.settingsPlayView),
              const SizedBox(height: AppSpacing.s),
              SegmentedButton<PlayView>(
                key: const Key('playview-selector'),
                segments: [
                  ButtonSegment(value: PlayView.arena, label: Text(l10n.settingsPlayViewArena)),
                  ButtonSegment(value: PlayView.look, label: Text(l10n.settingsPlayViewLook)),
                ],
                selected: {settings.playView},
                onSelectionChanged: (s) => notifier.update((x) => x.copyWith(playView: s.first)),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                settings.playView == PlayView.arena ? l10n.settingsPlayViewArenaHint : l10n.settingsPlayViewLookHint,
                key: const Key('playview-hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.l),
              Kicker(l10n.settingsBoardStyle),
              const SizedBox(height: AppSpacing.s),
              const _BoardStylePicker(),
              const SizedBox(height: AppSpacing.m),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: SwitchListTile(
                  key: const Key('double-zoom-switch'),
                  value: settings.doubleZoom,
                  onChanged: (v) => notifier.update((x) => x.copyWith(doubleZoom: v)),
                  title: Text(l10n.settingsDoubleZoom),
                  subtitle: Text(l10n.settingsDoubleZoomHint),
                  secondary: const Icon(Icons.zoom_in_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: SwitchListTile(
                  key: const Key('tempo-hint-switch'),
                  value: settings.tempoHint,
                  onChanged: (v) => notifier.update((x) => x.copyWith(tempoHint: v)),
                  title: Text(l10n.settingsTempoHint),
                  subtitle: Text(l10n.settingsTempoHintHint),
                  secondary: const Icon(Icons.timer_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.l),
              Kicker(l10n.settingsBotPace),
              const SizedBox(height: AppSpacing.s),
              SegmentedButton<BotPace>(
                key: const Key('bot-pace-selector'),
                // Ohne Haken bleibt am Telefon Platz für „Gemütlich“ in einer Zeile.
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: BotPace.quick, label: Text(l10n.settingsBotPaceQuick)),
                  ButtonSegment(value: BotPace.relaxed, label: Text(l10n.settingsBotPaceRelaxed)),
                  ButtonSegment(value: BotPace.veryRelaxed, label: Text(l10n.settingsBotPaceVeryRelaxed)),
                ],
                selected: {settings.botPace},
                onSelectionChanged: (s) => notifier.update((x) => x.copyWith(botPace: s.first)),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                switch (settings.botPace) {
                  BotPace.quick => l10n.settingsBotPaceQuickHint,
                  BotPace.relaxed => l10n.settingsBotPaceRelaxedHint,
                  BotPace.veryRelaxed => l10n.settingsBotPaceVeryRelaxedHint,
                },
                key: const Key('bot-pace-hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SectionGap(),
              SectionHeader(l10n.settingsDailyGoal),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: ListTile(
                  key: const Key('settings-daily-goal'),
                  leading: const Icon(Icons.track_changes_rounded),
                  title: Text(l10n.dgPerDay(settings.dailyGoal.amount, l10n.goalUnit(settings.dailyGoal.unit))),
                  subtitle: Text(l10n.dgRules),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showDailyGoalEditor(context),
                ),
              ),
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
              SectionHeader(l10n.updateTitle),
              const UpdateSettingsCard(),
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
            ],
      ),
    );
  }
}

/// Vier Vorschau-Kacheln; Antippen wechselt den Look sofort.
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
      (DartLookId.arena, l10n.lookArenaName, l10n.lookArenaText),
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
        // Breit: alle vier nebeneinander; sonst zwei mal zwei.
        final perRow = c.maxWidth >= 900 ? looks.length : 2;
        return Column(
          children: [
            for (var start = 0; start < looks.length; start += perRow) ...[
              if (start > 0) SizedBox(height: gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < perRow; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    Expanded(
                      child: start + i < looks.length
                          ? tile(looks[start + i].$1, looks[start + i].$2, looks[start + i].$3)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
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

/// Auswahl der Scheibe mit kleiner Vorschau; gilt sofort überall.
class _BoardStylePicker extends ConsumerWidget {
  const _BoardStylePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final look = context.look;
    final current = ref.watch(settingsProvider.select((s) => s.boardStyle));
    final styles = [
      (BoardStyle.tournament, l10n.boardStyleTournament, l10n.boardStyleTournamentText),
      (BoardStyle.turquoise, l10n.boardStyleTurquoise, l10n.boardStyleTurquoiseText),
      (BoardStyle.classic, l10n.boardStyleClassic, l10n.boardStyleClassicText),
    ];
    Widget tile(BoardStyle style, String name, String text, BoxConstraints c) {
      final selected = style == current;
      return Semantics(
        selected: selected,
        button: true,
        label: name,
        child: Material(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(look.radiusL),
            side: BorderSide(
              color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('board-style-${style.name}'),
            onTap: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(boardStyle: style)),
            child: Padding(
              padding: EdgeInsets.all(c.maxWidth >= 560 ? AppSpacing.m : AppSpacing.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 132),
                      child: IgnorePointer(child: ExcludeSemantics(child: DartboardView(style: style))),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Row(
                    children: [
                      Expanded(child: Text(name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                      if (selected) Icon(Icons.check_circle_rounded, size: 20, color: theme.colorScheme.primary),
                    ],
                  ),
                  Text(text, style: theme.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 300 ? 3 : 2;
      final gap = look.gridGap;
      final width = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (style, name, text) in styles) SizedBox(width: width, child: tile(style, name, text, c)),
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
            const Divider(height: AppSpacing.xl),
            // Autodarts Live: beim Start direkt mitschreiben.
            SwitchListTile(
              key: const Key('live-autostart'),
              contentPadding: EdgeInsets.zero,
              value: widget.settings.autodartsLiveAutoStart,
              onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(autodartsLiveAutoStart: v)),
              title: Text(l10n.liveAutoStart),
              subtitle: Text(l10n.liveAutoStartHint),
              secondary: const Icon(Icons.hearing_rounded),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('open-autodarts-live-settings'),
                onPressed: () => context.go(AutodartsLiveRoutes.live),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded),
                label: Text(l10n.liveOpen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
