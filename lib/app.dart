import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design/app_theme.dart';
import 'core/design/arena/arena_background.dart';
import 'core/design/dart_look.dart';
import 'core/feedback.dart';
import 'core/fullscreen.dart';
import 'core/l10n.dart';
import 'core/lite.dart';
import 'core/router/app_router.dart';
import 'core/settings/app_settings.dart';
import 'features/autodarts_import/presentation/autodarts_import_controller.dart';
import 'features/autodarts_import/presentation/import_prompt_host.dart';
import 'features/board/presentation/live_visit_controller.dart';
import 'features/caller/presentation/training_game_caller.dart';
import 'features/challenges/presentation/challenge_run_controller.dart';
import 'features/matches/presentation/match_caller.dart';
import 'features/dart_source/presentation/dart_source_providers.dart';
import 'features/live_remote/presentation/live_push_controller.dart';
import 'features/progress/presentation/celebrations.dart';
import 'features/progress/presentation/progress_providers.dart';
import 'features/sync/presentation/sync_controller.dart';
import 'features/update/presentation/update_controller.dart';

class DartLabApp extends ConsumerWidget {
  const DartLabApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(settingsProvider.select((s) => s.look));
    // TV, Lab und Arena sind immer dunkel; nur Clean folgt der Helligkeit.
    final themeMode = look.supportsLight ? ref.watch(settingsProvider.select((s) => s.themeMode)) : ThemeMode.dark;
    final router = ref.watch(routerProvider);
    // Dauerhaft aktiv halten, damit nichts verloren geht, solange der
    // jeweilige Bildschirm nicht offen ist.
    ref
      ..watch(syncControllerProvider.select((_) => null))
      // Sucht beim Start nach Updates (höchstens einmal am Tag).
      ..watch(updateControllerProvider.select((_) => null));
    // Lite zeigt nur Daten an: kein Spiel, keine Ansagen, keine Erfolge.
    final lite = ref.watch(liteProvider);
    if (!lite) {
      ref
        ..watch(dartFeedbackProvider)
        ..watch(trainingGameCallerProvider)
        ..watch(matchCallerProvider)
        ..watch(liveVisitProvider.select((_) => null))
        ..watch(rawLogProvider.select((_) => null))
        ..watch(achievementRecorderProvider.select((_) => null))
        ..watch(celebrationsProvider.select((_) => null))
        ..watch(challengeRunProvider.select((_) => null))
        // Zeigt das laufende Spiel live im Internet, wenn Ben es eingeschaltet hat
        // (sonst tut dieser Provider nichts).
        ..watch(livePushControllerProvider.select((_) => null))
        // Lokaler Empfänger für das Browser-Skript (Online-Matches); startet
        // nur auf dem Desktop und nur, wenn er in den Optionen an ist.
        ..watch(autodartsImportControllerProvider.select((_) => null));
    }

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(look, Brightness.light),
      darkTheme: AppTheme.build(look, Brightness.dark),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        final app = _FullscreenShortcuts(child: child ?? const SizedBox());
        final prompted = lite ? app : ImportPromptHost(child: app);
        // Arena: Marineblau mit den Dreiecken hinter allen Seiten (die
        // Scaffolds sind in diesem Look durchsichtig).
        return look == DartLookId.arena ? ArenaBackground(strip: 8, child: prompted) : prompted;
      },
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

/// F11 schaltet das Vollbild um, Esc beendet es.
class _FullscreenShortcuts extends ConsumerWidget {
  const _FullscreenShortcuts({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fullscreen = ref.watch(fullscreenProvider);
    final notifier = ref.read(fullscreenProvider.notifier);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): notifier.toggle,
        if (fullscreen) const SingleActivator(LogicalKeyboardKey.escape): () => notifier.set(false),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
