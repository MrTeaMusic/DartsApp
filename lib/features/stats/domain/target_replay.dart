import '../../../core/database/app_database.dart';
import '../../board/domain/segment.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../games/domain/engine/game_definition.dart';
import '../../games/domain/engine/training_game.dart';
import '../../games/domain/game_catalog.dart';

/// Ein gezählter Dart mit dem Ziel, das das Spiel in diesem Moment
/// hervorgehoben hat.
class AimedDart {
  const AimedDart(this.row, this.segment, this.targets);
  final ThrowRow row;
  final Segment segment;

  /// Leer, wenn das Spiel kein Ziel vorgibt.
  final Set<Segment> targets;

  bool get onTarget => targets.contains(segment);

  /// Genau ein Double (oder das Bullseye) als Ziel, z. B. in Bob's 27,
  /// Around the Clock auf Doubles oder ein Checkout-Dart aufs Double.
  int? get aimedDouble {
    if (targets.length != 1) return null;
    final t = targets.first;
    return t.isDouble ? t.number : null;
  }

  /// Genau ein Triple als Ziel, z. B. T20-Training oder Highscore-Jagd.
  int? get aimedTreble {
    if (targets.length != 1) return null;
    final t = targets.first;
    return t.isTriple ? t.number : null;
  }
}

/// Baut das Segment eines gespeicherten Wurfs nach (mit innerer/äußerer
/// Single-Fläche, damit es exakt mit den Zielen des Spiels vergleichbar ist).
Segment? segmentOf(ThrowRow t) {
  final bed = Bed.values.where((b) => b.name == t.bed).firstOrNull;
  try {
    return switch (bed) {
      Bed.singleInner => Segment.single(t.number, inner: true),
      Bed.singleOuter => Segment.single(t.number),
      Bed.double => Segment.double(t.number),
      Bed.triple => Segment.triple(t.number),
      Bed.outerBull => Segment.outerBull,
      Bed.innerBull => Segment.bull,
      Bed.miss => Segment.miss,
      null => Segment.tryParse(t.segment),
    };
  } on ArgumentError {
    return Segment.tryParse(t.segment);
  }
}

/// Spielt eine Session mit ihren gespeicherten Würfen erneut durch und
/// liefert zu jedem gezählten Dart das damalige Ziel.
///
/// Spiele sind deterministisch aus Config, Startwert und Würfen, deshalb
/// braucht es dafür keine zusätzlichen Spalten in der Datenbank. Aufnahmen,
/// die vor dem dritten Dart beendet wurden (Takeout, "Weiter"), erkennt die
/// Funktion am Sprung im Aufnahme-Index. Unbekannte Spiele oder Fehler beim
/// Abspielen ergeben eine leere Liste.
List<AimedDart> replayTargets(SessionRow session, List<ThrowRow> throws, Map<String, Object?> config,
    {GameDefinition? Function(String id) lookup = GameCatalog.byId}) {
  final def = lookup(session.gameId);
  if (def == null || throws.isEmpty) return const [];
  try {
    final TrainingGame game = def.start(config, session.seed)..prepare();
    final sorted = [...throws]..sort((a, b) => a.seq.compareTo(b.seq));
    final out = <AimedDart>[];
    for (final t in sorted) {
      final seg = segmentOf(t);
      if (seg == null) return const [];
      if (t.visitIndex > game.visitIndex && game.physicalDartsInVisit > 0 && game.physicalDartsInVisit < TrainingGame.dartsPerVisit) {
        game.endVisit();
      }
      final targets = Set<Segment>.of(game.targets);
      final before = game.dartsThrown;
      game.throwDart(DartThrow(segment: seg, timestamp: t.timestamp, source: DartSourceKind.manual));
      if (game.dartsThrown > before && t.counted) out.add(AimedDart(t, seg, targets));
    }
    return out;
  } on Object {
    return const [];
  }
}
