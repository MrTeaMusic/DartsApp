import 'dart:convert';

import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';

/// Mitschnitt mit Koordinaten, die durch [distort] verfälscht sind.
String recording(List<String> names, BoardPoint Function(BoardPoint) distort) {
  final lines = <String>[];
  final throws = <Map<String, Object?>>[];
  lines.add(jsonEncode({'numThrows': 0, 'throws': <Object>[]}));
  for (final n in names) {
    final s = Segment.tryParse(n)!;
    final p = distort(BoardGeometry.centerOf(s));
    throws.add({
      'segment': {'name': n, 'number': s.number, 'multiplier': s.multiplier},
      'coords': {'x': p.x, 'y': p.y},
    });
    lines.add(jsonEncode({'numThrows': throws.length, 'throws': throws}));
    if (throws.length == 3) {
      throws.clear();
      lines.add(jsonEncode({'numThrows': 0, 'throws': <Object>[], 'event': 'Takeout finished'}));
    }
  }
  return lines.join('\n');
}

const sample = ['T20', 'D6', 'D3', 'S11', 'T14', 'D17', 'S1', 'T5', 'D19', 'S8', 'T16', 'D2'];
