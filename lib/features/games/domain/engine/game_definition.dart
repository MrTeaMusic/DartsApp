import 'training_game.dart';

/// Eine einstellbare Option eines Spiels. Die Einstellungs-Oberfläche wird
/// daraus automatisch gebaut, neue Spiele brauchen keinen UI-Code dafür.
sealed class ConfigOption {
  const ConfigOption(this.key);

  /// Schlüssel in der JSON-Config, zugleich Übersetzungsschlüssel.
  final String key;
}

class IntOption extends ConfigOption {
  const IntOption(super.key, {required this.min, required this.max, this.step = 1});
  final int min;
  final int max;
  final int step;
}

class BoolOption extends ConfigOption {
  const BoolOption(super.key);
}

/// Auswahl aus festen Werten (gespeichert als String).
class ChoiceOption extends ConfigOption {
  const ChoiceOption(super.key, this.values);
  final List<String> values;
}

/// Liste ganzer Zahlen zur Auswahl, z. B. Zielscore 100/140/180.
class IntChoiceOption extends ConfigOption {
  const IntChoiceOption(super.key, this.values);
  final List<int> values;
}

/// Beschreibt ein Spiel: Kennung, Optionen, Standard-Config und wie es
/// erzeugt wird. Neue Spiele = neue [TrainingGame]-Klasse + eine Definition
/// im Katalog.
class GameDefinition {
  const GameDefinition({
    required this.id,
    required this.defaults,
    required this.options,
    required this.create,
    this.normalize,
  });

  /// Stabile Kennung, wird in der Datenbank gespeichert.
  final String id;

  /// Standardwerte der Config.
  final Map<String, Object?> defaults;
  final List<ConfigOption> options;

  /// Erzeugt das Spiel aus Config und Zufallsstartwert.
  final TrainingGame Function(Map<String, Object?> config, int seed) create;

  /// Optional: Config bereinigen (z. B. min ≤ max).
  final Map<String, Object?> Function(Map<String, Object?> config)? normalize;

  /// Config mit Standardwerten auffüllen und bereinigen.
  Map<String, Object?> resolve(Map<String, Object?> config) {
    final merged = {...defaults, ...config};
    return normalize?.call(merged) ?? merged;
  }

  TrainingGame start(Map<String, Object?> config, int seed) => create(resolve(config), seed);
}

/// Lesehilfen für Config-Maps.
extension ConfigRead on Map<String, Object?> {
  int intOf(String key, int fallback) => switch (this[key]) {
        final int v => v,
        final num v => v.round(),
        final String v => int.tryParse(v) ?? fallback,
        _ => fallback,
      };

  bool boolOf(String key, bool fallback) => switch (this[key]) {
        final bool v => v,
        _ => fallback,
      };

  String stringOf(String key, String fallback) => switch (this[key]) {
        final String v => v,
        _ => fallback,
      };

  List<int> intListOf(String key) => switch (this[key]) {
        final List<Object?> v => [for (final e in v) if (e is num) e.toInt()],
        _ => const [],
      };
}
