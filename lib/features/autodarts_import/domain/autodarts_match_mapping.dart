/// DIE EINE STELLE, die die Feldnamen der Autodarts-Antwort kennt.
///
/// ACHTUNG, NICHT AN ECHTEN DATEN GEPRÜFT. Die erwartete Form stammt aus
/// Community-Quellcode (siehe `docs/autodarts-import.md` und die Recherche
/// zur Cloud-Antwort `GET /as/v0/matches/<id>/stats`). Alle Fixtures in den
/// Tests sind selbst gebaut. Stimmt ein Name nicht, wird nur diese Datei
/// angepasst: Alles dahinter (Auswertung, Speicherung, Anzeige) arbeitet mit
/// den Klassen aus `imported_match.dart`.
///
/// Angenommene Form (alles optional, wo nicht anders vermerkt):
///
/// ```text
/// {
///   "id": "…"                     // Match-Id; sonst die Id aus der Adresse,
///                                 // sonst ein Abdruck des Inhalts
///   "variant": "X01"              // fehlt sie, gilt X01 nur mit settings.baseScore
///   "players": [ {"id": "…", "name": "…"}, … ]        // PFLICHT, genau zwei
///   "games": [                    // PFLICHT: ein Eintrag je Leg (auch "legs")
///     { "set": 1, "leg": 1,
///       "winnerPlayerId": "…",    // Sieger des Legs (auch "winner": Index/Id)
///       "settings": { "baseScore": 501, "inMode": "Straight",
///                     "outMode": "Double" },
///       "turns": [                // auch "rounds"
///         { "playerId": "…",      // auch "player": Index oder Id
///           "points": 60, "score": 441,   // werden NICHT gelesen: DartLab
///                                         // rechnet aus den Darts selbst
///           "createdAt": "…", "finishedAt": "…",
///           "throws": [           // auch "darts"
///             { "segment": { "name": "T20", "number": 20, "multiplier": 3,
///                            "bed": "Triple" },     // oder Text "T20"
///               "coords": { "x": 0.01, "y": 0.61 }, // optional
///               "entry": "…", "createdAt": "…" } ] } ] } ],
///   "matchStats": [ … ]           // wird NICHT gelesen
///   "settings": { "baseScore": 501, "inMode": "…", "outMode": "…" },
///   "host": { … },                // wird NICHT gelesen
///   "finishedAt": "…"             // ISO-Text oder Epoch (Sekunden/ms)
/// }
/// ```
///
/// Segmentnamen: `T20`, `S5`, `D16`, `25` (Single Bull), `Bull`/`50`
/// (Bullseye), `M12` und `Outside` (Fehlwurf). Koordinaten: wie beim lokalen
/// Board Manager (Mitte 0/0, Radius 1 = Außenkante Double, y zeigt zur 20);
/// ob die Cloud dieselben Werte liefert, ist ungeprüft.
///
/// Auch tolerant gegenüber einer Umhüllung (`{"data": {…}}`, `{"match": {…}}`,
/// `{"stats": {…}}`) und einem Live-Zustand ohne `games`, der die Aufnahmen
/// flach in `turns` (mit `leg`/`set` je Aufnahme) liefert.
library;

import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../dart_source/data/autodarts_state_mapper.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import 'imported_match.dart';

