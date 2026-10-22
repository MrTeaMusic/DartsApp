import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/lite.dart';
import '../domain/app_release.dart';
import 'update_controller.dart';

/// „Update verfügbar“-Karte auf der Startseite. Unsichtbar, solange es
/// nichts Neues gibt oder der Hinweis mit „Später“ weggeklickt wurde.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key, this.bottomGap = 0});

  /// Abstand unter der Karte (nur wenn sie sichtbar ist).
  final double bottomGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(updateControllerProvider.select((s) => s.showBanner));
    if (!show) return const SizedBox.shrink();
    final release = ref.watch(updateControllerProvider.select((s) => s.latest))!;
    // Knöpfe rechts nur vor dem Download; Fortschritt und Anleitung brauchen
    // die Breite und stehen darunter.
    final idle = ref.watch(updateControllerProvider.select((s) => s.downloadPhase == DownloadPhase.idle));
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final look = context.look;
    // Lite: eigener Text, und die Änderungen der Haupt-App gehen den Leser
    // dort nichts an.
    final lite = ref.watch(liteProvider);
    final notes = lite ? const <String>[] : release.shortNotes();
    final hidden = lite ? 0 : release.hiddenNoteCount();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: AppCard(
        key: const Key('update-banner'),
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 640;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Kicker(lite ? l10n.liteUpdateKicker : l10n.updateBannerKicker, color: theme.colorScheme.primary),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                lite
                    ? l10n.liteUpdateTitle(updateBuildText(context, release.build))
                    : l10n.updateBannerTitle(updateBuildText(context, release.build)),
                style: theme.textTheme.titleMedium,
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                for (final n in notes)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: theme.textTheme.bodySmall),
                        Expanded(
                          child: Text(n, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                if (hidden > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l10n.updateMoreNotes(hidden),
                      style: theme.textTheme.bodySmall?.copyWith(color: context.dartColors.textMuted),
                    ),
                  ),
              ],
            ],
          );
          final side = wide && idle && !lite;
          final actions = UpdateActions(showLater: true, alignEnd: side);
          if (side) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBadge(icon: Icons.system_update_alt_rounded, size: 44),
                SizedBox(width: look.cardPadding * 0.75),
                Expanded(flex: 3, child: text),
                SizedBox(width: look.cardPadding),
                Flexible(flex: 2, child: actions),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(icon: Icons.system_update_alt_rounded, size: wide ? 44 : 38),
                  SizedBox(width: wide ? look.cardPadding * 0.75 : AppSpacing.m),
                  Expanded(child: text),
                ],
              ),
              const SizedBox(height: AppSpacing.m),
              Padding(
                // Auf breiten Bildschirmen bündig mit dem Text.
                padding: EdgeInsets.only(left: wide ? 44 + look.cardPadding * 0.75 : 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: actions),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// „0.10.0 · Build 123“ (ohne Build-Nummer nur die Version).
String updateBuildText(BuildContext context, AppBuild b) =>
    b.isDevBuild ? b.version : context.l10n.updateBuildLabel(b.version, b.build);

/// Knöpfe und Fortschritt rund um den Download, auf der Startseite und in
/// den Optionen gleich: Herunterladen → Fortschritt → „Ordner öffnen“.
/// Auf iOS gibt es keinen Download, nur den Hinweis auf den Mac.
class UpdateActions extends ConsumerWidget {
  const UpdateActions({super.key, required this.showLater, this.alignEnd = false});

  /// „Später“ (Startseite) blendet den Hinweis bis zur nächsten Version aus.
  final bool showLater;
  final bool alignEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final s = ref.watch(updateControllerProvider);
    final ctrl = ref.read(updateControllerProvider.notifier);
    final host = ref.watch(updateHostProvider);
    final release = s.latest;
    if (release == null) return const SizedBox.shrink();
    final platform = host.platform;
    final cross = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = alignEnd ? TextAlign.end : TextAlign.start;

    Widget buttons(List<Widget> children) => Wrap(
          alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: children,
        );
    final later = showLater
        ? TextButton(key: const Key('update-later'), onPressed: ctrl.later, child: Text(l10n.updateLater))
        : null;

    if (host.isIos) {
      return Column(
        crossAxisAlignment: cross,
        children: [
          Text(l10n.updateIosHint, key: const Key('update-ios-hint'), style: theme.textTheme.bodySmall, textAlign: textAlign),
          const SizedBox(height: AppSpacing.s),
          buttons([
            OutlinedButton(onPressed: ctrl.openReleasePage, child: Text(l10n.updateReleasePage)),
            ?later,
          ]),
        ],
      );
    }

    // Android: Der Browser lädt die Datei, der Rest ist Handarbeit.
    if (platform == ReleasePlatform.android && release.assetFor(platform!) != null) {
      return _AndroidActions(showLater: showLater);
    }

    switch (s.downloadPhase) {
      case DownloadPhase.running:
        final pct = s.progress == null ? null : (s.progress! * 100).floor();
        return Column(
          key: const Key('update-progress'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              pct == null ? l10n.updateDownloadingUnknown : l10n.updateDownloading(pct),
              style: theme.textTheme.bodySmall,
              textAlign: textAlign,
            ),
            const SizedBox(height: AppSpacing.s),
            if (s.progress == null)
              const LinearProgressIndicator()
            else
              LookProgressBar(value: s.progress!),
          ],
        );
      case DownloadPhase.done:
        final file = s.file!;
        return Column(
          crossAxisAlignment: cross,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_rounded, size: 18, color: colors.success),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    l10n.updateDownloaded(p.basename(file.path)),
                    key: const Key('update-downloaded'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              platform == ReleasePlatform.macos ? l10n.updateInstallMacos : l10n.updateInstallWindows,
              style: theme.textTheme.bodySmall,
              textAlign: textAlign,
            ),
            const SizedBox(height: AppSpacing.s),
            buttons([
              FilledButton.icon(
                key: const Key('update-open-folder'),
                onPressed: ctrl.openDownloadFolder,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(l10n.updateOpenFolder),
              ),
              if (showLater) TextButton(onPressed: ctrl.later, child: Text(l10n.updateDone)),
            ]),
          ],
        );
      case DownloadPhase.failed:
        return Column(
          crossAxisAlignment: cross,
          children: [
            Text(
              l10n.updateDownloadFailed,
              key: const Key('update-download-failed'),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
              textAlign: textAlign,
            ),
            const SizedBox(height: AppSpacing.s),
            buttons([
              FilledButton(onPressed: ctrl.download, child: Text(l10n.updateRetry)),
              OutlinedButton(onPressed: ctrl.openReleasePage, child: Text(l10n.updateOpenInBrowser)),
            ]),
          ],
        );
      case DownloadPhase.idle:
        final canDownload = platform != null && release.assetFor(platform) != null;
        return buttons([
          FilledButton.icon(
            key: const Key('update-download'),
            onPressed: canDownload ? ctrl.download : ctrl.openReleasePage,
            icon: Icon(canDownload ? Icons.download_rounded : Icons.open_in_new_rounded),
            label: Text(canDownload ? l10n.updateDownload : l10n.updateOpenInBrowser),
          ),
          ?later,
        ]);
    }
  }
}

