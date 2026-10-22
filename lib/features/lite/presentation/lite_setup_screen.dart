import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../sync/data/cloud_api.dart';
import '../../sync/data/cloud_crypto.dart';
import '../../sync/data/sync_client.dart';
import '../domain/lite_gate.dart';
import 'lite_setup_controller.dart';

/// Einrichtung beim ersten Start: Adresse und Geheimnis des Cloud-Speichers.
/// Ohne Navigationsleiste; erst wenn die Daten geladen sind, geht es zur
/// Statistik.
class LiteSetupScreen extends ConsumerStatefulWidget {
  const LiteSetupScreen({super.key});

  @override
  ConsumerState<LiteSetupScreen> createState() => _LiteSetupScreenState();
}

class _LiteSetupScreenState extends ConsumerState<LiteSetupScreen> {
  final _url = TextEditingController();
  final _secret = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _url.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() => _secret.text = text);
    ref.read(liteSetupProvider.notifier).clearFailure();
  }

  Future<void> _connect() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final done = await ref.read(liteSetupProvider.notifier).connect(_url.text, _secret.text);
    if (done && mounted) context.go(LiteRoutes.stats);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final setup = ref.watch(liteSetupProvider);
    final busy = setup.busy;
    final clear = ref.read(liteSetupProvider.notifier).clearFailure;

    return Scaffold(
      body: SafeArea(
        child: AppPage(
          maxWidth: 520,
          listKey: const Key('lite-setup'),
          children: [
            const SizedBox(height: AppSpacing.l),
            const IconBadge(icon: Icons.insights_rounded, size: 56),
            const SizedBox(height: AppSpacing.l),
            Text(l10n.liteWelcomeTitle, key: const Key('lite-welcome-title'), style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.s),
            Text(l10n.liteWelcomeText, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.l),
            AppCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(child: Text(l10n.liteWelcomeAsk, key: const Key('lite-welcome-ask'), style: theme.textTheme.bodyMedium)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.l),
                    TextFormField(
                      key: const Key('lite-setup-url'),
                      controller: _url,
                      enabled: !busy,
                      decoration: InputDecoration(labelText: l10n.syncCloudUrl, hintText: l10n.liteSetupUrlHint),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      validator: (v) => CloudApi.tryParseUrl(v ?? '') == null ? l10n.syncCloudUrlInvalid : null,
                      onChanged: (_) => clear(),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    TextFormField(
                      key: const Key('lite-setup-secret'),
                      controller: _secret,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: l10n.syncCloudSecret,
                        helperText: l10n.liteSetupSecretHelper,
                        helperMaxLines: 3,
                        suffixIcon: IconButton(
                          key: const Key('lite-setup-paste'),
                          tooltip: l10n.liteSetupPaste,
                          onPressed: busy ? null : _paste,
                          icon: const Icon(Icons.content_paste_rounded),
                        ),
                      ),
                      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], letterSpacing: 1.5),
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => CloudSecret.tryParse(v ?? '') == null ? l10n.syncCloudSecretInvalid : null,
                      onChanged: (_) => clear(),
                      onFieldSubmitted: (_) => _connect(),
                    ),
                    const SizedBox(height: AppSpacing.l),
                    FilledButton.icon(
                      key: const Key('lite-setup-connect'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      onPressed: busy ? null : _connect,
                      icon: const Icon(Icons.link_rounded),
                      label: Text(l10n.liteSetupConnect),
                    ),
                  ],
                ),
              ),
            ),
            if (busy) ...[
              const SizedBox(height: AppSpacing.l),
              AppCard(
                key: const Key('lite-setup-progress'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      setup.phase == LiteSetupPhase.loading ? l10n.liteSetupLoading : l10n.liteSetupChecking,
                      key: const Key('lite-setup-progress-text'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.m),
                    const LinearProgressIndicator(),
                    if (setup.phase == LiteSetupPhase.loading) ...[
                      const SizedBox(height: AppSpacing.m),
                      Text(l10n.liteSetupLoadingHint, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ],
            if (setup.phase == LiteSetupPhase.failed) ...[
              const SizedBox(height: AppSpacing.l),
              AppCard(
                key: const Key('lite-setup-error'),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, color: colors.danger),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(
                      child: Text(
                        liteSetupErrorText(context, setup.failure ?? SyncFailure.server, setup.detail),
                        key: const Key('lite-setup-error-text'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.l),
          ],
        ),
      ),
    );
  }
}

/// Verständliche Meldung zu einem Fehler beim Einrichten.
String liteSetupErrorText(BuildContext context, SyncFailure failure, String? detail) {
  final l10n = context.l10n;
  return switch (failure) {
    SyncFailure.unreachable => l10n.liteSetupErrUnreachable,
    SyncFailure.notDartLab => l10n.liteSetupErrNotDartLab,
    SyncFailure.wrongKey => l10n.liteSetupErrAuth,
    SyncFailure.wrongSecret => l10n.liteSetupErrWrongSecret,
    SyncFailure.noVault => l10n.liteSetupErrNoVault,
    SyncFailure.server => l10n.liteSetupErrServer(detail ?? ''),
  };
}
