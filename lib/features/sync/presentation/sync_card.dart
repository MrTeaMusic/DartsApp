import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../../second_screen/presentation/second_screen_page.dart';
import '../data/cloud_api.dart';
import '../data/cloud_crypto.dart';
import '../data/cloud_remote.dart';
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

/// Text und Farbe der Statuszeile unter den Eingabefeldern.
(String, Color?) syncStatusText(BuildContext context, SyncState sync) {
  final l10n = context.l10n;
  final cloud = sync.role == SyncRole.cloud;
  if (sync.syncing) return (l10n.syncSyncing, null);
  final failure = sync.failure;
  if (failure != null) {
    return (
      switch (failure) {
        SyncFailure.unreachable => cloud ? l10n.syncErrCloudUnreachable : l10n.syncErrUnreachable,
        SyncFailure.wrongKey => cloud ? l10n.syncErrCloudAuth : l10n.syncErrWrongKey,
        SyncFailure.notDartLab => cloud ? l10n.syncErrCloudNotDartLab : l10n.syncErrNotDartLab,
        SyncFailure.server => cloud ? l10n.syncErrCloudServer(sync.failureDetail ?? '') : l10n.syncErrServer(sync.failureDetail ?? ''),
        SyncFailure.wrongSecret => l10n.syncErrWrongSecret,
        SyncFailure.noVault => l10n.syncErrNoVault,
      },
      context.dartColors.danger,
    );
  }
  final last = sync.lastSync;
  if (last != null) {
    final r = sync.lastReport!;
    return (l10n.syncLast(formatSyncTime(last), r.sent, r.received), null);
  }
  return (l10n.syncNever, null);
}