/// Liest die Antwort. Wirft [AutodartsImportException] mit klarem Text, wenn
/// sie nicht brauchbar ist; sonst gibt es nur Hinweise in
/// [ImportedMatch.warnings].
///
/// [externalId] ist die Match-Id aus der Adresse der Anfrage, falls die
/// Antwort selbst keine enthält.
ImportedMatch parseAutodartsMatch(Object? json, {String? externalId}) {
  final root = _root(json);
  final warnings = <String>[];

  final settings = _map(root['settings']);
  final games = _list(root['games'] ?? root['legs']) ?? _gamesFromFlatTurns(root);
  if (games == null || games.isEmpty) {
    throw const AutodartsImportException(ImportProblem.format, 'Format unbekannt: keine Legs (games) im Match.');
  }
  final firstGameSettings = _map(_map(games.first)['settings']);

  final variant = _text(root['variant'] ?? settings['variant'] ?? firstGameSettings['variant']);
  final baseScore = _int(settings['baseScore'] ?? firstGameSettings['baseScore'] ?? settings['startScore'] ?? firstGameSettings['startScore']);
  if (variant != null) {
    if (variant.trim().toLowerCase() != 'x01') {
      throw AutodartsImportException(ImportProblem.notX01, 'Kein X01-Match (Variante: ${variant.trim()}).');
    }
  } else if (baseScore == null) {
    throw const AutodartsImportException(ImportProblem.format, 'Format unbekannt: weder Variante noch Startwert im Match.');
  }

  // Spieler.
  final rawPlayers = _list(root['players']);
  if (rawPlayers == null || rawPlayers.isEmpty) {
    throw const AutodartsImportException(ImportProblem.format, 'Format unbekannt: keine Spieler (players) im Match.');
  }
  final players = <ImportedPlayer>[];
  for (final (i, p) in rawPlayers.indexed) {
    final m = _map(p);
    final user = _map(m['user']);
    final name = _text(m['name'] ?? m['displayName'] ?? user['name']) ?? 'Spieler ${i + 1}';
    players.add(ImportedPlayer(id: _text(m['id'] ?? m['playerId']) ?? '$i', name: name.trim()));
  }
  if (players.length < 2) {
    throw const AutodartsImportException(ImportProblem.players, 'Nur Matches mit zwei Spielern werden importiert (hier: 1 Spieler).');
  }
  if (players.length > 2) {
    throw AutodartsImportException(
      ImportProblem.players,
      'Nur Matches mit zwei Spielern werden importiert (hier: ${players.length} Spieler).',
    );
  }

  // Startwert und Modi.
  var startScore = baseScore;
  if (startScore == null || startScore < 2 || startScore > 1001) {
    warnings.add('Startwert nicht gefunden, 501 angenommen.');
    startScore = 501;
  }
  final outRaw = _text(settings['outMode'] ?? firstGameSettings['outMode'])?.toLowerCase() ?? '';
  final outMode = outRaw.contains('master')
      ? OutMode.master
      : (outRaw.contains('straight') || outRaw.contains('single') || outRaw.contains('open'))
          ? OutMode.straight
          : OutMode.double;
  final inRaw = _text(settings['inMode'] ?? firstGameSettings['inMode'])?.toLowerCase() ?? '';
  final doubleIn = inRaw.contains('double') || inRaw.contains('master');
  if (doubleIn) warnings.add('Double-In wird in der Auswertung nicht berücksichtigt.');

  // Legs.
  final legs = <ImportedLeg>[];
  var unknownDarts = 0;
  var unknownTurns = 0;
  final positions = <BoardPoint>[];
  var dartCount = 0;
  for (final (gi, g) in games.indexed) {
    final gm = _map(g);
    final rawTurns = _list(gm['turns'] ?? gm['rounds']) ?? const [];
    final turns = <ImportedTurn>[];
    for (final t in rawTurns) {
      final tm = _map(t);
      final player = _playerIndex(tm['playerId'] ?? tm['player'], players);
      if (player == null) {
        unknownTurns++;
        continue;
      }
      final rawDarts = _list(tm['throws'] ?? tm['darts']) ?? const [];
      final darts = <ImportedDart>[];
      for (final d in rawDarts) {
        final dart = _dart(d);
        if (dart == null) {
          unknownDarts++;
          darts.add(const ImportedDart(Segment.miss));
          dartCount++;
          continue;
        }
        darts.add(dart);
        dartCount++;
        if (dart.position != null) positions.add(dart.position!);
      }
      if (darts.isEmpty) continue;
      turns.add(ImportedTurn(player: player, darts: darts, at: _time(tm['finishedAt'] ?? tm['createdAt'])));
    }
    legs.add(ImportedLeg(
      set: _int(gm['set']) ?? 1,
      leg: _int(gm['leg']) ?? gi + 1,
      winner: _playerIndex(gm['winnerPlayerId'] ?? gm['winner'], players),
      turns: turns,
    ));
  }
  if (unknownTurns > 0) warnings.add('$unknownTurns Aufnahmen ohne bekannten Spieler übersprungen.');
  if (unknownDarts > 0) warnings.add('$unknownDarts Darts nicht erkannt, als Fehlwurf gewertet.');
  if (dartCount == 0) {
    throw const AutodartsImportException(ImportProblem.empty, 'Das Match enthält keine Darts.');
  }

  // Koordinaten nur übernehmen, wenn sie zu Radius-1-Koordinaten passen.
  var cleaned = legs;
  if (positions.isNotEmpty) {
    final far = positions.where((p) => p.distance > 3.5).length;
    if (far / positions.length > 0.2) {
      warnings.add('Koordinaten wirken unplausibel (andere Einheit?) und wurden nicht übernommen.');
      cleaned = [
        for (final l in legs)
          ImportedLeg(
            set: l.set,
            leg: l.leg,
            winner: l.winner,
            turns: [
              for (final t in l.turns)
                ImportedTurn(player: t.player, at: t.at, darts: [for (final d in t.darts) ImportedDart(d.segment, at: d.at)]),
            ],
          ),
      ];
    }
  }

  final finishedAt = _time(root['finishedAt'] ?? root['finished_at'] ?? root['endedAt']);
  final finishedFlag = root['finished'];
  final finished = finishedFlag is bool ? finishedFlag : (finishedAt != null || cleaned.every((l) => l.winner != null));

  final id = _text(root['id'] ?? root['matchId'] ?? root['match_id']) ?? externalId ?? _fingerprint(players, cleaned);
  return ImportedMatch(
    id: id,
    players: players,
    legs: cleaned,
    startScore: startScore,
    outMode: outMode,
    doubleIn: doubleIn,
    finishedAt: finishedAt,
    finished: finished,
    warnings: warnings,
  );
}

