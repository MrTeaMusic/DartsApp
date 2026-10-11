import '../../../dart_source/domain/dart_event.dart';
import 'game_definition.dart';
import 'training_game.dart';

/// Eine Eingabe ins Spiel.
sealed class GameInput {
  const GameInput();
}

class DartInput extends GameInput {
  const DartInput(this.dart);
  final DartThrow dart;
}

class VisitEndInput extends GameInput {
  const VisitEndInput();
}

/// Ein gespeicherter Dart mit seinem Platz im Spiel.
class DartRecord {
  const DartRecord(this.dart, {required this.visitIndex, required this.counted});
  final DartThrow dart;
  final int visitIndex;

  /// `false`, wenn das Spiel den Dart ignoriert hat (nach Bust/Checkout).
  final bool counted;
}

/// Hält Config, Startwert und Eingaben eines laufenden Spiels.
///
/// Rückgängig und Korrektur bauen das Spiel aus den Eingaben neu auf.
/// Das ist billig (wenige hundert Darts) und garantiert, dass das Ergebnis
/// immer exakt zu den gespeicherten Würfen passt.
class GameSession {
  GameSession({required this.definition, required Map<String, Object?> config, required this.seed})
      : config = definition.resolve(config) {
    _game = _fresh();
  }

  final GameDefinition definition;
  final Map<String, Object?> config;
  final int seed;
  final List<GameInput> _inputs = [];
  final List<DartRecord> _records = [];
  late TrainingGame _game;

  TrainingGame get game => _game;
  List<GameInput> get inputs => List.unmodifiable(_inputs);

  /// Alle Darts in Wurfreihenfolge, passend zum aktuellen Spielstand.
  List<DartRecord> get records => List.unmodifiable(_records);

  TrainingGame _fresh() => definition.create(config, seed)..prepare();

  void addDart(DartThrow dart) {
    _inputs.add(DartInput(dart));
    _records.add(_apply(_game, dart));
  }

  static DartRecord _apply(TrainingGame game, DartThrow dart) {
    final before = game.dartsThrown;
    game.throwDart(dart);
    return DartRecord(dart, visitIndex: game.visitIndex, counted: game.dartsThrown > before);
  }

  /// Aufnahme beenden. Doppelte Enden werden zusammengefasst.
  void endVisit() {
    if (_inputs.isEmpty || _inputs.last is VisitEndInput) return;
    _inputs.add(const VisitEndInput());
    _game.endVisit();
  }

  /// Letzten Dart entfernen. Gibt `false` zurück, wenn es keinen gibt.
  bool undoLastDart() {
    final i = _inputs.lastIndexWhere((e) => e is DartInput);
    if (i < 0) return false;
    _inputs.removeRange(i, _inputs.length);
    _replay();
    return true;
  }

  /// Ersetzt den Dart an Position [indexInVisit] der laufenden Aufnahme
  /// (gezählt wie am Board, also inklusive ignorierter Darts).
  bool correctDart(int indexInVisit, DartThrow dart) {
    final inVisit = _game.physicalDartsInVisit;
    if (indexInVisit < 0 || indexInVisit >= inVisit) return false;
    final dartPositions = [
      for (var i = 0; i < _inputs.length; i++)
        if (_inputs[i] is DartInput) i,
    ];
    final target = dartPositions[dartPositions.length - inVisit + indexInVisit];
    _inputs[target] = DartInput(dart);
    _replay();
    return true;
  }

  void _replay() {
    final game = _fresh();
    _records.clear();
    for (final input in _inputs) {
      switch (input) {
        case DartInput(:final dart):
          _records.add(_apply(game, dart));
        case VisitEndInput():
          game.endVisit();
      }
    }
    game.events.clear();
    _game = game;
  }
}
