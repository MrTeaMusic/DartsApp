import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/domain/engine/training_game.dart';

/// Dart aus Kurzname, z. B. d('T20').
DartThrow d(String name) => DartThrow(
      segment: Segment.tryParse(name)!,
      timestamp: DateTime(2026, 10, 11),
      source: DartSourceKind.manual,
    );

/// Wirft mehrere Darts nacheinander.
void throwAll(TrainingGame game, List<String> names) {
  for (final n in names) {
    game.throwDart(d(n));
  }
}
