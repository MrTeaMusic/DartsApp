import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/settings/app_settings.dart';
import '../domain/cpu_players.dart';
import '../domain/match_session.dart';
import '../domain/tournament.dart';

/// Ein unterbrochenes Match zum Fortsetzen.
class SavedMatch {
  const SavedMatch({required this.setup, required this.inputs, this.sessionIds = const {}});

  final MatchSetup setup;
  final List<MatchInput> inputs;

  /// Datenbank-Sessions der Menschen (Spielerindex → Session-ID).
  final Map<int, int> sessionIds;

  Map<String, Object?> toJson() => {
    'setup': setup.toJson(),
    'inputs': [for (final i in inputs) MatchSession.inputToJson(i)],
    'sessions': {for (final e in sessionIds.entries) '${e.key}': e.value},
  };

  static SavedMatch? fromJson(Object? json) {
    if (json is! Map) return null;
    final setup = MatchSetup.fromJson(json['setup']);
    if (setup.players.length < 2) return null;
    final inputs = <MatchInput>[
      for (final i in (json['inputs'] is List ? json['inputs'] as List : const [])) ?MatchSession.inputFromJson(i),
    ];
    final sessions = json['sessions'];
    return SavedMatch(
      setup: setup,
      inputs: inputs,
      sessionIds: {
        if (sessions is Map)
          for (final e in sessions.entries)
            if (int.tryParse('${e.key}') != null && e.value is num) int.parse('${e.key}'): (e.value as num).toInt(),
      },
    );
  }
}

/// Speichert Matches, Turniere und die CPU-Spielerliste lokal in den
/// Einstellungen des Geräts (kein Abgleich).
class MatchStore {
  MatchStore(this.prefs);
  final SharedPreferences prefs;

  static const String cpuKey = 'matches.cpuPlayers';
  static const String tournamentKey = 'matches.tournament';
  static const String currentKey = 'matches.current';
  static const String setupKey = 'matches.lastSetup';

  Object? _read(String key) {
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  /// Eigene Liste oder die Standardliste.
  List<CpuPlayer> cpuPlayers() {
    final v = _read(cpuKey);
    if (v is! List) return defaultCpuPlayers;
    return [for (final e in v) ?CpuPlayer.fromJson(e)];
  }

  Future<void> saveCpuPlayers(List<CpuPlayer> players) =>
      prefs.setString(cpuKey, jsonEncode([for (final p in players) p.toJson()]));

  Future<void> resetCpuPlayers() => prefs.remove(cpuKey);

  Tournament? tournament() => Tournament.fromJson(_read(tournamentKey));

  Future<void> saveTournament(Tournament? t) =>
      t == null ? prefs.remove(tournamentKey) : prefs.setString(tournamentKey, jsonEncode(t.toJson()));

  SavedMatch? currentMatch() => SavedMatch.fromJson(_read(currentKey));

  Future<void> saveCurrentMatch(SavedMatch? m) =>
      m == null ? prefs.remove(currentKey) : prefs.setString(currentKey, jsonEncode(m.toJson()));

  /// Zuletzt gewählte Einstellungen des Gegner-Modus.
  Map<String, Object?> lastSetup() {
    final v = _read(setupKey);
    return v is Map<String, Object?> ? v : const {};
  }

  Future<void> saveLastSetup(Map<String, Object?> json) => prefs.setString(setupKey, jsonEncode(json));

  /// Zuletzt gewählte Turnier-Einstellungen (Schwierigkeit, Format).
  Map<String, Object?> lastTournamentSetup() {
    final v = _read(tournamentSetupKey);
    return v is Map<String, Object?> ? v : const {};
  }

  Future<void> saveLastTournamentSetup(Map<String, Object?> json) =>
      prefs.setString(tournamentSetupKey, jsonEncode(json));

  static const String tournamentSetupKey = 'matches.lastTournamentSetup';
}

final matchStoreProvider = Provider<MatchStore>((ref) => MatchStore(ref.watch(sharedPreferencesProvider)));
