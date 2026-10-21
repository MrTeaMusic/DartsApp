/// Wie ruhig der Bot wirft (Optionen → Darstellung → Bot-Tempo). Die Zeiten
/// in Millisekunden: Pause vor dem ersten Dart der Aufnahme, zwischen den
/// Darts und wie lange die Darts nach der Aufnahme stehen bleiben.
enum BotPace {
  /// Die ursprünglichen, flotten Zeiten.
  quick(1200, 850, 1600),

  /// Standard: der Bot lässt dem Menschen Zeit zum Werfen.
  relaxed(2400, 1700, 2800),

  /// Noch ruhiger: das 1,6-fache von [relaxed].
  veryRelaxed(3840, 2720, 4480);

  const BotPace(this.firstDartMs, this.betweenDartsMs, this.takeoutMs);

  final int firstDartMs;
  final int betweenDartsMs;
  final int takeoutMs;

  static const defaultPace = BotPace.relaxed;

  static BotPace byName(String? name) => values.where((v) => v.name == name).firstOrNull ?? defaultPace;
}