// ---------------------------------------------------------------------------
// Hilfen
// ---------------------------------------------------------------------------

/// Packt eine Umhüllung aus, bis `players` oder `games` sichtbar sind.
Map<String, Object?> _root(Object? json) {
  if (json is! Map) {
    throw const AutodartsImportException(ImportProblem.format, 'Format unbekannt: Erwartet wird ein JSON-Objekt.');
  }
  var m = _map(json);
  for (var depth = 0; depth < 3; depth++) {
    if (m.containsKey('players') || m.containsKey('games')) return m;
    Map<String, Object?>? inner;
    for (final key in const ['data', 'match', 'stats', 'result']) {
      final v = m[key];
      if (v is Map) {
        inner = _map(v);
        break;
      }
    }
    if (inner == null) break;
    m = inner;
  }
  return m;
}

/// Live-Zustand: flache `turns` mit `leg`/`set` je Aufnahme zu Legs gruppieren.
List<Object?>? _gamesFromFlatTurns(Map<String, Object?> root) {
  final turns = _list(root['turns']);
  if (turns == null || turns.isEmpty) return null;
  final groups = <String, List<Object?>>{};
  for (final t in turns) {
    final m = _map(t);
    groups.putIfAbsent('${m['set'] ?? 1}/${m['leg'] ?? 1}', () => []).add(t);
  }
  return [
    for (final e in groups.entries)
      {
        'set': int.tryParse(e.key.split('/').first),
        'leg': int.tryParse(e.key.split('/').last),
        'turns': e.value,
      },
  ];
}

Map<String, Object?> _map(Object? v) => v is Map ? {for (final e in v.entries) '${e.key}': e.value} : const {};