/// Android-Update in drei Schritten: Herunterladen, Datei öffnen, Installieren.
/// Die App installiert nichts selbst; sie öffnet nur den Download-Link.
/// Im Hinweis ([showLater]) steht nur eine Zeile, die Schritte erklärt ein
/// Blatt; in den Optionen stehen sie gleich da.
class _AndroidActions extends ConsumerWidget {
  const _AndroidActions({required this.showLater});
  final bool showLater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final ctrl = ref.read(updateControllerProvider.notifier);
    return Column(
      key: const Key('update-android-steps'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLater)
          Text(l10n.liteUpdateSummary, key: const Key('update-android-summary'), style: theme.textTheme.bodyMedium)
        else
          const _StepList(),
        const SizedBox(height: AppSpacing.m),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            FilledButton.icon(
              key: const Key('update-download'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
              onPressed: ctrl.download,
              icon: const Icon(Icons.download_rounded),
              label: Text(l10n.updateDownload),
            ),
            if (showLater) ...[
              OutlinedButton(
                key: const Key('update-android-howto'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
                onPressed: () => _showSteps(context, ctrl),
                child: Text(l10n.liteUpdateHowTo),
              ),
              TextButton(
                key: const Key('update-later'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 52)),
                onPressed: ctrl.later,
                child: Text(l10n.updateLater),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _showSteps(BuildContext context, UpdateController ctrl) {
    final l10n = context.l10n;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          key: const Key('update-android-sheet'),
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _StepList(),
              const SizedBox(height: AppSpacing.l),
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                    onPressed: () {
                      Navigator.pop(context);
                      ctrl.download();
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: Text(l10n.updateDownload),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 52)),
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.liteUpdateClose),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Die drei Schritte und der Hinweis auf die einmalige Erlaubnis.
class _StepList extends StatelessWidget {
  const _StepList();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final steps = [l10n.liteUpdateStep1, l10n.liteUpdateStep2, l10n.liteUpdateStep3];
    final base = theme.textTheme.bodyMedium;

    // „Herunterladen: Tippe …“: der Teil vor dem Doppelpunkt fett.
    Widget step(int number, String text) {
      final cut = text.indexOf(':');
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 22, child: Text('$number.', style: base?.copyWith(fontWeight: FontWeight.w700))),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: text.substring(0, cut + 1), style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: text.substring(cut + 1)),
                ]),
                style: base,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.liteUpdateSteps, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.s),
        for (final (i, text) in steps.indexed) step(i + 1, text),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.liteUpdateAllow,
          key: const Key('update-android-allow'),
          style: theme.textTheme.bodySmall?.copyWith(color: context.dartColors.textMuted),
        ),
      ],
    );
  }
}
