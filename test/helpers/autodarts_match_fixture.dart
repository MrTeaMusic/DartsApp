import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';

/// SYNTHETISCH. Dieses Match ist selbst gebaut nach der Form, die in
/// `lib/features/autodarts_import/domain/autodarts_match_mapping.dart`
/// beschrieben ist. Es stammt NICHT aus einer echten Autodarts-Antwort; die
/// Namen sind „Ben“ und „Gegner“. Ob die echte Antwort so aussieht, ist
/// ungeprüft.
///
/// Ein 501-Match, 3:2 für Ben, mit fünf Legs. Leg 3 enthält einen Bust von
/// Ben; wer ein Leg verliert, wirft vor dem Ende Fehlwürfe (`M12`). Ben
/// beginnt Leg 1, 3 und 5, der Gegner Leg 2 und 4.
Map<String, Object?> syntheticMatch({
  String ben = 'Ben',
  String opponent = 'Gegner',
  String? id = 'synthetic-0001',
  bool coords = true,
  String variant = 'X01',
  int start = 501,
  String outMode = 'Double',
  List<int> winners = const [0, 1, 0, 1, 0],
  bool finished = true,
  String? finishedAt = '2026-10-20T19:45:00.000Z',
}) {
  const benId = 'p-ben';
  const oppId = 'p-opp';
  final base = DateTime.utc(2026, 10, 20, 19, 0);
  var clock = base;

  Map<String, Object?> segmentJson(Segment s, {int? missNumber}) {
    if (s.isMiss) {
      return {'name': 'M${missNumber ?? 12}', 'number': missNumber ?? 12, 'multiplier': 0, 'bed': 'Outside'};
    }
    if (s == Segment.bull) return {'name': 'Bull', 'number': 25, 'multiplier': 2, 'bed': 'DoubleBull'};
    if (s == Segment.outerBull) return {'name': '25', 'number': 25, 'multiplier': 1, 'bed': 'SingleBull'};
    return {
      'name': s.name,
      'number': s.number,
      'multiplier': s.multiplier,
      'bed': switch (s.multiplier) {
        3 => 'Triple',
        2 => 'Double',
        _ => 'Single',
      },
    };
  }

  Map<String, Object?> throwJson(Segment s, {int? missNumber}) {
    clock = clock.add(const Duration(seconds: 5));
    final p = s.isMiss ? const BoardPoint(1.4, 0.2) : BoardGeometry.centerOf(s);
    return {
      'segment': segmentJson(s, missNumber: missNumber),
      if (coords) 'coords': {'x': p.x, 'y': p.y},
      'entry': 'Detected',
      'createdAt': clock.toIso8601String(),
    };
  }

  List<Segment> names(List<String> n) => [for (final x in n) Segment.tryParse(x) ?? Segment.miss];

  // Wurfmuster beim Scoring (Ben etwa Average 70, der Gegner etwa 50).
  final benScoring = [
    names(['T20', 'T20', 'T20']),
    names(['T20', 'T19', 'S20']),
    names(['T20', 'S20', 'S20']),
    names(['T19', 'T20', 'S19']),
    names(['S20', 'T20', 'S5']),
  ];
  final oppScoring = [
    names(['T20', 'S20', 'S20']),
    names(['S20', 'S5', 'S1']),
    names(['T19', 'S19', 'S19']),
    names(['T20', 'S1', 'S5']),
    names(['S19', 'S18', 'S17']),
  ];

  final games = <Object?>[];
  for (var leg = 0; leg < winners.length; leg++) {
    final winner = winners[leg];
    final remaining = [start, start];
    final cursor = [leg, leg + 2];
    final turns = <Object?>[];
    var player = leg.isEven ? 0 : 1;
    var bustDone = false;
    for (var guard = 0; guard < 60; guard++) {
      final r = remaining[player];
      List<Segment> visit;
      var bust = false;
      final finish = r <= 170 ? CheckoutRules.suggest(r, darts: 3, out: OutMode.double) : null;
      if (player == 0 && leg == 2 && !bustDone && r > 60 && r <= 180) {
        // Bust: Triple 20, bis der Rest überworfen ist (der Bust-Dart ist der letzte der Aufnahme).
        visit = [];
        var rest = r;
        while (visit.length < 3) {
          final t = Segment.triple(20);
          visit.add(t);
          if (CheckoutRules.isBust(rest, t, OutMode.double)) break;
          rest -= t.score;
        }
        bust = true;
        bustDone = true;
      } else if (player == winner && finish != null) {
        visit = finish;
      } else if (r <= 170) {
        // Wer das Leg nicht gewinnt, trifft die Doppel nicht (auch ein Fehlwurf).
        visit = r > 12 ? [Segment.single(1), Segment.miss, Segment.single(1)] : [Segment.miss, Segment.miss, Segment.miss];
      } else {
        final scoring = player == 0 ? benScoring : oppScoring;
        visit = scoring[cursor[player]++ % scoring.length];
        if (r - visit.fold(0, (a, s) => a + s.score) < 2) visit = names(['S1', 'S1', 'S1']);
      }
      final points = bust ? 0 : visit.fold(0, (a, s) => a + s.score);
      if (!bust) remaining[player] -= points;
      clock = clock.add(const Duration(seconds: 12));
      turns.add({
        'playerId': player == 0 ? benId : oppId,
        'points': points,
        'score': remaining[player],
        'busted': bust,
        'createdAt': clock.toIso8601String(),
        'throws': [for (final s in visit) throwJson(s, missNumber: s.isMiss ? 12 : null)],
      });
      if (remaining[player] == 0) break;
      player = 1 - player;
    }
    assert(remaining[winner] == 0, 'Leg ${leg + 1}: Sieger hat nicht ausgecheckt (${remaining[winner]})');
    games.add({
      'set': 1,
      'leg': leg + 1,
      'winnerPlayerId': winner == 0 ? benId : oppId,
      'settings': {'baseScore': start, 'inMode': 'Straight', 'outMode': outMode},
      'turns': turns,
    });
  }

  return {
    'id': ?id,
    'variant': variant,
    'players': [
      {'id': benId, 'name': ben},
      {'id': oppId, 'name': opponent},
    ],
    'games': games,
    'matchStats': [
      {'playerId': benId, 'average': 70.1},
      {'playerId': oppId, 'average': 48.2},
    ],
    'settings': {'baseScore': start, 'inMode': 'Straight', 'outMode': outMode, 'maxRounds': 80},
    'host': {'name': 'synthetic'},
    'finished': finished,
    'finishedAt': ?finishedAt,
  };
}
