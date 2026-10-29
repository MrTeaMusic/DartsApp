import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/lite.dart';
import '../domain/board_control.dart';
import '../domain/dart_event.dart';
import 'dart_source_providers.dart';

/// Die Quelle als [BoardControl], aber nur, wenn es eine lokale
/// Autodarts-Quelle ist und die App nicht als Lite läuft. Simulator, manuelle
/// Eingabe und fremde Quellen bekommen weder Board-Hilfe noch Rahmen.
final boardControlProvider = Provider<BoardControl?>((ref) {
  if (ref.watch(liteProvider)) return null;
  final source = ref.watch(dartSourceProvider);
  if (source.kind != DartSourceKind.autodartsLocal) return null;
  return source is BoardControl ? source as BoardControl : null;
});

/// Läuft die Erkennung am Board? Null, solange unbekannt.
final boardRunningProvider = StreamProvider<bool?>((ref) async* {
  final control = ref.watch(boardControlProvider);
  if (control == null) {
    yield null;
    return;
  }
  yield control.boardRunning;
  yield* control.boardRunningChanges;
});

/// Wie [boardControlProvider], aber nur mit Verbindung zum Board Manager.
/// Ohne Verbindung käme kein Befehl an; dort hilft nur das Wiederverbinden.
final boardHelpProvider = Provider<BoardControl?>((ref) {
  final control = ref.watch(boardControlProvider);
  if (control == null) return null;
  final source = ref.watch(dartSourceProvider);
  final status = ref.watch(sourceStatusProvider).value ?? source.status;
  return status.isLive ? control : null;
});

extension BoardActionText on BoardAction {
  String label(AppLocalizations l10n) => switch (this) {
        BoardAction.recalibrate => l10n.boardHelpRecalibrate,
        BoardAction.stop => l10n.boardHelpStop,
        BoardAction.start => l10n.boardHelpStart,
        BoardAction.refresh => l10n.boardHelpRefresh,
      };

  String hint(AppLocalizations l10n) => switch (this) {
        BoardAction.recalibrate => l10n.boardHelpRecalibrateHint,
        BoardAction.stop => l10n.boardHelpStopHint,
        BoardAction.start => l10n.boardHelpStartHint,
        BoardAction.refresh => l10n.boardHelpRefreshHint,
      };

  String question(AppLocalizations l10n) => switch (this) {
        BoardAction.recalibrate => l10n.boardHelpAskRecalibrate,
        BoardAction.stop => l10n.boardHelpAskStop,
        BoardAction.start => l10n.boardHelpAskStart,
        BoardAction.refresh => l10n.boardHelpAskRefresh,
      };

  IconData get icon => switch (this) {
        BoardAction.recalibrate => Icons.center_focus_strong_outlined,
        BoardAction.stop => Icons.stop_circle_outlined,
        BoardAction.start => Icons.play_circle_outline_rounded,
        BoardAction.refresh => Icons.refresh_rounded,
      };
}

/// Ergebnis-Hinweis: der HTTP-Status des Boards bzw. der Fehlertext, sonst nichts
/// (keine Antwortdaten). „Angenommen“ heißt nicht „hat gewirkt“.
String boardHelpResultText(AppLocalizations l10n, BoardAction action, BoardCommandResult r) {
  final name = action.label(l10n);
  if (r.blocked) return l10n.boardHelpResultBlocked(name);
  final status = r.statusCode;
  if (status == null) return l10n.boardHelpResultError(name, r.error ?? '?');
  if (r.fellBackFrom != null) {
    final first = r.fallbackStatusCode ?? 0;
    return r.ok
        ? l10n.boardHelpResultFallback(name, first, status)
        : l10n.boardHelpResultFallbackRejected(name, first, status);
  }
  return r.ok ? l10n.boardHelpResultOk(name, status) : l10n.boardHelpResultRejected(name, status);
}

/// Knopf „Board-Hilfe“ für die Kopfzeilen. Erscheint nur bei einer
/// verbundenen lokalen Autodarts-Quelle (siehe [boardHelpProvider]).
class BoardHelpButton extends ConsumerWidget {
  const BoardHelpButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final control = ref.watch(boardHelpProvider);
    if (control == null) return const SizedBox.shrink();
    return IconButton(
      key: const Key('board-help'),
      tooltip: context.l10n.boardHelpTooltip,
      icon: const Icon(Icons.build_circle_outlined),
      // Schmal, damit der Titel der Kopfzeile auf dem Telefon Platz behält.
      visualDensity: VisualDensity.compact,
      onPressed: () => showBoardHelp(context, control),
    );
  }
}

/// Öffnet das Menü; nach der Wahl fragt ein Dialog nach, dann geht der Befehl
/// raus und ein Hinweis zeigt, was das Board geantwortet hat.
Future<void> showBoardHelp(BuildContext context, BoardControl control) async {
  final action = await showModalBottomSheet<BoardAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => BoardHelpSheet(control: control),
  );
  if (action == null || !context.mounted) return;
  await _confirmAndRun(context, control, action);
}

Future<void> _confirmAndRun(BuildContext context, BoardControl control, BoardAction action) async {
  final l10n = context.l10n;
  final theme = Theme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('board-help-confirm'),
      title: Text(action.label(l10n)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(action.question(l10n)),
            if (control.listenOnly) ...[
              const SizedBox(height: AppSpacing.m),
              Text(
                l10n.boardHelpLiveWarning,
                key: const Key('board-help-live-warning'),
                style: theme.textTheme.bodyMedium?.copyWith(color: context.dartColors.warning),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('board-help-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.boardHelpCancel),
        ),
        FilledButton(
          key: const Key('board-help-send'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.boardHelpSend),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      key: const Key('board-help-sending'),
      duration: const Duration(seconds: 30),
      content: Text(l10n.boardHelpSending(action.label(l10n))),
    ));
  // Der Knopfdruck ist die ausdrückliche Absicht des Nutzers: nur er darf die
  // Sperre „nur mithören“ umgehen.
  final result = await control.run(action, userInitiated: true);
  final good = result.ok;
  final colors = context.mounted ? context.dartColors : null;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      showCloseIcon: true,
      content: Row(
        children: [
          Icon(
            good ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            color: good ? colors?.success : colors?.danger,
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text(
              // l10n bleibt gültig, auch wenn der Knopf inzwischen weg ist.
              boardHelpResultText(l10n, action, result),
              key: const Key('board-help-result'),
            ),
          ),
        ],
      ),
    ));
}

/// Das Blatt mit den Aktionen.
class BoardHelpSheet extends StatelessWidget {
  const BoardHelpSheet({super.key, required this.control});
  final BoardControl control;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final actions = [
      BoardAction.recalibrate,
      control.boardRunning == false ? BoardAction.start : BoardAction.stop,
      BoardAction.refresh,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('board-help-sheet'),
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.boardHelpTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.boardHelpIntro(control.boardAddress), style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.s),
            for (final a in actions)
              ListTile(
                key: Key('board-help-${a.name}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(a.icon),
                title: Text(a.label(l10n)),
                subtitle: Text(a.hint(l10n)),
                onTap: () => Navigator.pop(context, a),
              ),
            const SizedBox(height: AppSpacing.s),
            Text(
              l10n.boardHelpUnverified,
              key: const Key('board-help-unverified'),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.warning),
            ),
          ],
        ),
      ),
    );
  }
}
