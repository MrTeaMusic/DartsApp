import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design/app_theme.dart';
import 'core/feedback.dart';
import 'core/l10n.dart';
import 'core/router/app_router.dart';
import 'core/settings/app_settings.dart';
import 'features/board/presentation/live_visit_controller.dart';
import 'features/dart_source/presentation/dart_source_providers.dart';
import 'features/sync/presentation/sync_controller.dart';

class DartLabApp extends ConsumerWidget {
  const DartLabApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final router = ref.watch(routerProvider);
    // Dauerhaft aktiv halten, damit nichts verloren geht, solange der
    // jeweilige Bildschirm nicht offen ist.
    ref
      ..watch(dartFeedbackProvider)
      ..watch(liveVisitProvider.select((_) => null))
      ..watch(rawLogProvider.select((_) => null))
      ..watch(syncControllerProvider.select((_) => null));

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
