import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/dart_source/domain/coordinate_calibration.dart';
import '../../features/dart_source/domain/dart_event.dart';
import '../../features/sync/domain/sync_role.dart';
import '../../features/board/presentation/board_style.dart';
import '../../features/progress/domain/daily_goal.dart';
import '../design/dart_look.dart';

/// Aufbau der X01-Spielansichten (Match und Solo).
enum PlayView {
  /// Drei Spalten mit großen Spielertafeln und Wurftabelle (Arena).
  arena,

  /// Die Ansicht des gewählten Looks (TV, Clean, Lab).
  look;

  static PlayView byName(String? name) => values.where((v) => v.name == name).firstOrNull ?? arena;
}

/// Einstellungen der App. Unveränderlich, Änderungen über [SettingsNotifier].
@immutable
class AppSettings {
  const AppSettings({
    this.look = DartLookId.tv,
    this.boardStyle = BoardStyle.tournament,
    this.doubleZoom = true,
    this.tempoHint = true,
    this.playView = PlayView.arena,
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
    this.dailyGoalUnit = DailyGoalUnit.darts,
    this.dailyGoalAmount = 200,
    this.autodartsLiveAutoStart = false,
  });

  /// Gewählter Look (Optionen → Darstellung).
  final DartLookId look;

  /// Zeigt X01 die Arena-Spielansicht? Bei „Arena“ als Look immer, sonst nach
  /// der Wahl der Spielansicht.
  bool get arenaPlay => playView == PlayView.arena || look == DartLookId.arena;

  /// Optik der Dartscheibe (Optionen → Darstellung → Scheibe).
  final BoardStyle boardStyle;

  /// Vergrößerter Ausschnitt des Doppels, wenn eins geworfen werden muss.
  final bool doubleZoom;

  /// Leises Wurftempo (Sekunden der Aufnahme) in den Spielansichten. Die
  /// Statistik „Tempo“ gibt es immer.
  final bool tempoHint;

  /// Aufbau der X01-Spielansichten (Optionen → Darstellung).
  final PlayView playView;

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

  /// Tagesziel (Startseite, Optionen → Tagesziel): Einheit und Menge.
  final DailyGoalUnit dailyGoalUnit;
  final int dailyGoalAmount;

  /// Beim Start von DartLab direkt Autodarts Live öffnen (nur mit Quelle
  /// Autodarts).
  final bool autodartsLiveAutoStart;

  DailyGoal get dailyGoal => DailyGoal(dailyGoalUnit, dailyGoalUnit.clamp(dailyGoalAmount));

  AppSettings copyWith({
    DartLookId? look,
    BoardStyle? boardStyle,
    bool? doubleZoom,
    bool? tempoHint,
    PlayView? playView,
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
    DailyGoalUnit? dailyGoalUnit,
    int? dailyGoalAmount,
    bool? autodartsLiveAutoStart,
  }) =>
      AppSettings(
        look: look ?? this.look,
        boardStyle: boardStyle ?? this.boardStyle,
        doubleZoom: doubleZoom ?? this.doubleZoom,
        tempoHint: tempoHint ?? this.tempoHint,
        playView: playView ?? this.playView,
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
        dailyGoalUnit: dailyGoalUnit ?? this.dailyGoalUnit,
        dailyGoalAmount: dailyGoalAmount ?? this.dailyGoalAmount,
        autodartsLiveAutoStart: autodartsLiveAutoStart ?? this.autodartsLiveAutoStart,
      );

  static const _kLook = 'settings.look';
  static const _kBoardStyle = 'settings.boardStyle';
  static const _kDoubleZoom = 'settings.doubleZoom';
  static const _kTempoHint = 'settings.tempoHint';
  static const _kPlayView = 'settings.playView';
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
  static const _kGoalUnit = 'goals.dailyUnit';
  static const _kGoalAmount = 'goals.dailyAmount';
  static const _kLiveAutoStart = 'settings.autodartsLiveAutoStart';

  static AppSettings load(SharedPreferences prefs) {
    const d = AppSettings();
    T byName<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    return AppSettings(
      look: DartLookId.byName(prefs.getString(_kLook)),
      boardStyle: BoardStyle.byName(prefs.getString(_kBoardStyle)),
      doubleZoom: prefs.getBool(_kDoubleZoom) ?? d.doubleZoom,
      tempoHint: prefs.getBool(_kTempoHint) ?? d.tempoHint,
      playView: PlayView.byName(prefs.getString(_kPlayView)),
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
      dailyGoalUnit: DailyGoalUnit.byName(prefs.getString(_kGoalUnit)),
      dailyGoalAmount: prefs.getInt(_kGoalAmount) ?? d.dailyGoalAmount,
      autodartsLiveAutoStart: prefs.getBool(_kLiveAutoStart) ?? d.autodartsLiveAutoStart,
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString(_kLook, look.name);
    await prefs.setString(_kBoardStyle, boardStyle.name);
    await prefs.setBool(_kDoubleZoom, doubleZoom);
    await prefs.setBool(_kTempoHint, tempoHint);
    await prefs.setString(_kPlayView, playView.name);
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
    await prefs.setString(_kGoalUnit, dailyGoalUnit.name);
    await prefs.setInt(_kGoalAmount, dailyGoalAmount);
    await prefs.setBool(_kLiveAutoStart, autodartsLiveAutoStart);
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
