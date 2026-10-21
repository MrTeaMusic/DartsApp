import 'package:dartlab/features/autodarts_live/domain/live_x01.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:flutter_test/flutter_test.dart';

List<List<Segment>> visits(List<List<String>> v) => [
  for (final x in v) [for (final n in x) Segment.tryParse(n)!],
];

/// Zeilen als „Aufnahme:Punkte→Rest“, Bust mit `!`, Checkout mit `#`.
List<String> rows(LiveX01 x) => [
  for (final r in x.legRows) '${r.visit}:${r.points}→${r.remaining}${r.bust ? '!' : ''}${r.checkout ? '#' : ''}',
];

void main() {
  const config = LiveX01Config();

  group('Aufnahmen des Legs (Tabelle der Arena-Ansicht)', () {
    test('abgeschlossene Aufnahmen mit Punkten und Rest, offene Aufnahme noch nicht', () {
      final x = LiveX01.replay(
        config,
        visits([
          ['T20', 'T20', 'T20'],
          ['T20', 'S20', 'S5'],
          ['T19', 'S19'],
        ]),
        const [],
        visitOpen: true,
      );
      expect(rows(x), ['0:180→321', '1:85→236']);
      expect(x.remaining, 236 - 76);
      // Mit Takeout zählt auch die dritte.
      final y = LiveX01.replay(
        config,
        visits([
          ['T20', 'T20', 'T20'],
          ['T20', 'S20', 'S5'],
          ['T19', 'S19'],
        ]),
        const [],
        visitOpen: false,
      );
      expect(rows(y), ['0:180→321', '1:85→236', '2:76→160']);
    });

    test('Bust: Punkte 0, Rest unverändert, Zeile sofort, weitere Darts zählen nicht', () {
      final x = LiveX01.replay(
        config,
        visits([
          ['T20', 'T20', 'T20'],
          ['T20', 'T20', 'T20'],
          ['T20', 'T20', 'T20'],
          ['T20', 'T20', 'S5'],
        ]),
        const [],
        visitOpen: true,
      );
      // 501 → 321 → 141 → Bust bei 141 (3x T20 = 180) → noch 141. Die vierte
      // Aufnahme hat drei Darts und gilt als abgeschlossen (auch ohne Takeout).
      expect(rows(x), ['0:180→321', '1:180→141', '2:0→141!', '3:125→16']);
      expect(x.remaining, 141 - 125);
      // Mit zwei Darts läuft sie noch.
      final y = LiveX01.replay(
        config,
        visits([
          ['T20', 'T20', 'T20'],
          ['T20', 'T20', 'T20'],
          ['T20', 'T20', 'T20'],
          ['T20', 'T20'],
        ]),
        const [],
        visitOpen: true,
      );
      expect(rows(y), ['0:180→321', '1:180→141', '2:0→141!']);
    });

    test('Checkout: Leg bleibt in der Tabelle stehen, bis die nächste Aufnahme beginnt', () {
      final seq = visits([
        ['T20', 'T20', 'T20'],
        ['T20', 'T20', 'T20'],
        ['T20', 'T19', 'D12'],
      ]);
      // 501 - 180 - 180 = 141 → T20 + T19 + D12 = 141.
      final done = LiveX01.replay(config, seq, const [], visitOpen: false);
      expect(rows(done), ['0:180→321', '1:180→141', '2:141→0#']);
      expect(done.legsWon, 1);
      expect(done.remaining, 501);
      expect(done.legDarts, 0);
      // Der erste Dart des nächsten Legs räumt die Tabelle auf.
      final next = LiveX01.replay(config, [...seq, ...visits([['S20']])], const [], visitOpen: true);
      expect(rows(next), isEmpty);
      expect(next.remaining, 481);
      final closed = LiveX01.replay(config, [...seq, ...visits([['S20', 'S20', 'S20']])], const [], visitOpen: false);
      expect(rows(closed), ['3:60→441']);
    });

    test('„Leg verloren“ und „Leg neu starten“ leeren die Tabelle', () {
      final seq = visits([
        ['T20', 'T20', 'T20'],
        ['T20', 'S20', 'S5'],
      ]);
      for (final kind in LegMarkKind.values) {
        final x = LiveX01.replay(config, seq, [(at: 6, kind: kind)], visitOpen: false);
        expect(rows(x), isEmpty, reason: kind.name);
        expect(x.remaining, 501);
      }
      // Eine Marke mitten in der Session: Aufnahmen danach beginnen eine neue Tabelle.
      final y = LiveX01.replay(
        config,
        [...seq, ...visits([['S20', 'S20', 'S20']])],
        [(at: 6, kind: LegMarkKind.lost)],
        visitOpen: false,
      );
      expect(rows(y), ['2:60→441']);
    });

    test('Korrektur rechnet die Tabelle mit neu (Replay)', () {
      final before = LiveX01.replay(config, visits([['T20', 'T20', 'T20'], ['S1', 'S1', 'S1']]), const [], visitOpen: false);
      expect(rows(before), ['0:180→321', '1:3→318']);
      final after = LiveX01.replay(config, visits([['T20', 'T20', 'T20'], ['S20', 'S1', 'S1']]), const [], visitOpen: false);
      expect(rows(after), ['0:180→321', '1:22→299']);
    });

    test('Leg-Schnitt: gezählte Darts des laufenden Legs', () {
      final x = LiveX01.replay(config, visits([['T20', 'T20', 'T20'], ['S20', 'S20']]), const [], visitOpen: true);
      expect(x.legAverage, closeTo((180 + 40) / 5 * 3, 1e-9));
      expect(LiveX01.replay(config, const [], const [], visitOpen: false).legAverage, isNull);
    });
  });
}
