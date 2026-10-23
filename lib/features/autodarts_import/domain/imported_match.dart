import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';

/// Warum ein Import nicht möglich ist. Die Art entscheidet, ob der Empfänger
/// „ignored“ (kein X01, fremde Variante) oder einen Fehler meldet.
enum ImportProblem {
  /// Kein JSON-Objekt oder erwartete Felder fehlen („Format unbekannt“).
  format,

  /// Gültiges Match, aber nicht X01.
  notX01,

  /// Nicht genau zwei Spieler.
  players,

  /// Keine Darts im Match.
  empty,
}

/// Klarer Fehlertext statt Absturz. [message] ist für die Oberfläche gedacht
/// (deutsch).
class AutodartsImportException implements Exception {
  const AutodartsImportException(this.problem, this.message);

  final ImportProblem problem;
  final String message;

  @override
  String toString() => message;
}

/// Ein Dart des importierten Matches.
class ImportedDart {
  const ImportedDart(this.segment, {this.position, this.at});

  final Segment segment;

  /// Position in den normierten Koordinaten von DartLab, falls geliefert.
  final BoardPoint? position;

  /// Zeit des Darts, falls geliefert.
  final DateTime? at;
}

/// Eine Aufnahme (ein Spieler, 1–3 Darts).
class ImportedTurn {
  const ImportedTurn({required this.player, required this.darts, this.at});

  /// Index in [ImportedMatch.players].
  final int player;
  final List<ImportedDart> darts;
  final DateTime? at;
}

/// Ein Leg mit allen Aufnahmen beider Spieler in Wurfreihenfolge.
class ImportedLeg {
  const ImportedLeg({required this.set, required this.leg, required this.winner, required this.turns});

  final int set;
  final int leg;

  /// Sieger laut Daten (Index in [ImportedMatch.players]), `null` = nicht
  /// angegeben bzw. offen.
  final int? winner;
  final List<ImportedTurn> turns;
}

class ImportedPlayer {
  const ImportedPlayer({required this.id, required this.name});

  final String id;
  final String name;
}

/// Ein Match, wie es der Parser aus der Autodarts-Antwort gelesen hat.
/// Unabhängig von den Feldnamen der Antwort (die stehen allein in
/// `autodarts_match_mapping.dart`).
class ImportedMatch {
  const ImportedMatch({
    required this.id,
    required this.players,
    required this.legs,
    required this.startScore,
    required this.outMode,
    required this.doubleIn,
    required this.finishedAt,
    required this.finished,
    this.warnings = const [],
  });

  /// Autodarts-Match-Id (aus der Antwort, sonst aus der Adresse, sonst ein
  /// Abdruck des Inhalts). Dient der Duplikaterkennung.
  final String id;
  final List<ImportedPlayer> players;
  final List<ImportedLeg> legs;
  final int startScore;
  final OutMode outMode;
  final bool doubleIn;
  final DateTime? finishedAt;

  /// Das Match wurde zu Ende gespielt (alle Legs haben einen Sieger).
  final bool finished;

  /// Hinweise, was beim Lesen nicht eindeutig war (für Vorschau und Docs).
  final List<String> warnings;

  int get dartCount => legs.fold(0, (a, l) => a + l.turns.fold(0, (b, t) => b + t.darts.length));
}
