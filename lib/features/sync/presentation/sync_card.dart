import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../../second_screen/presentation/second_screen_page.dart';
import '../data/sync_client.dart';
import '../domain/sync_role.dart';
import 'sync_controller.dart';

/// IPv4-Adressen dieses Rechners, als Hinweis für die anderen Geräte.
final localAddressesProvider = FutureProvider<List<String>>((ref) async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [for (final i in interfaces) for (final a in i.addresses) if (!a.isLoopback && !a.isLinkLocal) a.address];
  } on Exception {
    return const [];
  }
});

String formatSyncTime(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final time = '${two(t.hour)}:${two(t.minute)}';
  final sameDay = t.year == n.year && t.month == n.month && t.day == n.day;
  return sameDay ? time : '${two(t.day)}.${two(t.month)}. $time';
}

/// Einstellungen für den Abgleich im Heimnetz.
class SyncCard extends ConsumerWidget {
  const SyncCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final roles = [SyncRole.off, if (canBeHub || settings.syncRole == SyncRole.hub) SyncRole.hub, SyncRole.client];

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<SyncRole>(
            groupValue: settings.syncRole,
            onChanged: (v) {
              if (v != null) notifier.update((x) => x.copyWith(syncRole: v));
            },
            child: Column(
              children: [
                for (final role in roles)
                  RadioListTile<SyncRole>(
                    key: Key('sync-role-${role.name}'),
                    value: role,
                    secondary: Icon(switch (role) {
                      SyncRole.off => Icons.sync_disabled_rounded,
                      SyncRole.hub => Icons.hub_rounded,
                      SyncRole.client => Icons.sync_rounded,
                    }),
                    title: Text(switch (role) {
                      SyncRole.off => l10n.syncRoleOff,
                      SyncRole.hub => l10n.syncRoleHub,
                      SyncRole.client => l10n.syncRoleClient,
                    }),
                    subtitle: Text(switch (role) {
                      SyncRole.off => l10n.syncRoleOffHint,
                      SyncRole.hub => canBeHub ? l10n.syncRoleHubHint : l10n.syncHubOnlyDesktop,
                      SyncRole.client => l10n.syncRoleClientHint,
                    }),
                  ),
              ],
            ),
          ),
          if (settings.syncRole == SyncRole.hub && canBeHub)
            const Padding(padding: EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.m), child: _HubPanel()),
          if (settings.syncRole == SyncRole.client)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.m),
              child: _ClientPanel(settings: settings),
            ),
        ],
      ),
    );
  }
}