/// Einstellungen für den Abgleich zwischen Geräten.
class SyncCard extends ConsumerWidget {
  const SyncCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final roles = [SyncRole.off, SyncRole.cloud, if (canBeHub || settings.syncRole == SyncRole.hub) SyncRole.hub, SyncRole.client];

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
                      SyncRole.cloud => Icons.cloud_sync_rounded,
                    }),
                    title: Text(switch (role) {
                      SyncRole.off => l10n.syncRoleOff,
                      SyncRole.hub => l10n.syncRoleHub,
                      SyncRole.client => l10n.syncRoleClient,
                      SyncRole.cloud => l10n.syncRoleCloud,
                    }),
                    subtitle: Text(switch (role) {
                      SyncRole.off => l10n.syncRoleOffHint,
                      SyncRole.hub => canBeHub ? l10n.syncRoleHubHint : l10n.syncHubOnlyDesktop,
                      SyncRole.client => l10n.syncRoleClientHint,
                      SyncRole.cloud => l10n.syncRoleCloudHint,
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
          if (settings.syncRole == SyncRole.cloud)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.m),
              child: _CloudPanel(settings: settings),
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

    final (statusText, statusColor) = syncStatusText(context, sync);

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

class _CloudPanel extends ConsumerStatefulWidget {
  const _CloudPanel({required this.settings});
  final AppSettings settings;

  @override
  ConsumerState<_CloudPanel> createState() => _CloudPanelState();
}

class _CloudPanelState extends ConsumerState<_CloudPanel> {
  late final _url = TextEditingController(text: widget.settings.syncCloudUrl);
  late final _secret = TextEditingController(
    text: CloudSecret.tryParse(widget.settings.syncCloudSecret)?.display ?? widget.settings.syncCloudSecret,
  );
  final _formKey = GlobalKey<FormState>();

  /// Das Geheimnis wurde hier gerade erzeugt: Der Tresor wird neu angelegt.
  /// Sonst wird zuerst geprüft, ob es ihn gibt (Tippfehler abfangen).
  bool _generated = false;
  bool _checking = false;
  SyncFailure? _error;

  @override
  void dispose() {
    _url.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _generate() {
    setState(() {
      _secret.text = CloudSecret.generate().display;
      _generated = true;
      _error = null;
    });
  }

  Future<void> _copy() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _secret.text));
    messenger.showSnackBar(SnackBar(content: Text(l10n.syncCloudCopied)));
  }

  /// Prüft Adresse und Tresor, speichert dann und gleicht ab.
  Future<void> _apply() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final url = CloudApi.tryParseUrl(_url.text)!.toString();
    final secret = CloudSecret.tryParse(_secret.text)!;
    final s = ref.read(settingsProvider);
    final changed = s.syncCloudUrl != url || s.syncCloudSecret != secret.text;
    if (!changed) {
      await ref.read(syncControllerProvider.notifier).syncNow();
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final failure = await _check(url, secret, mustExist: !_generated);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = failure;
    });
    if (failure != null) return;
    // Neue Einstellungen bauen den Abgleich neu auf; der gleicht dann von selbst ab.
    await ref.read(settingsProvider.notifier).update((x) => x.copyWith(syncCloudUrl: url, syncCloudSecret: secret.text));
    _generated = false;
  }

  Future<SyncFailure?> _check(String url, CloudSecret secret, {required bool mustExist}) async {
    final api = CloudApi(url, (await secret.keys()).token, client: ref.read(cloudHttpClientProvider)());
    try {
      await api.hello();
      if (mustExist && await CloudRemote(api, await secret.keys()).vaultExists() == false) return SyncFailure.noVault;
      return null;
    } on SyncException catch (e) {
      return e.kind;
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sync = ref.watch(syncControllerProvider);
    final saved = widget.settings.syncCloudSecret.isNotEmpty;
    var (statusText, statusColor) = syncStatusText(context, sync);
    final error = _error;
    if (error != null) {
      statusColor = context.dartColors.danger;
      statusText = switch (error) {
        SyncFailure.noVault => l10n.syncErrNoVault,
        SyncFailure.unreachable => l10n.syncErrCloudUnreachable,
        SyncFailure.notDartLab => l10n.syncErrCloudNotDartLab,
        SyncFailure.wrongKey => l10n.syncErrCloudAuth,
        SyncFailure.wrongSecret => l10n.syncErrWrongSecret,
        SyncFailure.server => l10n.syncErrCloudServer(''),
      };
    } else if (_checking) {
      statusText = l10n.syncSyncing;
      statusColor = null;
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          TextFormField(
            key: const Key('sync-cloud-url-field'),
            controller: _url,
            decoration: InputDecoration(labelText: l10n.syncCloudUrl, hintText: 'dartlab-sync.dein-name.workers.dev'),
            keyboardType: TextInputType.url,
            autocorrect: false,
            validator: (v) => CloudApi.tryParseUrl(v ?? '') == null ? l10n.syncCloudUrlInvalid : null,
            onFieldSubmitted: (_) => _apply(),
          ),
          const SizedBox(height: AppSpacing.m),
          TextFormField(
            key: const Key('sync-cloud-secret-field'),
            controller: _secret,
            decoration: InputDecoration(
              labelText: l10n.syncCloudSecret,
              suffixIcon: IconButton(
                key: const Key('sync-cloud-copy'),
                tooltip: l10n.syncCloudCopy,
                onPressed: _secret.text.isEmpty ? null : _copy,
                icon: const Icon(Icons.copy_rounded),
              ),
            ),
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], letterSpacing: 1.5),
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            validator: (v) => CloudSecret.tryParse(v ?? '') == null ? l10n.syncCloudSecretInvalid : null,
            onChanged: (_) => setState(() {
              _generated = false;
              _error = null;
            }),
            onFieldSubmitted: (_) => _apply(),
          ),
          if (!saved || _generated) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton.icon(
              key: const Key('sync-cloud-generate'),
              onPressed: _generate,
              icon: const Icon(Icons.vpn_key_rounded),
              label: Text(l10n.syncCloudGenerate),
            ),
          ],
          if (_generated)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(l10n.syncCloudGenerated, key: const Key('sync-cloud-generated'), style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: AppSpacing.m),
          Text(statusText, key: const Key('sync-status'), style: theme.textTheme.bodySmall?.copyWith(color: statusColor)),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.syncCloudPrivacy, style: theme.textTheme.bodySmall?.copyWith(color: context.dartColors.textMuted)),
          const SizedBox(height: AppSpacing.m),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('sync-now'),
              onPressed: sync.syncing || _checking ? null : _apply,
              icon: const Icon(Icons.sync_rounded),
              label: Text(l10n.syncNow),
            ),
          ),
        ],
      ),
    );
  }
}
