import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import 'autodarts_import_controller.dart';
import 'import_dialogs.dart';

/// Stellt die Frage „Welcher Spieler bist du?“, sobald der Empfänger ein
/// Match bekommt, bei dem DartLab den eigenen Spieler nicht erkennt. Eine
/// Frage je Match; wer „Später“ wählt, findet sie in den Optionen wieder
/// (Karte „Online-Matches“).
///
/// Unsichtbar und ohne Wirkung, solange nichts wartet (und in Lite, wo der
/// Empfänger nie läuft).
class ImportPromptHost extends ConsumerStatefulWidget {
  const ImportPromptHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ImportPromptHost> createState() => _ImportPromptHostState();
}

class _ImportPromptHostState extends ConsumerState<ImportPromptHost> {
  final Set<String> _asked = {};
  bool _open = false;

  Future<void> _ask(PendingImport pending) async {
    final context = ref.read(rootNavigatorKeyProvider).currentContext;
    if (context == null || _open) return;
    _open = true;
    try {
      final me = await showWhoAreYouDialog(context, pending.match);
      if (me != null) {
        await ref.read(autodartsImportControllerProvider.notifier).resolve(pending, me);
      }
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(autodartsImportControllerProvider.select((s) => s.pending), (_, pending) {
      for (final p in pending) {
        if (_asked.add(p.match.id)) {
          unawaited(_ask(p));
          break;
        }
      }
    });
    return widget.child;
  }
}
