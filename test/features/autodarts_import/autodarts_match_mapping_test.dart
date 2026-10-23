import 'dart:convert';

import 'package:dartlab/features/autodarts_import/domain/autodarts_match_mapping.dart';
import 'package:dartlab/features/autodarts_import/domain/imported_match.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/autodarts_match_fixture.dart';

// Alle Daten in diesen Tests sind synthetisch (siehe autodarts_match_fixture.dart).

/// Wie eine echte Antwort: erst als Text, dann gelesen.
Object? viaJson(Object? v) => jsonDecode(jsonEncode(v));

Map<String, Object?> tiny({Object? segment, Object? throws, Map<String, Object?>? extra}) => {
      'variant': 'X01',
      'players': [
        {'id': 'a', 'name': 'Ben'},
        {'id': 'b', 'name': 'Gegner'},
      ],
      'settings': {'baseScore': 301},
      'games': [
        {
          'winnerPlayerId': 'a',
          'turns': [
            {
              'playerId': 'a',
              'throws': throws ?? [if (segment != null) {'segment': segment}],
            },
          ],
        },
      ],
      ...?extra,
    };

Segment? firstDart(Map<String, Object?> json) => parseAutodartsMatch(viaJson(json)).legs.first.turns.first.darts.firstOrNull?.segment;