class _HubPanel extends ConsumerWidget {
  const _HubPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final sync = ref.watch(syncControllerProvider);
    final addresses = ref.watch(localAddressesProvider).value ?? const [];
    final status = sync.hubError != null
        ? Text(l10n.syncHubFailed(sync.hubError!), style: TextStyle(color: context.dartColors.danger))
        : Text(sync.hubRunning ? l10n.syncHubRunning(settings.syncPort) : l10n.syncHubStarting);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.syncHubCode, style: theme.textTheme.bodySmall),
                  SelectableText(
                    settings.syncKey,
                    key: const Key('sync-hub-code'),
                    style: theme.textTheme.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()], letterSpacing: 4),
                  ),
                ],
              ),
            ),
            TextButton(
              key: const Key('sync-new-code'),
              onPressed: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(syncKey: newSyncKey())),
              child: Text(l10n.syncHubNewCode),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        status,
        if (addresses.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          SelectableText(l10n.syncHubAddresses(addresses.join(', ')), key: const Key('sync-hub-addresses')),
        ],
        if (sync.hubLastReceived != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.syncHubLastReceived(formatSyncTime(sync.hubLastReceived!))),
        ],
        if (sync.hubRunning) ...[
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Icon(Icons.tv_rounded, size: 18, color: sync.screenViewers > 0 ? context.dartColors.success : context.dartColors.textMuted),
              const SizedBox(width: AppSpacing.s),
              Expanded(child: Text(l10n.syncScreenViewers(sync.screenViewers), key: const Key('sync-screen-viewers'))),
            ],
          ),
          if (addresses.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              l10n.syncScreenBrowser('http://${addresses.first}:${settings.syncPort}/screen'),
              key: const Key('sync-screen-url'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.s),
        Text(l10n.syncFirewallHint(settings.syncPort), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ClientPanel extends ConsumerStatefulWidget {
  const _ClientPanel({required this.settings});
  final AppSettings settings;

  @override
  ConsumerState<_ClientPanel> createState() => _ClientPanelState();
}

class _ClientPanelState extends ConsumerState<_ClientPanel> {
  late final _host = TextEditingController(text: widget.settings.syncHost);
  late final _code = TextEditingController(text: widget.settings.syncKey);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _host.dispose();
    _code.dispose();
    super.dispose();
  }

  String? get _autodartsHost {
    final h = widget.settings.autodartsHost.trim();
    return (h.isEmpty || h == '127.0.0.1' || h == 'localhost') ? null : h;
  }

  Future<void> _apply({bool syncAfter = true}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final host = _host.text.trim();
    final key = _code.text.trim();
    final s = ref.read(settingsProvider);
    if (s.syncHost != host || s.syncKey != key) {
      // Neue Einstellungen bauen den Abgleich neu auf; der gleicht dann von
      // selbst ab.
      await ref.read(settingsProvider.notifier).update((x) => x.copyWith(syncHost: host, syncKey: key));
    } else if (syncAfter) {
      await ref.read(syncControllerProvider.notifier).syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sync = ref.watch(syncControllerProvider);
    final suggestion = _autodartsHost;

    final String statusText;
    Color? statusColor;
    if (sync.syncing) {
      statusText = l10n.syncSyncing;
    } else if (sync.failure != null) {
      statusColor = context.dartColors.danger;
      statusText = switch (sync.failure!) {
        SyncFailure.unreachable => l10n.syncErrUnreachable,
        SyncFailure.wrongKey => l10n.syncErrWrongKey,
        SyncFailure.notDartLab => l10n.syncErrNotDartLab,
        SyncFailure.server => l10n.syncErrServer(sync.failureDetail ?? ''),
      };
    } else if (sync.lastSync != null) {
      final r = sync.lastReport!;
      statusText = l10n.syncLast(formatSyncTime(sync.lastSync!), r.sent, r.received);
    } else {
      statusText = l10n.syncNever;
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  key: const Key('sync-host-field'),
                  controller: _host,
                  decoration: InputDecoration(labelText: l10n.syncHost, hintText: '192.168.178.20'),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  validator: (v) => (v == null || v.trim().isEmpty || v.contains(' ')) ? l10n.settingsHostInvalid : null,
                  onFieldSubmitted: (_) => _apply(),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: const Key('sync-code-field'),
                  controller: _code,
                  decoration: InputDecoration(labelText: l10n.syncCode),
                  keyboardType: TextInputType.number,
                  autocorrect: false,
                  validator: (v) => (v == null || v.trim().isEmpty) ? l10n.syncCodeInvalid : null,
                  onFieldSubmitted: (_) => _apply(),
                ),
              ),
            ],
          ),
          if (suggestion != null && _host.text.trim().isEmpty)
            TextButton(
              key: const Key('sync-use-autodarts-host'),
              onPressed: () => setState(() => _host.text = suggestion),
              child: Text(l10n.syncUseAutodartsHost(suggestion)),
            ),
          const SizedBox(height: AppSpacing.m),
          Text(statusText, key: const Key('sync-status'), style: theme.textTheme.bodySmall?.copyWith(color: statusColor)),
          const SizedBox(height: AppSpacing.m),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.m,
            runSpacing: AppSpacing.s,
            children: [
              OutlinedButton.icon(
                key: const Key('sync-open-screen'),
                onPressed: widget.settings.syncHost.trim().isEmpty ? null : () => context.push(secondScreenRoute),
                icon: const Icon(Icons.tv_rounded),
                label: Text(l10n.syncScreenOpen),
              ),
              FilledButton.icon(
                key: const Key('sync-now'),
                onPressed: sync.syncing ? null : _apply,
                icon: const Icon(Icons.sync_rounded),
                label: Text(l10n.syncNow),
              ),
            ],
            ),
          ),
        ],
      ),
    );
  }
}
