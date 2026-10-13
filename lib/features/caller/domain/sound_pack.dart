import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'caller_phrases.dart';

/// Eigene Sounddateien für den Caller: Dateiname (ohne Endung) → Pfad.
///
/// Namen, die der Caller sucht (Groß-/Kleinschreibung, Leerzeichen und
/// Bindestriche egal):
/// - `0` bis `180`: Punkte einer Aufnahme (`0` bzw. `no_score` für „No score“)
/// - `bust`, `game_on`
/// - `game_shot`, `game_shot_leg`, `game_shot_set`, `game_shot_match`
/// - `require_32` usw. oder `you_require` gefolgt von der Zahl als eigene
///   Datei
///
/// Fehlt eine Datei, spricht für diese eine Ansage die normale Stimme.
@immutable
class CallerSoundPack {
  const CallerSoundPack(this.files);

  static const empty = CallerSoundPack({});

  /// Dateiendungen, die als Sound übernommen werden.
  static const extensions = {'mp3', 'wav', 'm4a', 'aac', 'ogg'};

  /// Schlüssel → absoluter Pfad.
  final Map<String, String> files;

  bool get isEmpty => files.isEmpty;
  int get length => files.length;

  /// Schlüssel für einen Dateinamen, `null`, wenn die Endung kein Sound ist.
  static String? keyFor(String fileName) {
    final base = p.basename(fileName);
    final ext = p.extension(base).replaceFirst('.', '').toLowerCase();
    if (!extensions.contains(ext)) return null;
    if (base.startsWith('.')) return null; // ._180.mp3 (macOS) u. ä.
    final key = p.basenameWithoutExtension(base).trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
    return key.isEmpty ? null : key;
  }

  /// Baut ein Paket aus Dateipfaden. Bei gleichem Schlüssel gewinnt der
  /// erste Pfad.
  factory CallerSoundPack.fromPaths(Iterable<String> paths) {
    final files = <String, String>{};
    for (final path in paths) {
      final key = keyFor(path);
      if (key != null) files.putIfAbsent(key, () => path);
    }
    return CallerSoundPack(files);
  }

  /// Die Dateien, die [call] abspielt, oder `null`, wenn etwas fehlt und
  /// die Stimme übernehmen soll.
  List<String>? pathsFor(CallerCall call) {
    for (final keys in alternativesFor(call)) {
      if (keys.every(files.containsKey)) return [for (final k in keys) files[k]!];
    }
    return null;
  }

  /// Mögliche Dateifolgen für [call], die erste vollständige gewinnt.
  static List<List<String>> alternativesFor(CallerCall call) => switch (call) {
        GameOnCall() => const [
            ['game_on'],
          ],
        ScoreCall(:final score) => [
            if (score <= 0) const ['no_score'],
            ['${score < 0 ? 0 : score}'],
          ],
        BustCall() => const [
            ['bust'],
          ],
        RequireCall(:final remaining) => [
            ['require_$remaining'],
            ['you_require', '$remaining'],
          ],
        GameShotCall(:final kind) => [
            if (kind != GameShotKind.plain) ['game_shot_${kind.name}'],
            const ['game_shot'],
          ],
      };

  /// Punkte, die mit drei Darts nicht gehen (163, 166, …, 179). Für sie
  /// braucht kein Paket eine Datei.
  static final Set<int> impossibleScores = {
    for (var s = 0; s <= 180; s++)
      if (!_possibleScores.contains(s)) s,
  };

  static final Set<int> _possibleScores = () {
    final single = <int>{0, 25, 50};
    for (var n = 1; n <= 20; n++) {
      single.addAll([n, 2 * n, 3 * n]);
    }
    return {
      for (final a in single)
        for (final b in single)
          for (final c in single) a + b + c,
    };
  }();

  /// Mögliche Punkte (0–180), für die keine Datei da ist.
  List<int> get missingScores => [
        for (var s = 0; s <= 180; s++)
          if (!impossibleScores.contains(s) && !files.containsKey('$s') && !(s == 0 && files.containsKey('no_score'))) s,
      ];

  /// Ansagen außer Punkten, die das Paket abdeckt bzw. nicht abdeckt.
  static const extraKeys = ['bust', 'game_on', 'game_shot', 'you_require'];

  List<String> get presentExtras => [for (final k in extraKeys) if (files.containsKey(k)) k];
  List<String> get missingExtras => [for (final k in extraKeys) if (!files.containsKey(k)) k];

  @override
  bool operator ==(Object other) => other is CallerSoundPack && mapEquals(other.files, files);

  @override
  int get hashCode => Object.hashAllUnordered(files.entries.map((e) => Object.hash(e.key, e.value)));
}
