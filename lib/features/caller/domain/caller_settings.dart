import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'caller_phrases.dart';

/// Einstellungen des Callers. Eigene Schlüssel (`caller.*`), damit sie
/// unabhängig von den übrigen App-Einstellungen bleiben.
@immutable
class CallerSettings {
  const CallerSettings({
    this.enabled = true,
    this.language = CallerLanguage.english,
    this.volume = 1.0,
    this.rate = normalRate,
    this.announceScores = true,
    this.announceRemaining = true,
    this.announceCheckout = true,
    this.announceGameOn = true,
    this.useSoundPack = true,
  });

  /// Sprechtempo der Plattform: 0,5 ist auf allen Zielplattformen normal.
  static const double normalRate = 0.5;
  static const double minRate = 0.35;
  static const double maxRate = 0.65;

  /// An/aus. Der Stumm-Knopf in der Spielansicht schaltet genau diesen Wert.
  final bool enabled;
  final CallerLanguage language;

  /// Lautstärke 0–1.
  final double volume;

  /// Sprechtempo [minRate]–[maxRate].
  final double rate;

  /// Punkte jeder Aufnahme, „No score“ und „Bust“.
  final bool announceScores;

  /// Rest auf einem Finish („You require 32“).
  final bool announceRemaining;

  /// „Game shot“ beim Checkout.
  final bool announceCheckout;

  /// „Game on“ zu Spielbeginn.
  final bool announceGameOn;

  /// Eigene Sounddateien abspielen, sofern welche importiert sind
  /// (siehe `CallerSoundPack`). Fehlende Ansagen spricht die Stimme.
  final bool useSoundPack;

  CallerSettings copyWith({
    bool? enabled,
    CallerLanguage? language,
    double? volume,
    double? rate,
    bool? announceScores,
    bool? announceRemaining,
    bool? announceCheckout,
    bool? announceGameOn,
    bool? useSoundPack,
  }) =>
      CallerSettings(
        enabled: enabled ?? this.enabled,
        language: language ?? this.language,
        volume: volume ?? this.volume,
        rate: rate ?? this.rate,
        announceScores: announceScores ?? this.announceScores,
        announceRemaining: announceRemaining ?? this.announceRemaining,
        announceCheckout: announceCheckout ?? this.announceCheckout,
        announceGameOn: announceGameOn ?? this.announceGameOn,
        useSoundPack: useSoundPack ?? this.useSoundPack,
      );

  static const _kEnabled = 'caller.enabled';
  static const _kLanguage = 'caller.language';
  static const _kVolume = 'caller.volume';
  static const _kRate = 'caller.rate';
  static const _kScores = 'caller.scores';
  static const _kRemaining = 'caller.remaining';
  static const _kCheckout = 'caller.checkout';
  static const _kGameOn = 'caller.gameOn';
  static const _kSoundPack = 'caller.soundPack';

  static CallerSettings load(SharedPreferences prefs) {
    const d = CallerSettings();
    final language = prefs.getString(_kLanguage);
    return CallerSettings(
      enabled: prefs.getBool(_kEnabled) ?? d.enabled,
      language: CallerLanguage.values.where((l) => l.name == language).firstOrNull ?? d.language,
      volume: (prefs.getDouble(_kVolume) ?? d.volume).clamp(0.0, 1.0),
      rate: (prefs.getDouble(_kRate) ?? d.rate).clamp(minRate, maxRate),
      announceScores: prefs.getBool(_kScores) ?? d.announceScores,
      announceRemaining: prefs.getBool(_kRemaining) ?? d.announceRemaining,
      announceCheckout: prefs.getBool(_kCheckout) ?? d.announceCheckout,
      announceGameOn: prefs.getBool(_kGameOn) ?? d.announceGameOn,
      useSoundPack: prefs.getBool(_kSoundPack) ?? d.useSoundPack,
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setBool(_kEnabled, enabled);
    await prefs.setString(_kLanguage, language.name);
    await prefs.setDouble(_kVolume, volume);
    await prefs.setDouble(_kRate, rate);
    await prefs.setBool(_kScores, announceScores);
    await prefs.setBool(_kRemaining, announceRemaining);
    await prefs.setBool(_kCheckout, announceCheckout);
    await prefs.setBool(_kGameOn, announceGameOn);
    await prefs.setBool(_kSoundPack, useSoundPack);
  }
}
