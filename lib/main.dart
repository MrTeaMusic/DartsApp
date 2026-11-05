import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/fullscreen.dart';
import 'core/settings/app_settings.dart';
import 'core/settings/prefs_guard.dart';
import 'features/history/share/shared_match_opener.dart';

/// Startargumente (Desktop):
/// `--fullscreen` startet direkt im Vollbild, z. B. für einen Raspberry Pi
/// am Board, der DartLab beim Hochfahren als Kiosk öffnet. F11/Esc
/// funktionieren danach wie gewohnt.
/// Ein Pfad auf eine `.dartlab`-Datei öffnet das geteilte Match.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFullscreenSupport();
  // Einstellungsdatei vor dem ersten Lesen prüfen und sichern (Windows/Linux).
  await (await PrefsGuard.forPlatform())?.protect();
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // Doppelklick auf eine .dartlab-Datei (Windows/Linux): Pfad als Argument.
      launchFilesProvider.overrideWithValue(sharedMatchArgs(args)),
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DartLabApp(),
    ),
  );
  if (args.contains('--fullscreen')) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      container.read(fullscreenProvider.notifier).set(true);
    });
  }
}