List<Object?>? _list(Object? v) => v is List ? v : null;

String? _text(Object? v) => switch (v) {
      final String s when s.trim().isNotEmpty => s,
      final num n => '$n',
      _ => null,
    };

int? _int(Object? v) => switch (v) {
      final int i => i,
      final double d => d.round(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    };

DateTime? _time(Object? v) {
  switch (v) {
    case final String s:
      return DateTime.tryParse(s.trim())?.toLocal();
    case final num n:
      final ms = n > 100000000000 ? n.toInt() : (n * 1000).toInt();
      return DateTime.fromMillisecondsSinceEpoch(ms);
    default:
      return null;
  }
}

/// Spieler aus einer Id (Text) oder einem Index (Zahl); `null` bei -1 oder
/// Unbekanntem.
int? _playerIndex(Object? ref, List<ImportedPlayer> players) {
  if (ref == null) return null;
  final text = ref is String ? ref.trim() : '$ref';
  final byId = players.indexWhere((p) => p.id == text);
  if (byId >= 0) return byId;
  final index = ref is num ? ref.toInt() : int.tryParse(text);
  if (index != null && index >= 0 && index < players.length) return index;
  return null;
}

ImportedDart? _dart(Object? raw) {
  if (raw is String) {
    final s = _segmentName(raw);
    return s == null ? null : ImportedDart(s);
  }
  final m = _map(raw);
  if (m.isEmpty) return null;
  final seg = m['segment'];
  Segment? segment;
  if (seg is String) {
    segment = _segmentName(seg);
  } else if (seg is Map) {
    segment = AutodartsStateMapper.parseSegment(seg) ?? _segmentName(_text(_map(seg)['name']));
  } else {
    segment = AutodartsStateMapper.parseSegment(m) ?? _segmentName(_text(m['name']));
  }
  if (segment == null) return null;
  return ImportedDart(
    segment,
    position: AutodartsStateMapper.parseCoords(m['coords'] ?? m['position']),
    at: _time(m['createdAt'] ?? m['timestamp']),
  );
}

Segment? _segmentName(String? name) {
  if (name == null) return null;
  final n = name.trim().toUpperCase();
  if (n.isEmpty) return null;
  // Fehlwurf: "M12" (Sektor, aber außerhalb), "Outside", "Miss", "0".
  if (RegExp(r'^M\d*$').hasMatch(n) || n == 'MISS' || n == 'OUTSIDE' || n == 'OUT' || n == 'NONE' || n == '0') return Segment.miss;
  if (n == 'SBULL' || n == 'SINGLEBULL' || n == 'OUTERBULL') return Segment.outerBull;
  if (n == 'DBULL' || n == 'DOUBLEBULL' || n == 'INNERBULL' || n == 'BULLSEYE') return Segment.bull;
  return Segment.tryParse(n);
}

/// Stabiler Abdruck aus Spielernamen, Siegern und Darts, wenn das Match
/// keine Id hat. Gleiches Match → gleiche Id, unabhängig von der Schreibweise
/// des JSON. Zwei kleine Streuwerte (passen auch in Web-Zahlen).
String _fingerprint(List<ImportedPlayer> players, List<ImportedLeg> legs) {
  final b = StringBuffer(players.map((p) => p.name).join('|'));
  for (final l in legs) {
    b.write('/${l.set}.${l.leg}:${l.winner}');
    for (final t in l.turns) {
      b.write(';${t.player}=${t.darts.map((d) => d.segment.name).join(',')}');
    }
  }
  var a = 7, c = 11;
  for (final u in b.toString().codeUnits) {
    a = (a * 31 + u) % 2147483629;
    c = (c * 37 + u + 1) % 2147483587;
  }
  String hex(int v) => v.toRadixString(16).padLeft(8, '0');
  return 'h-${hex(a)}${hex(c)}';
}
