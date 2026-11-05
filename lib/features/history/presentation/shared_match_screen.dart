import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../share/shared_match_opener.dart';
import 'history_screen.dart';
import 'session_detail_screen.dart';

/// Ein geteiltes Match, geöffnet aus einer `.dartlab`-Datei: dieselbe
/// Ansicht wie im eigenen Verlauf, nur zum Ansehen. Ohne Navigationsleiste,
/// das Kreuz führt zurück.
class SharedMatchScreen extends ConsumerWidget {
  const SharedMatchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final match = ref.watch(openedSharedMatchProvider);
    void close() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.stats);
      }
    }

    return Scaffold(
      appBar: AppPageBar(
        maxWidth: kHistoryMaxWidth,
        leading: IconButton(
          key: const Key('shared-match-close'),
          tooltip: l10n.sharedMatchClose,
          onPressed: close,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(l10n.sharedMatchTitle),
      ),
      body: match == null
          ? Center(child: Text(l10n.sharedMatchNone, style: Theme.of(context).textTheme.bodyMedium))
          : SessionDetailBody(detail: match.toDetail(), shared: match),
    );
  }
}
