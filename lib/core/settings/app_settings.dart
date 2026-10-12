import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/dart_source/domain/coordinate_calibration.dart';
import '../../features/dart_source/domain/dart_event.dart';
import '../../features/sync/domain/sync_role.dart';
import '../../features/board/presentation/board_style.dart';
import '../design/dart_look.dart';

/// Einstellungen der App. Unveränderlich, Änderungen über [SettingsNotifier].
@immutable
class AppSettings {
  const AppSettings({
    this.look = DartLookId.tv,
    this.boardStyle = BoardStyle.tournament,
    this.themeMode = ThemeMode.system,
    this.sourceKind = DartSourceKind.simulator,
    this.autodartsHost = '127.0.0.1',
    this.autodartsPort = 3180,
    this.soundEnabled = false,
    this.hapticsEnabled = true,
    this.logRawToFile = false,
    this.coordCalibration = CoordinateCalibration.identity,
    this.syncRole = SyncRole.off,
    this.syncHost = '',
    this.syncPort = defaultSyncPort,
    this.syncKey = '',
  });

  /// Gewählter Look (Optionen → Darstellung).
  final DartLookId look;

  /// Optik der Dartscheibe (Optionen → Darstellung → Scheibe).
  final BoardStyle boardStyle;

  /// Helligkeit; gilt nur für Looks mit heller Variante (Clean).
  final ThemeMode themeMode;
  final DartSourceKind sourceKind;
  final String autodartsHost;
  final int autodartsPort;
  final bool soundEnabled;
  final bool hapticsEnabled;

  /// Rohe Autodarts-Nachrichten zusätzlich in eine Datei schreiben.
  final bool logRawToFile;

  /// Umrechnung der Autodarts-Koordinaten (Standard: keine).
  final CoordinateCalibration coordCalibration;

  /// Abgleich im Heimnetz: Rolle, Adresse des Hubs (nur Client), Port und
  /// Kopplungscode (beide Seiten gleich).
  final SyncRole syncRole;
  final String syncHost;
  final int syncPort;
  final String syncKey;

  AppSettings copyWith({
    DartLookId? look,
    BoardStyle? boardStyle,
    ThemeMode? themeMode,
    DartSourceKind? sourceKind,
    String? autodartsHost,
    int? autodartsPort,
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? logRawToFile,
    CoordinateCalibration? coordCalibration,
    SyncRole? syncRole,
    String? syncHost,
    int? syncPort,
    String? syncKey,
  }) =>
      AppSettings(
        look: look ?? this.look,
        boardStyle: boardStyle ?? this.boardStyle,
        themeMode: themeMode ?? this.themeMode,
        sourceKind: sourceKind ?? this.sourceKind,
        autodartsHost: autodartsHost ?? this.autodartsHost,
        autodartsPort: autodartsPort ?? this.autodartsPort,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        logRawToFile: logRawToFile ?? this.logRawToFile,
        coordCalibration: coordCalibration ?? this.coordCalibration,
        syncRole: syncRole ?? this.syncRole,
        syncHost: syncHost ?? this.syncHost,
        syncPort: syncPort ?? this.syncPort,
        syncKey: syncKey ?? this.syncKey,
      );

  static const _kLook = 'settings.look';
  static const _kBoardStyle = 'settings.boardStyle';
  static const _kTheme = 'settings.themeMode';
  static const _kSource = 'settings.sourceKind';
  static const _kHost = 'settings.autodartsHost';
  static const _kPort = 'settings.autodartsPort';
  static const _kSound = 'settings.sound';
  static const _kHaptics = 'settings.haptics';
  static const _kLogFile = 'settings.logRawToFile';
  static const _kCalibration = 'settings.coordCalibration';
  static const _kSyncRole = 'sync.role';
  static const _kSyncHost = 'sync.host';
  static const _kSyncPort = 'sync.port';
  static const _kSyncKey = 'sync.key';

  static AppSettings load(SharedPreferences prefs) {
    const d = AppSettings();
    T byName<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    return AppSettings(
      look: DartLookId.byName(prefs.getString(_kLook)),
      boardStyle: BoardStyle.byName(prefs.getString(_kBoardStyle)),
      themeMode: byName(ThemeMode.values, prefs.getString(_kTheme), d.themeMode),
      sourceKind: byName(DartSourceKind.values, prefs.getString(_kSource), d.sourceKind),
      autodartsHost: prefs.getString(_kHost) ?? d.autodartsHost,
      autodartsPort: prefs.getInt(_kPort) ?? d.autodartsPort,
      soundEnabled: prefs.getBool(_kSound) ?? d.soundEnabled,
      hapticsEnabled: prefs.getBool(_kHaptics) ?? d.hapticsEnabled,
      logRawToFile: prefs.getBool(_kLogFile) ?? d.logRawToFile,
      coordCalibration: CoordinateCalibration.decode(prefs.getString(_kCalibration)),
      syncRole: byName(SyncRole.values, prefs.getString(_kSyncRole), d.syncRole),
      syncHost: prefs.getString(_kSyncHost) ?? d.syncHost,
      syncPort: prefs.getInt(_kSyncPort) ?? d.syncPort,
      syncKey: prefs.getString(_kSyncKey) ?? d.syncKey,
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString(_kLook, look.name);
    await prefs.setString(_kBoardStyle, boardStyle.name);
    await prefs.setString(_kTheme, themeMode.name);
    await prefs.setString(_kSource, sourceKind.name);
    await prefs.setString(_kHost, autodartsHost);
    await prefs.setInt(_kPort, autodartsPort);
    await prefs.setBool(_kSound, soundEnabled);
    await prefs.setBool(_kHaptics, hapticsEnabled);
    await prefs.setBool(_kLogFile, logRawToFile);
    await prefs.setString(_kCalibration, coordCalibration.encode());
    await prefs.setString(_kSyncRole, syncRole.name);
    await prefs.setString(_kSyncHost, syncHost);
    await prefs.setInt(_kSyncPort, syncPort);
    await prefs.setString(_kSyncKey, syncKey);
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