void main() {
  group('Normales Match', () {
    final match = parseAutodartsMatch(viaJson(syntheticMatch()));

    test('Spieler, Startwert, Modi und Ende', () {
      expect(match.id, 'synthetic-0001');
      expect([for (final p in match.players) p.name], ['Ben', 'Gegner']);
      expect(match.startScore, 501);
      expect(match.outMode, OutMode.double);
      expect(match.doubleIn, isFalse);
      expect(match.finished, isTrue);
      expect(match.finishedAt!.isAtSameMomentAs(DateTime.utc(2026, 10, 20, 19, 45)), isTrue);
      expect(match.warnings, isEmpty);
    });

    test('fünf Legs mit Siegern und allen Aufnahmen beider Spieler', () {
      expect(match.legs, hasLength(5));
      expect([for (final l in match.legs) l.winner], [0, 1, 0, 1, 0]);
      expect([for (final l in match.legs) l.set], everyElement(1));
      expect(match.legs.first.turns.first.player, 0, reason: 'Ben beginnt Leg 1');
      expect(match.legs[1].turns.first.player, 1, reason: 'Gegner beginnt Leg 2');
      final players = {for (final t in match.legs.expand((l) => l.turns)) t.player};
      expect(players, {0, 1});
    });

    test('Darts mit Feld, Position und Zeit; Fehlwurf wird zum Fehlwurf', () {
      final darts = [for (final l in match.legs) for (final t in l.turns) ...t.darts];
      expect(darts, isNotEmpty);
      expect(darts.every((d) => d.position != null && d.at != null), isTrue);
      expect(darts.where((d) => d.segment.isMiss), isNotEmpty, reason: 'M12 / Outside');
      final first = match.legs.first.turns.first.darts;
      expect([for (final d in first) d.segment.name], ['T20', 'T20', 'T20']);
    });

    test('ohne coords gibt es keine Positionen und keinen Fehler', () {
      final m = parseAutodartsMatch(viaJson(syntheticMatch(coords: false)));
      expect(m.dartCount, match.dartCount);
      expect(m.legs.expand((l) => l.turns).expand((t) => t.darts).every((d) => d.position == null), isTrue);
    });
  });

  group('Feldnamen und Segmente', () {
    test('Namen als Text und als Objekt', () {
      expect(firstDart(tiny(segment: 'T20')), Segment.triple(20));
      expect(firstDart(tiny(segment: {'name': 'S5'})), Segment.single(5));
      expect(firstDart(tiny(segment: {'name': 'D16'})), Segment.double(16));
      expect(firstDart(tiny(segment: {'name': '25'})), Segment.outerBull);
      expect(firstDart(tiny(segment: {'name': 'Bull'})), Segment.bull);
      expect(firstDart(tiny(segment: {'name': 'SB'})), Segment.outerBull);
      expect(firstDart(tiny(segment: {'name': 'DB'})), Segment.bull);
    });

    test('Fehlwurf als M12, Outside, Multiplikator 0', () {
      expect(firstDart(tiny(segment: {'name': 'M12'})), Segment.miss);
      expect(firstDart(tiny(segment: 'M7')), Segment.miss);
      expect(firstDart(tiny(segment: {'name': 'Outside'})), Segment.miss);
      expect(firstDart(tiny(segment: {'number': 12, 'multiplier': 0, 'bed': 'Outside', 'name': 'M12'})), Segment.miss);
    });

    test('Zahl und Multiplikator vor dem Namen, innere Single über bed', () {
      expect(firstDart(tiny(segment: {'number': 20, 'multiplier': 3, 'bed': 'Triple'})), Segment.triple(20));
      expect(firstDart(tiny(segment: {'number': 25, 'multiplier': 2, 'bed': 'DoubleBull'})), Segment.bull);
      expect(firstDart(tiny(segment: {'number': 5, 'multiplier': 1, 'bed': 'SingleInner'})), Segment.single(5, inner: true));
    });

    test('unlesbarer Dart zählt als Fehlwurf, mit Hinweis', () {
      final m = parseAutodartsMatch(viaJson(tiny(segment: {'name': 'Zebra'})));
      expect(m.legs.first.turns.first.darts.single.segment, Segment.miss);
      expect(m.warnings.single, contains('nicht erkannt'));
    });

    test('abweichende Namen: rounds/darts, Spielerindex, Umhüllung', () {
      final json = {
        'data': {
          'variant': 'x01',
          'players': [
            {'name': 'Ben'},
            {'name': 'Gegner'},
          ],
          'settings': {'startScore': 301, 'outMode': 'Straight'},
          'legs': [
            {
              'winnerPlayerId': 0,
              'rounds': [
                {
                  'player': 0,
                  'darts': [
                    {'segment': 'T20'},
                    'S5',
                    {'name': 'D18'},
                  ],
                },
                {
                  'player': 1,
                  'darts': ['S20'],
                },
              ],
            },
          ],
        },
      };
      final m = parseAutodartsMatch(viaJson(json));
      expect(m.startScore, 301);
      expect(m.outMode, OutMode.straight);
      expect(m.legs.single.winner, 0);
      expect([for (final d in m.legs.single.turns.first.darts) d.segment.name], ['T20', 'S5', 'D18']);
      expect(m.legs.single.turns.last.player, 1);
    });

    test('Live-Zustand mit flachen turns wird zu Legs gruppiert', () {
      final json = {
        'variant': 'X01',
        'settings': {'baseScore': 501},
        'players': [
          {'id': 'a', 'name': 'Ben'},
          {'id': 'b', 'name': 'Gegner'},
        ],
        'finished': true,
        'turns': [
          {'playerId': 'a', 'leg': 1, 'set': 1, 'throws': [{'segment': {'name': 'T20'}}]},
          {'playerId': 'b', 'leg': 1, 'set': 1, 'throws': [{'segment': {'name': 'S1'}}]},
          {'playerId': 'a', 'leg': 2, 'set': 1, 'throws': [{'segment': {'name': 'T19'}}]},
        ],
      };
      final m = parseAutodartsMatch(viaJson(json));
      expect(m.legs, hasLength(2));
      expect(m.legs.first.turns, hasLength(2));
    });

    test('Zeit als Epoch in Sekunden und Millisekunden', () {
      final s = parseAutodartsMatch(viaJson(tiny(segment: 'S1', extra: {'finishedAt': 1760990400, 'id': 'x'})));
      final ms = parseAutodartsMatch(viaJson(tiny(segment: 'S1', extra: {'finishedAt': 1760990400000, 'id': 'x'})));
      expect(s.finishedAt!.isAtSameMomentAs(ms.finishedAt!), isTrue);
      expect(s.finishedAt!.toUtc().year, 2025);
    });
  });

  group('Id', () {
    test('aus dem Match, sonst aus der Adresse, sonst ein stabiler Abdruck', () {
      final noId = viaJson(syntheticMatch(id: null));
      expect(parseAutodartsMatch(noId, externalId: 'from-url').id, 'from-url');
      final a = parseAutodartsMatch(noId).id;
      final b = parseAutodartsMatch(viaJson(syntheticMatch(id: null, finishedAt: null))).id;
      expect(a, startsWith('h-'));
      expect(a, b, reason: 'gleicher Inhalt, gleiche Id');
      final other = parseAutodartsMatch(viaJson(syntheticMatch(id: null, winners: [0, 0, 0, 1, 0]))).id;
      expect(other, isNot(a));
      expect(parseAutodartsMatch(viaJson(syntheticMatch(id: 'in-body')), externalId: 'from-url').id, 'in-body');
    });
  });

  group('Unbrauchbares gibt klare Fehler statt Absturz', () {
    void expectProblem(Object? json, ImportProblem problem, String text) {
      expect(
        () => parseAutodartsMatch(json),
        throwsA(isA<AutodartsImportException>()
            .having((e) => e.problem, 'problem', problem)
            .having((e) => e.message, 'message', contains(text))),
      );
    }

    test('kein Objekt', () {
      expectProblem(null, ImportProblem.format, 'Format unbekannt');
      expectProblem(<Object?>[], ImportProblem.format, 'Format unbekannt');
      expectProblem('text', ImportProblem.format, 'Format unbekannt');
      expectProblem(42, ImportProblem.format, 'Format unbekannt');
    });

    test('Objekt ohne Match-Felder', () {
      expectProblem(<String, Object?>{}, ImportProblem.format, 'Format unbekannt');
      expectProblem({'foo': 'bar'}, ImportProblem.format, 'Format unbekannt');
      expectProblem({'players': <Object?>[]}, ImportProblem.format, 'Format unbekannt');
    });

    test('fremde Variante', () {
      expectProblem({...viaJson(syntheticMatch()) as Map<String, Object?>, 'variant': 'Cricket'}, ImportProblem.notX01, 'Kein X01-Match');
      expectProblem({...viaJson(syntheticMatch()) as Map<String, Object?>, 'variant': 'Bermuda'}, ImportProblem.notX01, 'Bermuda');
    });

    test('keine Spieler oder falsche Anzahl', () {
      final base = viaJson(syntheticMatch()) as Map<String, Object?>;
      expectProblem({...base, 'players': <Object?>[]}, ImportProblem.format, 'keine Spieler');
      expectProblem(
        {
          ...base,
          'players': [
            {'id': 'p-ben', 'name': 'Ben'},
          ],
        },
        ImportProblem.players,
        'zwei Spielern',
      );
      expectProblem(
        {
          ...base,
          'players': [
            {'id': 'p-ben', 'name': 'Ben'},
            {'id': 'p-opp', 'name': 'Gegner'},
            {'id': 'p-3', 'name': 'Dritter'},
          ],
        },
        ImportProblem.players,
        '3 Spieler',
      );
    });

    test('Match ohne Darts', () {
      final base = viaJson(syntheticMatch()) as Map<String, Object?>;
      expectProblem({...base, 'games': <Object?>[]}, ImportProblem.format, 'keine Legs');
      expectProblem(
        {
          ...base,
          'games': [
            {'winnerPlayerId': 'p-ben', 'turns': <Object?>[]},
          ],
        },
        ImportProblem.empty,
        'keine Darts',
      );
    });

    test('Aufnahme eines unbekannten Spielers wird übersprungen, nicht geworfen', () {
      final json = tiny(throws: [
        {'segment': 'T20'},
      ]);
      ((json['games']! as List).first as Map)['turns'] = [
        {'playerId': 'fremd', 'throws': [{'segment': 'S1'}]},
        {'playerId': 'a', 'throws': [{'segment': 'T20'}]},
      ];
      final m = parseAutodartsMatch(viaJson(json));
      expect(m.legs.single.turns, hasLength(1));
      expect(m.warnings.single, contains('übersprungen'));
    });

    test('Koordinaten in anderer Einheit werden verworfen, das Match bleibt', () {
      final json = tiny(throws: [
        {'segment': 'T20', 'coords': {'x': 12.0, 'y': 80.0}},
        {'segment': 'S20', 'coords': {'x': -40.0, 'y': 90.0}},
      ]);
      final m = parseAutodartsMatch(viaJson(json));
      expect(m.dartCount, 2);
      expect(m.legs.single.turns.single.darts.every((d) => d.position == null), isTrue);
      expect(m.warnings.single, contains('Koordinaten'));
    });

    test('fehlender Startwert: 501 mit Hinweis; Double-In mit Hinweis', () {
      final json = tiny(segment: 'T20');
      json.remove('settings');
      ((json['games']! as List).first as Map)['settings'] = {'inMode': 'Double'};
      json['variant'] = 'X01';
      final m = parseAutodartsMatch(viaJson(json));
      expect(m.startScore, 501);
      expect(m.doubleIn, isTrue);
      expect(m.warnings, hasLength(2));
    });
  });
}
