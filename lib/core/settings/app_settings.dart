import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/dart_source/domain/dart_event.dart';

/// Einstellungen der App. Unveränderlich, Änderungen über [SettingsNotifier].
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.sourceKind = DartSourceKind.simulator,
    this.autodartsHost = '127.0.0.1',
    this.autodartsPort = 3180,
    this.soundEnabled = false,
    this.hapticsEnabled = true,
    this.logRawToFile = false,
  });

  final ThemeMode themeMode;
  final DartSourceKind sourceKind;
  final String autodartsHost;
  final int autodartsPort;
  final bool soundEnabled;
  final bool hapticsEnabled;

  /// Rohe Autodarts-Nachrichten zusätzlich in eine Datei schreiben.
  final bool logRawToFile;

  AppSettings copyWith({
    ThemeMode? themeMode,
    DartSourceKind? sourceKind,
    String? autodartsHost,
    int? autodartsPort,
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? logRawToFile,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        sourceKind: sourceKind ?? this.sourceKind,
        autodartsHost: autodartsHost ?? this.autodartsHost,
        autodartsPort: autodartsPort ?? this.autodartsPort,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        logRawToFile: logRawToFile ?? this.logRawToFile,
      );

  static const _kTheme = 'settings.themeMode';
  static const _kSource = 'settings.sourceKind';
  static const _kHost = 'settings.autodartsHost';
  static const _kPort = 'settings.autodartsPort';
  static const _kSound = 'settings.sound';
  static const _kHaptics = 'settings.haptics';
  static const _kLogFile = 'settings.logRawToFile';

  static AppSettings load(SharedPreferences prefs) {
    const d = AppSettings();
    T byName<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    return AppSettings(
      themeMode: byName(ThemeMode.values, prefs.getString(_kTheme), d.themeMode),
      sourceKind: byName(DartSourceKind.values, prefs.getString(_kSource), d.sourceKind),
      autodartsHost: prefs.getString(_kHost) ?? d.autodartsHost,
      autodartsPort: prefs.getInt(_kPort) ?? d.autodartsPort,
      soundEnabled: prefs.getBool(_kSound) ?? d.soundEnabled,
      hapticsEnabled: prefs.getBool(_kHaptics) ?? d.hapticsEnabled,
      logRawToFile: prefs.getBool(_kLogFile) ?? d.logRawToFile,
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString(_kTheme, themeMode.name);
    await prefs.setString(_kSource, sourceKind.name);
    await prefs.setString(_kHost, autodartsHost);
    await prefs.setInt(_kPort, autodartsPort);
    await prefs.setBool(_kSound, soundEnabled);
    await prefs.setBool(_kHaptics, hapticsEnabled);
    await prefs.setBool(_kLogFile, logRawToFile);
  }
}

/// Wird in `main()` mit der geladenen Instanz überschrieben.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider muss überschrieben werden'),
);

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.load(ref.watch(sharedPreferencesProvider));

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await state.save(ref.read(sharedPreferencesProvider));
  }
}
